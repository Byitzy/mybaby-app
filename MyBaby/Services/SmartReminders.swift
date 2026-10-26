import CoreData
import Foundation
import UIKit
import UserNotifications

// Kept with the reminders they control. All in `UserDefaults.shared`, and per phone: each parent
// chooses their own reminders.
extension SettingsKey {
    /// `FeedReminderMode`. Missing on phones set up before it existed: then `feedingReminderEnabled`
    /// decides (on is `.fixed`). `SmartReminders.start()` fills it in once.
    static let feedReminderMode = "feedReminderMode"
    /// Smart feed reminders go off this many minutes before the predicted time: 0, 5, 10 (the default) or 15.
    static let feedReminderLeadMinutes = "feedReminderLeadMinutes"
    /// "Never wait longer than…", in hours. Missing (or 0): the "every few hours" setting, or 3 hours.
    static let feedMaxIntervalHours = "feedMaxIntervalHours"
    /// "Diaper check?" reminders. Off by default.
    static let diaperReminderEnabled = "diaperReminderEnabled"
    /// "Let baby sleep": no feed reminders while a sleep is going on. Off by default.
    static let letBabySleep = "letBabySleep"
}

/// The feeding reminder, as chosen in Settings › Feed & diaper reminders.
enum FeedReminderMode: String, CaseIterable, Identifiable {
    case off
    /// A fixed time after the last feed (`feedingReminderHours`), as the reminder always worked.
    case fixed
    /// Around the time `FeedPredictor` expects the next feed.
    case smart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off", comment: "Feed reminder setting: no reminders")
        case .fixed: return String(localized: "Every few hours", comment: "Feed reminder setting")
        case .smart: return String(localized: "Smart (learns from your log)", comment: "Feed reminder setting")
        }
    }

    /// The saved choice, or, on a phone set up before smart reminders, the old on/off switch.
    static func current(_ defaults: UserDefaults = .shared) -> FeedReminderMode {
        if let raw = defaults.string(forKey: SettingsKey.feedReminderMode), let mode = FeedReminderMode(rawValue: raw) {
            return mode
        }
        return defaults.bool(forKey: SettingsKey.feedingReminderEnabled) ? .fixed : .off
    }
}

/// The feed and diaper reminders: at most one of each pending per baby (see the budget at the top of
/// `NotificationManager`), always for the next one only, worked out again whenever anything changes.
///
/// **When they're worked out again** (started once at launch, `MyBabyApp.init`):
/// - after any save that touches an entry, a marked period or a baby (`didSaveObjectsNotification`),
///   from any screen, Siri or a widget button;
/// - when the partner's changes arrive from iCloud (`NSPersistentStoreRemoteChange`). iCloud's silent
///   push wakes the app for it in the background (the `remote-notification` background mode), so a
///   reminder is usually moved before it would have gone off. If the phone couldn't sync in time, it can
///   still go off after the partner logged;
/// - when the app comes to the foreground;
/// - when a setting, the night plan or the breastfeeding timer changes (all kept in `UserDefaults`).
///
/// **Rules:**
/// - Feeds: *Every few hours* goes off that long after the last feed began; *Smart* goes off the chosen
///   lead time before `FeedPredictor`'s expected time, which never passes the parent's maximum.
/// - Diapers ("Diaper check?"): at `DiaperPredictor`'s expected time. Never while the baby is asleep; if
///   one came due during the sleep, it goes off `afterWaking` (5 min) after the baby wakes.
/// - Feeds go off during a sleep as usual (young babies may need waking), unless "Let baby sleep" is on;
///   then they wait like diaper checks.
/// - Nothing while the breastfeeding timer is running for that baby.
/// - During a night shift only the parent on duty is reminded, the same way as the wake-ups: a phone that
///   belongs to the other parent skips it, and the on-duty phone uses the night plan's alert style
///   (vibrate only, or sound). Outside shifts, and without a night plan, both phones are reminded.
/// - One reminder per feed (or change): once it went off, it isn't scheduled again until something new
///   is logged. **Snooze 15 min** puts it back, until something new is logged.
@MainActor
final class SmartReminders {
    static let shared = SmartReminders()

