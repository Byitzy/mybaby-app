import CoreData
import Foundation
import UserNotifications

/// iOS keeps at most 64 pending notifications per app and silently drops the rest. MyBaby's share:
/// - night shifts: `nightShiftNights` (4) nights × (1 bedtime heads-up + `wakeUpRepeats` (5) buzzes) = 24
/// - appointments: the next `maxAppointmentReminders` (8)
/// - "How did it go?" after a visit: the next 3 (`VisitFollowUp`)
/// - medicine dose alerts: the next 10 (`CareReminders.maxMedicineReminders`)
/// - milk stash: the next 10 mornings (`CareReminders.maxMilkReminders`)
/// - Parent care's check-in: 1 (repeating)
/// - "Haven't logged in a while": 1, for the baby shown (`GapReminder`)
/// - the diary's "month birthday" nudge: 1, the next one only (`DiaryReminder`)
/// - feed & diaper reminders: at most 2 per baby, only the next feed and the next diaper check
///   (`SmartReminders`; "Snooze 15 min" replaces its own reminder rather than adding one)
/// That's 58 plus two per baby (62 with twins, 64 with triplets). Cry alerts are delivered at once, so they're never pending.
/// Alerts from a nursery monitor don't count either: they're CloudKit pushes, not local
/// notifications (see `AlertInboxes`).
enum NotificationManager {
    private static var center: UNUserNotificationCenter { .current() }
    /// How many upcoming appointments get a reminder; the rest are scheduled as these go by.
    private static let maxAppointmentReminders = 8

    /// Asks for permission the first time; afterwards returns the current answer without prompting.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func cancel(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: Appointments

