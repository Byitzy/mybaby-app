import CoreData
import Foundation
import WatchConnectivity

/// The iPhone's side of the Apple Watch app.
///
/// The watch never opens the database. The two talk only through Apple's WatchConnectivity, directly
/// between this iPhone and its paired watch, with no server in between:
/// - **iPhone → watch:** whenever `WidgetSnapshotWriter` rebuilds the widgets' snapshot, `send(_:)` wraps it
///   in a `WatchContext` (adding the ml/oz bottle buttons, recent medicines and the suggested side) and,
///   if anything changed, hands it to `updateApplicationContext`. The system keeps only the latest one and
///   delivers it when the watch is next in reach.
/// - **watch → iPhone:** each tap on the watch is a `WatchCommand`. It arrives as a message when the
///   phone is reachable (and the system launches this app in the background for it if needed), or later
///   as a queued user info transfer. `handle(_:)` runs it through the same code as Siri and the widgets
///   (`QuickLog`, `FeedingTimer`) at the time it was tapped, and the reply is the fresh context.
/// - **Medicine on the allergy list:** a medicine that matches the baby's allergy list is never logged
///   from the watch. The context marks such medicines (the watch shows ⚠︎ and doesn't send them), and
///   if one arrives anyway (the list changed while the watch was away) it isn't logged: the reply, and
///   the contexts for a while after, carry a `WatchContext.Refusal` saying why, which the watch shows.
///
/// Started once at launch (`MyBabyApp.init`), next to `WidgetSnapshotWriter`.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    /// What was last sent, so unchanged contexts aren't sent again.
    private var lastSent: WatchContext?

    private override init() {
        super.init()
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func start() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: iPhone → watch

    /// Sends the context for `snapshot` to the watch, if there is one with MyBaby installed and the
    /// context changed since the last send (or `force`).
    func send(_ snapshot: WidgetSnapshot?, force: Bool = false) {
        guard canSend else { return }
        sendContext(Self.makeContext(snapshot: snapshot), force: force)
    }

    /// Whether there's a watch with MyBaby installed to send to.
    private var canSend: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    /// Sends `context`, already made, if it changed since the last send (or `force`).
    private func sendContext(_ context: WatchContext, force: Bool) {
        guard let session, canSend else { return }
        if !force, let lastSent, context.hasSameContent(as: lastSent) { return }
        do {
            try session.updateApplicationContext(context.message)
            lastSent = context
        } catch {
            // Not reachable right now in a way the system can't queue (e.g. mid-switch between watches).
            // The next change, or the session reactivating, sends it again.
        }
    }

    /// After Delete all MyBaby data: sends a context with no baby, which the watch shows as its empty
    /// state ("Add your baby in MyBaby on your iPhone") in place of the deleted log, and its
    /// complications as "Open MyBaby". Delivered when the watch is next in reach if it isn't now.
    func sendEmpty() {
        lastSent = nil
        send(nil, force: true)
    }

    /// Rebuilds the context from the log and sends it.
    func sendCurrent(force: Bool = false) {
        // While iCloud is switched on or off the stores are being reopened and look empty.
        guard CloudStatus.shared.reloadingMessage == nil else { return }
        send(WidgetSnapshot.make(context: QuickLog.context), force: force)
    }

    /// The context for `snapshot`: the widgets' summary plus what the watch's buttons need.
    static func makeContext(snapshot: WidgetSnapshot?) -> WatchContext {
        let context = QuickLog.context
        let unit = VolumeUnit(rawValue: UserDefaults.shared.string(forKey: SettingsKey.volumeUnit) ?? "") ?? .ml
        var watch = WatchContext(snapshot: snapshot)
        // The watch app shows the baby shown on the iPhone (the top-level fields). Its complications can
        // be set to any baby, so every baby's part goes too, trimmed to what they show: the application
        // context has to stay small.
        watch.snapshot?.babies = snapshot?.babies?.map(\.forWatchComplications)
        // The watch shows nothing of cry alerts, and leaving it out keeps a cry from resending the context.
        watch.snapshot?.listening = nil
        watch.volumeUnit = unit.rawValue
        watch.bottlePresets = unit.presets.map { value in
            WatchContext.BottlePreset(title: unit.format(value: value), ml: unit.toML(value))
        }
        guard snapshot != nil, let baby = Baby.current(in: context) else { return watch }
        // Fetched once for all the medicines.
        let allergies = baby.allergyList()
        watch.medicines = QuickLog.recentMedicines(for: baby, limit: 6).map { medicine in
            let matches = AllergyMatch.medicineAllergies(matching: medicine.name, in: allergies).map(\.displayName)
            return WatchContext.Medicine(
                name: medicine.name,
                dosage: medicine.dosage,
                allergies: matches.isEmpty ? nil : matches
            )
        }
        watch.suggestedSide = FeedingTimer.suggestion(for: baby, in: context)?.side
        watch.lastBottle = lastBottle(for: baby)
        watch.refusal = recentRefusal()
        // Well under WatchConnectivity's limit even with several babies; should it ever grow past this,
        // the complications set to a particular baby show the one shown on the iPhone instead.
        if (watch.encoded()?.count ?? 0) > Self.maxContextBytes {
            watch.snapshot?.babies = nil
        }
        return watch
    }

    /// Application contexts and replies have to stay small (WatchConnectivity's messages are limited to
    /// about 64 KB). A typical context is a few KB.
    private static let maxContextBytes = 48_000

    private static func lastBottle(for baby: Baby) -> WatchCommand.Bottle? {
        let request = baby.entries(Activity.fetch(
            NSPredicate(
                format: "kindRaw == %@ AND feedingTypeRaw IN %@",
                ActivityKind.feeding.rawValue,
                [FeedingType.breastMilkBottle.rawValue, FeedingType.formula.rawValue] as NSArray
            ),
            limit: 1
        ))
        switch (try? QuickLog.context.fetch(request).first)?.feedingType {
        case .formula: return .formula
        case .breastMilkBottle: return .breastMilk
        default: return nil
        }
    }

    // MARK: watch → iPhone

    /// Runs `command` (unless it already ran) and returns the reply: the fresh context.
    func handle(_ command: WatchCommand) -> [String: Any] {
        var handled = Self.handledCommands()
        if command.action == .sync {
            // Nothing to log or remember.
        } else if !handled.contains(where: { $0.id == command.id }) {
            let record = perform(command)
            handled.append(record)
            Self.saveHandledCommands(handled)
        }
        guard CloudStatus.shared.reloadingMessage == nil else { return [:] }
        var context = Self.makeContext(snapshot: WidgetSnapshot.make(context: QuickLog.context))
        // This tap's own refusal, also when it arrived twice, so the watch can show why.
        if let record = handled.first(where: { $0.id == command.id }), let message = record.refusal {
            context.refusal = WatchContext.Refusal(commandID: command.id, message: message)
        }
        // Keeps the application context in step too, for when this reply doesn't make it back. The
        // same context as the reply, made once: making it reads the log.
        sendContext(context, force: false)
        return context.message
    }

    /// What a command did, so it isn't done twice and can be undone.
    private struct Handled: Codable {
        var id: UUID
        /// `Activity.uuid` of the entry it added, or of the sleep it ended.
        var activityID: String?
        /// True when it ended a sleep (undo reopens it) rather than adding an entry (undo deletes it).
        var endedSleep = false
        /// Why it wasn't logged (a medicine on the baby's allergy list), for the watch to show.
        var refusal: String? = nil
        /// When that was, so later contexts carry it only for a while.
        var refusedAt: Date? = nil
    }

    /// How long contexts keep carrying the latest refusal, for a watch that was out of reach.
    private static let refusalLifetime: TimeInterval = 12 * 3600

    /// The latest tap that wasn't logged, while it's recent.
    private static func recentRefusal(now: Date = .now) -> WatchContext.Refusal? {
        guard let record = handledCommands().last(where: { $0.refusal != nil }),
              let message = record.refusal,
              let refusedAt = record.refusedAt,
              now.timeIntervalSince(refusedAt) < refusalLifetime
        else { return nil }
        return WatchContext.Refusal(commandID: record.id, message: message)
    }

    private func perform(_ command: WatchCommand) -> Handled {
        var record = Handled(id: command.id)
        let context = QuickLog.context
        let baby = Self.baby(for: command, in: context)
        // A queued command logs at the time it was tapped, but never in the future (clocks can differ).
        let date = min(command.date, .now)
        do {
            switch command.action {
            case .sync:
                break
            case .logDiaper(let diaper):
                record.activityID = try insert(.diaper, for: baby, at: date) { $0.diaperType = diaper.diaperType }
            case .logBottle(let type, let ml):
                guard ml > 0, ml <= 1000 else { break }
                record.activityID = try insert(.feeding, for: baby, at: date) { feed in
                    feed.feedingType = type == .formula ? .formula : .breastMilkBottle
                    feed.amountML = ml
                }
            case .logMedicine(let name):
                let medicine = name.trimmingCharacters(in: .whitespaces)
                guard !medicine.isEmpty else { break }
                // Never from the wrist when it's on the baby's allergy list: that's for the iPhone, after
                // checking with a doctor or pharmacist. The watch shows why (`WatchContext.Refusal`).
                if let baby, let allergy = baby.medicineAllergies(matching: medicine).first {
                    record.refusal = WatchContext.allergyMessage(babyName: baby.displayName, allergyName: allergy.displayName)
                    record.refusedAt = .now
                    break
                }
                // The spelling and dose logged before, as the Siri intent does. The watch shows that dose
                // on the button, so the parent sees what's recorded; it never suggests one.
                let previous = QuickLog.recentMedicines(limit: 50).first { $0.name.lowercased() == medicine.lowercased() }
                record.activityID = try insert(.medication, for: baby, at: date) { entry in
                    entry.medicationName = previous?.name ?? medicine
                    entry.dosage = previous?.dosage ?? ""
                }
            case .startSleep:
                // The watch may be out of date (e.g. the partner just started one).
                guard Self.ongoingSleep(for: baby, in: context) == nil else { break }
                record.activityID = try insert(.sleep, for: baby, at: date)
            case .endSleep:
                guard let sleep = Self.ongoingSleep(for: baby, in: context), let id = sleep.uuid?.uuidString else { break }
                QuickLog.endSleep(id: id, at: date)
                record.activityID = id
                record.endedSleep = true
            case .timerStart(let side):
                FeedingTimer.shared.start(side, baby: baby, at: timerDate(date))
            case .timerSwitch:
                FeedingTimer.shared.switchSide(at: timerDate(date))
            case .timerStop:
                FeedingTimer.shared.finish(context: context, at: timerDate(date))
            case .undo(let id):
                undo(id)
            case .acknowledgeWakeUp(let notificationID):
                // "I'm up" on the watch: stop the rest of the buzzes, as answering it here does.
                Task { await NotificationManager.cancelWakeUpGroup(for: notificationID) }
            }
        } catch {
            // No baby yet: there's nothing to log to. The reply tells the watch so.
        }
        return record
    }

    /// Adds an entry like `QuickLog.insert`, for `baby` (which may not be the one shown in the app),
    /// and returns its `uuid`.
    private func insert(
        _ kind: ActivityKind,
        for baby: Baby?,
        at date: Date,
        configure: (Activity) -> Void = { _ in }
    ) throws -> String? {
        let activity = try QuickLog.insert(kind, at: date) { entry in
            // `create` attached the baby shown in the app; the watch may have been showing the other twin.
            if let baby, entry.baby != baby {
                if let store = baby.objectID.persistentStore {
                    QuickLog.context.assign(entry, to: store)
                }
                entry.baby = baby
            }
            configure(entry)
        }
        return activity.uuid?.uuidString
    }

    /// A breastfeeding timer change from the watch, never before the timer's last change, so a late
    /// command can't count the same minutes twice.
    private func timerDate(_ date: Date) -> Date {
        guard let state = FeedingTimer.shared.state else { return date }
        return max(date, state.segmentStart)
    }

    /// Takes back what the command with `id` logged.
    private func undo(_ id: UUID) {
        guard let record = Self.handledCommands().first(where: { $0.id == id }),
              let activityID = record.activityID,
              let uuid = UUID(uuidString: activityID)
        else { return }
        let context = QuickLog.context
        let request = Activity.fetch(NSPredicate(format: "uuid == %@", uuid as NSUUID), limit: 1)
        guard let activity = try? context.fetch(request).first else { return }
        let wasFeeding = activity.kind == .feeding
        if record.endedSleep {
            activity.endDate = nil
        } else {
            context.delete(activity)
        }
        QuickLog.save(refreshingFeedingReminder: wasFeeding)
    }

    /// The baby the watch was showing, or the one shown in the app.
    private static func baby(for command: WatchCommand, in context: NSManagedObjectContext) -> Baby? {
        if let id = command.babyID,
           let babies = try? context.fetch(Baby.fetchAll()),
           let baby = babies.first(where: { $0.uuid?.uuidString == id }) {
            return baby
        }
        return Baby.current(in: context)
    }

    private static func ongoingSleep(for baby: Baby?, in context: NSManagedObjectContext) -> Activity? {
        guard let baby else { return nil }
        return try? context.fetch(baby.entries(Activity.ongoingSleep)).first
    }

    // MARK: Commands already handled

    /// Kept on this iPhone (`UserDefaults.standard`): the last few commands, by `id`.
    private static let handledKey = "watchHandledCommands"

    private static func handledCommands() -> [Handled] {
        guard let data = UserDefaults.standard.data(forKey: handledKey) else { return [] }
        return (try? JSONDecoder().decode([Handled].self, from: data)) ?? []
    }

    private static func saveHandledCommands(_ handled: [Handled]) {
        if let data = try? JSONEncoder().encode(Array(handled.suffix(50))) {
            UserDefaults.standard.set(data, forKey: handledKey)
        }
    }
}

