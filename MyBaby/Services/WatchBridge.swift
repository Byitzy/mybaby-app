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
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled
        else { return }
        let context = Self.makeContext(snapshot: snapshot)
        if !force, let lastSent, context.hasSameContent(as: lastSent) { return }
        do {
            try session.updateApplicationContext(context.message)
            lastSent = context
        } catch {
            // Not reachable right now in a way the system can't queue (e.g. mid-switch between watches).
            // The next change, or the session reactivating, sends it again.
        }
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
        // The watch shows only the baby shown on the iPhone, so it gets only theirs (the top-level fields).
        watch.snapshot?.babies = nil
        watch.volumeUnit = unit.rawValue
        watch.bottlePresets = unit.presets.map { value in
            WatchContext.BottlePreset(title: unit.format(value: value), ml: unit.toML(value))
        }
        guard snapshot != nil, let baby = Baby.current(in: context) else { return watch }
        watch.medicines = QuickLog.recentMedicines(limit: 6).map { WatchContext.Medicine(name: $0.name, dosage: $0.dosage) }
        watch.suggestedSide = FeedingTimer.suggestion(for: baby, in: context)?.side
        watch.lastBottle = lastBottle(for: baby)
        return watch
    }

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
        let snapshot = WidgetSnapshot.make(context: QuickLog.context)
        // Keeps the application context in step too, for when this reply doesn't make it back.
        send(snapshot)
        return Self.makeContext(snapshot: snapshot).message
    }

    /// What a command did, so it isn't done twice and can be undone.
    private struct Handled: Codable {
        var id: UUID
        /// `Activity.uuid` of the entry it added, or of the sleep it ended.
        var activityID: String?
        /// True when it ended a sleep (undo reopens it) rather than adding an entry (undo deletes it).
        var endedSleep = false
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

extension WatchCommand.Diaper {
    var diaperType: DiaperType {
        switch self {
        case .wet: return .wet
        case .dirty: return .dirty
        case .both: return .mixed
        }
    }
}