    static func scheduleReminder(for appointment: Appointment) {
        let identifier = appointment.notificationID
        cancel(identifier)
        guard let minutes = appointment.reminderMinutes else { return }

        let fireDate = appointment.date.addingTimeInterval(-Double(minutes) * 60)
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = appointment.title.isEmpty ? "Appointment" : appointment.title
        let time = appointment.date.formatted(date: minutes >= 1440 ? .abbreviated : .omitted, time: .shortened)
        let place = [appointment.provider, appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = minutes == 0 ? "Starting now" : "Starts at \(time)"
        if !place.isEmpty { content.body += " · \(place)" }
        content.sound = .default

        schedule(identifier: identifier, content: content, at: fireDate)
    }

    /// Re-schedules reminders for every upcoming appointment, including ones the other parent added.
    @MainActor
    static func refreshAppointmentReminders(context: NSManagedObjectContext) {
        let request = Appointment.fetchAll()
        request.predicate = NSPredicate(format: "date > %@", Date.now as NSDate)
        // Only the soonest ones, to stay within iOS's 64 pending notifications (see above).
        let upcoming = ((try? context.fetch(request)) ?? [])
            .filter { $0.reminderMinutes != nil }
            .sorted { reminderDate(for: $0) < reminderDate(for: $1) }
            .prefix(maxAppointmentReminders)
        let keep = Set(upcoming.map(\.notificationID))

        // Drop reminders for appointments that were deleted on the other phone.
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("appointment-") && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for appointment in upcoming {
            scheduleReminder(for: appointment)
        }
    }

    private static func reminderDate(for appointment: Appointment) -> Date {
        appointment.date.addingTimeInterval(-Double(appointment.reminderMinutes ?? 0) * 60)
    }

    // MARK: Feeding reminder

    /// Re-schedules each baby's feed and diaper reminders from the log (`SmartReminders`), one of each
    /// per baby so twins each get theirs. Call after a feeding is added, edited or deleted; saves, the
    /// partner's changes and settings changes are picked up by `SmartReminders` by themselves too.
    @MainActor
    static func refreshFeedingReminder(context: NSManagedObjectContext) {
        context.saveIfChanged()
        SmartReminders.shared.refresh(context: context)
    }

    // MARK: Night shifts

    private static let nightShiftPrefix = "night-shift-"

    /// Shared with the Apple Watch app, which registers the same category so "I'm up" works there too.
    static let wakeUpCategory = WakeUpNotification.category
    private static let imUpAction = WakeUpNotification.imUpAction

    /// How many times a wake-up buzzes, and how far apart, until it's answered.
    private static let wakeUpRepeats = 5
    private static let wakeUpSpacing: TimeInterval = 30
    /// How many nights ahead are scheduled. The window rolls forward every time the app comes to
    /// the foreground; a full week (42) would leave too little of the 64 for everything else.
    private static let nightShiftNights = 4

    /// Cry alerts, from this phone's own listening and from a nursery monitor's pushes (whose
    /// subscription names the same category). Tapping one opens Today.
    static let cryAlertCategory = "cry-alert"

    /// Adds the "I'm up" button to wake-up reminders. Dismissing one counts as an answer too.
    static func registerCategories() {
        let imUp = UNNotificationAction(identifier: imUpAction, title: "I'm up", options: [])
        let wakeUp = UNNotificationCategory(
            identifier: wakeUpCategory,
            actions: [imUp],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let cryAlert = UNNotificationCategory(
            identifier: cryAlertCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([wakeUp, cryAlert, SmartReminders.notificationCategory])
    }

    /// Replaces the night-shift reminders with ones for the next `nightShiftNights` nights of the plan.
    /// Call when the plan changes and whenever the app comes to the foreground, so the window keeps rolling.
    /// At most 24 pending notifications (see the budget at the top).
    static func refreshNightShiftReminders() async {
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(nightShiftPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let plan = NightPlan.load()
        guard plan.isEnabled, plan.wakeUpAlarms || plan.bedtimeHeadsUp else { return }
        guard await requestAuthorization() else { return }

        let now = Date.now
        let sound = notificationSound(for: plan.alarmStyle)
        for night in plan.upcomingNights(from: now, count: nightShiftNights) {
            guard let first = night.first else { continue }

            // Heads-up at the start of the night: who's on, and when the handoff is.
            if plan.bedtimeHeadsUp, first.start > now {
                let content = UNMutableNotificationContent()
                content.title = "🌙 Tonight's shifts"
                content.body = night
                    .map { "\(plan.name(of: $0.parent)) \(timeRange($0))" }
                    .joined(separator: ", then ")
                content.sound = sound
                await add(nightShiftPrefix + "bedtime-\(Int(first.start.timeIntervalSince1970))", content, at: first.start)
            }

            // Wake-up for whoever takes over mid-night. It repeats until they tap "I'm up",
            // because a single silent buzz is easy to sleep through.
            guard plan.wakeUpAlarms else { continue }
            for (previous, shift) in zip(night, night.dropFirst())
            where shift.start > now && plan.alarmOwner.includes(shift.parent) {
                let content = UNMutableNotificationContent()
                content.title = "⏰ Your turn, \(plan.name(of: shift.parent))"
                content.body = "Take over from \(plan.name(of: previous.parent)). You're on until \(shift.end.formatted(date: .omitted, time: .shortened))."
                content.sound = sound
                content.interruptionLevel = .timeSensitive
                content.categoryIdentifier = wakeUpCategory
                content.threadIdentifier = "night-shift-\(Int(shift.start.timeIntervalSince1970))"

                let group = wakeUpGroup(for: shift)
                for attempt in 0..<wakeUpRepeats {
                    let date = shift.start.addingTimeInterval(Double(attempt) * wakeUpSpacing)
                    await add(group + "\(attempt)", content, at: date)
                }
            }
        }
    }

    /// Stops the remaining buzzes once someone answers a wake-up.
    static func handle(_ response: UNNotificationResponse) async {
        // "Snooze 15 min" on a feed or diaper reminder.
        await SmartReminders.handle(response)
        guard response.notification.request.content.categoryIdentifier == wakeUpCategory else { return }
        await cancelWakeUpGroup(for: response.notification.request.identifier)
    }

    /// Removes the pending and delivered buzzes of the wake-up that `identifier` (one of its buzzes)
    /// belongs to. Also used for "I'm up" on the Apple Watch (`WatchBridge`).
    static func cancelWakeUpGroup(for identifier: String) async {
        guard identifier.hasPrefix(nightShiftPrefix + "wake-"),
              let lastDash = identifier.lastIndex(of: "-") else { return }
        let group = String(identifier[...lastDash])

        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(group) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(group) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    /// Buzzes this phone right away because the baby is crying.
    static func sendCryAlert(title: String, body: String, style: AlarmStyle) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(for: style)
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "cry-alerts"
        content.categoryIdentifier = cryAlertCategory
        // A nil trigger delivers immediately.
        let request = UNNotificationRequest(identifier: "cry-\(UUID().uuidString)", content: content, trigger: nil)
        Task {
            guard await requestAuthorization() else { return }
            try? await center.add(request)
        }
    }

    /// Shared prefix for all the buzzes of one wake-up, e.g. "night-shift-wake-1761364800-".
    private static func wakeUpGroup(for shift: NightShift) -> String {
        nightShiftPrefix + "wake-\(Int(shift.start.timeIntervalSince1970))-"
    }

    /// "Vibrate only" plays a silent sound: iPhone still buzzes for it, but nobody else hears anything.
    static func notificationSound(for style: AlarmStyle) -> UNNotificationSound {
        switch style {
        case .vibrate: return UNNotificationSound(named: UNNotificationSoundName("silence.wav"))
        case .sound: return .default
        }
    }

    private static func timeRange(_ shift: NightShift) -> String {
        let start = shift.start.formatted(date: .omitted, time: .shortened)
        let end = shift.end.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }

    private static func add(_ identifier: String, _ content: UNNotificationContent, at date: Date) async {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    // MARK: Helpers

    private static func schedule(identifier: String, content: UNNotificationContent, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            guard await requestAuthorization() else { return }
            try? await center.add(request)
        }
    }
}