// MARK: - WCSessionDelegate

// WatchConnectivity calls these on a background queue; each hops to the main actor, where the log is.
extension WatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { WatchBridge.shared.sendCurrent(force: true) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The parent switched to another watch: start talking to that one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed, or a watch paired.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { WatchBridge.shared.sendCurrent(force: true) }
        }
    }

    /// A tap on the watch while the phone is reachable. The reply carries the fresh context.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = WatchCommand(userInfo: message) else {
            replyHandler([:])
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                replyHandler(WatchBridge.shared.handle(command))
            }
        }
    }

    /// A tap that was queued on the watch while the phone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let command = WatchCommand(userInfo: userInfo) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = WatchBridge.shared.handle(command)
            }
        }
    }
}

extension WidgetSnapshot.BabySnapshot {
    /// Only what the watch face complications show (the last feed and diaper, asleep or awake, the
    /// next medicine dose and today's diapers), to keep the application context small. The rest is for
    /// the iPhone's Home Screen widgets and their buttons.
    var forWatchComplications: Self {
        var trimmed = self
        trimmed.sleepID = nil
        trimmed.lastPumping = nil
        trimmed.stash = nil
        trimmed.lastMedicine = nil
        trimmed.usualBottle = nil
        trimmed.nextFeedExpected = nil
        return trimmed
    }
}

extension WatchCommand.Diaper {
    var diaperType: DiaperType {
        switch self {
        case .wet: return .wet
        case .dirty: return .dirty
        case .both: return .mixed
        }
    }
}