    /// The same prefix as the feeding reminder always had, so ones pending from before are replaced.
    nonisolated static let feedPrefix = "feeding-reminder-"
    nonisolated static let diaperPrefix = "diaper-reminder-"
    nonisolated static let category = "care-reminder"
    nonisolated static let snoozeAction = "care-snooze"
    nonisolated static let snoozeDelay: TimeInterval = 15 * 60
    /// When the reminder counts from (seconds since 1970), so it's known whether anything was logged since.
    nonisolated private static let lastEventKey = "lastEvent"
    nonisolated private static let snoozedKey = "snoozed"
    /// A reminder held during a sleep goes off this long after the baby wakes…
    static let afterWaking: TimeInterval = 5 * 60
    /// …as long as the baby woke up less than this long ago.
    static let wokeRecently: TimeInterval = 15 * 60

    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// The latest change to the pending notifications. Each waits for the one before, so they're applied in order.
    private var applying: Task<Void, Never>?

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        Self.fillInMode()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if Self.touchesCareLog(notification) { self?.scheduleRefresh() }
            }
        })
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            UIApplication.didBecomeActiveNotification,
            UserDefaults.didChangeNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        scheduleRefresh()
    }

    /// Refreshes shortly, so a burst of changes (an iCloud import, a settings screen) refreshes once.
    func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Works out every baby's next feed and diaper reminder and replaces the pending ones.
    func refresh(context: NSManagedObjectContext? = nil, now: Date = .now) {
        pending?.cancel()
        pending = nil
        // While iCloud is switched on or off the stores are being reopened and look empty.
        guard CloudStatus.shared.reloadingMessage == nil else { return }

        let context = context ?? PersistenceController.shared.viewContext
        let options = Options.load(from: .shared)
        var planned: [String: UNNotificationRequest] = [:]
        if options.mode != .off || options.diapers {
            let babies = (try? context.fetch(Baby.fetchAll())) ?? []
            let timer = FeedingTimerState.load()
            for baby in babies {
                for request in requests(for: baby, babyCount: babies.count, timer: timer, options: options, context: context, now: now) {
                    planned[request.identifier] = request
                }
            }
        }
        apply(planned)
    }

    // MARK: Working them out

    private struct Options {
        var mode: FeedReminderMode
        var diapers: Bool
        var lead: TimeInterval
        var letBabySleep: Bool
        var fixedHours: Double
        var settings: CareSettings
        var plan: NightPlan

        static func load(from defaults: UserDefaults) -> Options {
            Options(
                mode: FeedReminderMode.current(defaults),
                diapers: defaults.bool(forKey: SettingsKey.diaperReminderEnabled),
                lead: Double(defaults.object(forKey: SettingsKey.feedReminderLeadMinutes) as? Int ?? 10) * 60,
                letBabySleep: defaults.bool(forKey: SettingsKey.letBabySleep),
                fixedHours: defaults.object(forKey: SettingsKey.feedingReminderHours) as? Double ?? 3,
                settings: .load(from: defaults),
                plan: .load(from: defaults)
            )
        }
    }

    /// A reminder before the night-shift and timing rules are applied.
    private struct Planned {
        let kind: PredictionKind
        let identifier: String
        let fire: Date
        let lastEvent: Date
        let title: String
        let body: String
    }

    private func requests(
        for baby: Baby,
        babyCount: Int,
        timer: FeedingTimerState?,
        options: Options,
        context: NSManagedObjectContext,
        now: Date
    ) -> [UNNotificationRequest] {
        let log = CareLog.load(for: baby, context: context, now: now, plan: options.plan, timer: timer)
        // Breastfeeding now: worked out again when the timer's feed is saved.
        guard !log.isFeedingNow else { return [] }
        let key = baby.uuid?.uuidString ?? baby.objectID.uriRepresentation().absoluteString
        let feed = FeedPredictor.predict(log, settings: options.settings, now: now)

        var planned: [Planned] = []
        if let reminder = Self.feedReminder(log: log, prediction: feed, name: baby.displayName, babyCount: babyCount, key: key, options: options, now: now) {
            planned.append(reminder)
        }
        if options.diapers,
           let reminder = Self.diaperReminder(log: log, prediction: DiaperPredictor.predict(log, nextFeed: feed, now: now), name: baby.displayName, key: key, now: now) {
            planned.append(reminder)
        }
        return planned.compactMap { Self.request($0, plan: options.plan, now: now) }
    }

    private static func feedReminder(
        log: CareLog,
        prediction: CarePrediction?,
        name: String,
        babyCount: Int,
        key: String,
        options: Options,
        now: Date
    ) -> Planned? {
        guard let last = FeedPredictor.sessions(log.feeds.filter { $0.start <= now }).last else { return nil }
        var fire: Date
        let title: String
        let body: String
        switch options.mode {
        case .off:
            return nil
        case .fixed:
            let interval = options.fixedHours * 3600
            fire = last.start.addingTimeInterval(interval)
            let duration = Format.duration(interval)
            title = babyCount > 1
                ? String(localized: "Time to feed \(name)? 🍼", comment: "Feed reminder title, with twins or siblings; the baby's name")
                : String(localized: "Feeding time? 🍼", comment: "Feed reminder title")
            body = babyCount > 1
                ? String(localized: "It's been \(duration) since \(name)'s last feeding.", comment: "Feed reminder; a duration like 3h, then the baby's name")
                : String(localized: "It's been \(duration) since the last feeding.", comment: "Feed reminder; a duration like 3h")
        case .smart:
            guard let prediction else { return nil }
            fire = prediction.expected.addingTimeInterval(-options.lead)
            title = babyCount > 1
                ? String(localized: "Feeding time soon for \(name)? 🍼", comment: "Smart feed reminder title, with twins or siblings; the baby's name")
                : String(localized: "Feeding time soon? 🍼", comment: "Smart feed reminder title")
            body = smartFeedBody(name: name, prediction: prediction)
        }
        if options.letBabySleep {
            guard let held = holdingForSleep(fire, log: log, now: now) else { return nil }
            fire = held
        }
        return Planned(kind: .feed, identifier: feedPrefix + key, fire: fire, lastEvent: last.start, title: title, body: body)
    }

    /// "Mavie will probably be hungry around 2:40 AM (usually every 2 h 50 min)." Each reason is its
    /// own sentence, so it reads naturally in every language; the reasons are the same as
    /// `CarePrediction.reminderReason`.
    private static func smartFeedBody(name: String, prediction: CarePrediction) -> String {
        let time = CarePredictions.time(prediction.expected)
        let since = CarePredictions.describe(prediction.expected.timeIntervalSince(prediction.lastEvent))
        if prediction.wasCapped {
            return String(
                localized: "\(name) will probably be hungry around \(time) (your \(since) limit).",
                comment: "Smart feed reminder; the baby's name, a time, then the longest wait the parent set, like 3 h"
            )
        }
        if let usual = prediction.usualInterval, prediction.confidence > .low {
            let every = CarePredictions.describe(usual)
            return String(
                localized: "\(name) will probably be hungry around \(time) (usually every \(every)).",
                comment: "Smart feed reminder; the baby's name, a time, then the usual time between feeds, like 2 h 50 min"
            )
        }
        return String(
            localized: "\(name) will probably be hungry around \(time) (\(since) since the last feed).",
            comment: "Smart feed reminder; the baby's name, a time, then a duration like 3 h"
        )
    }

    private static func diaperReminder(log: CareLog, prediction: CarePrediction?, name: String, key: String, now: Date) -> Planned? {
        guard let prediction, let fire = holdingForSleep(prediction.expected, log: log, now: now) else { return nil }
        let since = CarePredictions.describe(fire.timeIntervalSince(prediction.lastEvent))
        return Planned(
            kind: .diaper,
            identifier: diaperPrefix + key,
            fire: fire,
            lastEvent: prediction.lastEvent,
            title: String(localized: "Diaper check for \(name)? 🧷", comment: "Diaper reminder title; the baby's name"),
            body: String(localized: "It's been \(since) since the last change.", comment: "Diaper reminder; a duration like 2 h 30 min")
        )
    }

    /// `fire`, or `nil` while the baby is asleep (it's worked out again when the sleep ends). One that
    /// came due during the sleep goes off `afterWaking` after the baby wakes, if that's still to come.
    private static func holdingForSleep(_ fire: Date, log: CareLog, now: Date) -> Date? {
        if log.isAsleep(at: now) { return nil }
        guard fire <= now,
              let sleep = log.lastFinishedSleep, let woke = sleep.end,
              woke > now.addingTimeInterval(-wokeRecently), fire >= sleep.start
        else { return fire }
        return woke.addingTimeInterval(afterWaking)
    }

    /// The notification, or `nil` when it's already past or it's for the parent who's off duty.
    private static func request(_ planned: Planned, plan: NightPlan, now: Date) -> UNNotificationRequest? {
        let interval = planned.fire.timeIntervalSince(now)
        guard interval > 1 else { return nil }
        // During a night shift, only the phone of the parent on duty, as with the wake-ups.
        let shift = plan.shift(at: planned.fire)
        if let shift, !plan.alarmOwner.includes(shift.parent) { return nil }

        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = shift == nil ? UNNotificationSound.default : NotificationManager.notificationSound(for: plan.alarmStyle)
        // A feed on a night shift gets through a Focus like the wake-ups; a diaper check never pushes in.
        content.interruptionLevel = planned.kind == .feed && shift != nil ? .timeSensitive : .active
        content.categoryIdentifier = category
        content.threadIdentifier = planned.identifier
        content.userInfo = [lastEventKey: planned.lastEvent.timeIntervalSince1970]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger)
    }

    // MARK: Pending notifications

    private func apply(_ planned: [String: UNNotificationRequest]) {
        let previous = applying
        applying = Task {
            await previous?.value
            await Self.replacePending(with: planned)
        }
    }

    /// Removes the feed and diaper reminders that no longer apply and adds the new ones, keeping a
    /// snoozed one, and not repeating one that already went off, until something new is logged.
    private static func replacePending(with planned: [String: UNNotificationRequest]) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().filter { isOurs($0.identifier) }
        let stale = ours.map(\.identifier).filter { planned[$0] == nil }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard !planned.isEmpty else { return }

        // Only Settings asks for permission, never a refresh in the background.
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let delivered = await center.deliveredNotifications().map(\.request)

        for (identifier, request) in planned {
            let event = lastEvent(of: request.content)
            if let snoozed = ours.first(where: { $0.identifier == identifier }),
               snoozed.content.userInfo[snoozedKey] as? Bool == true,
               lastEvent(of: snoozed.content) == event {
                continue
            }
            if delivered.contains(where: { $0.identifier == identifier && lastEvent(of: $0.content) == event }) {
                continue
            }
            // The same identifier replaces the one already pending.
            try? await center.add(request)
        }
    }

    // MARK: Snooze

    /// "Snooze 15 min" on a feed or diaper reminder.
    nonisolated static var notificationCategory: UNNotificationCategory {
        let snooze = UNNotificationAction(
            identifier: snoozeAction,
            title: String(localized: "Snooze 15 min", comment: "Notification button on a feed or diaper reminder"),
            options: []
        )
        return UNNotificationCategory(identifier: category, actions: [snooze], intentIdentifiers: [], options: [])
    }

    /// Puts a snoozed reminder back in 15 minutes. Called by the app's notification delegate.
    nonisolated static func handle(_ response: UNNotificationResponse) async {
        let request = response.notification.request
        guard response.actionIdentifier == snoozeAction, isOurs(request.identifier),
              let content = request.content.mutableCopy() as? UNMutableNotificationContent
        else { return }
        var info = content.userInfo
        info[snoozedKey] = true
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeDelay, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        )
    }

    // MARK: Helpers

    nonisolated private static func isOurs(_ identifier: String) -> Bool {
        identifier.hasPrefix(feedPrefix) || identifier.hasPrefix(diaperPrefix)
    }

    nonisolated private static func lastEvent(of content: UNNotificationContent) -> Double? {
        content.userInfo[lastEventKey] as? Double
    }

    private static func touchesCareLog(_ notification: Notification) -> Bool {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is Activity || $0 is TrackingPeriod || $0 is Baby }
        }
    }

    /// Saves the feeding reminder's mode on phones set up before it existed, so Settings shows it.
    private static func fillInMode() {
        let defaults = UserDefaults.shared
        guard defaults.object(forKey: SettingsKey.feedReminderMode) == nil else { return }
        defaults.set(FeedReminderMode.current(defaults).rawValue, forKey: SettingsKey.feedReminderMode)
    }
}
