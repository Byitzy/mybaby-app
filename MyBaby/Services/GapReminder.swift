import CoreData
import Foundation
import UserNotifications

/// "Haven't logged in a while": an optional nudge when a gap in the log begins (see `Coverage`), so a
/// stretch nobody logged can be caught up or marked as not tracked while it's still fresh.
///
/// Off by default (Settings › Reminders). One pending notification at most, for the baby shown in the
/// app (see the budget at the top of `NotificationManager`). It's worked out again whenever the log
/// changes, here or on the partner's phone (`WidgetSnapshotWriter` calls `refresh`), so logging
/// anything pushes it back.
///
/// It never buzzes the parent who's off duty: during a night shift that this iPhone's owner isn't on, it
/// waits until that shift ends. Without a night plan it waits for the morning (7 AM) instead of going off
/// at night.
enum GapReminder {
    static let identifier = "tracking-gap"

    @MainActor
    static func refresh(context: NSManagedObjectContext, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard UserDefaults.shared.bool(forKey: SettingsKey.gapReminderEnabled),
              let baby = Baby.current(in: context)
        else { return }

        // The latest few entries and periods are enough to find when the log last had something.
        let recent = (try? context.fetch(baby.entries(Activity.fetch(limit: 20)))) ?? []
        let ongoing = (try? context.fetch(baby.entries(Activity.ongoingSleep))) ?? []
        let periodRequest = baby.entries(TrackingPeriod.fetchAll())
        periodRequest.fetchLimit = 10
        let periods = (try? context.fetch(periodRequest)) ?? []
        guard ongoing.isEmpty, !(recent.isEmpty && periods.isEmpty) else { return }

        let plan = NightPlan.load()
        let calendar = Calendar.current
        let coverage = Coverage(activities: recent, periods: periods, now: now, plan: plan, calendar: calendar)
        // Something is still going on (a period that ends later), or the gap has already begun: Today
        // shows it, and a late notification wouldn't help.
        guard let last = lastTracked(in: recent, periods: periods, now: now) else { return }
        let begins = Coverage.gapBegins(after: last, night: coverage.night, calendar: calendar)
        let fire = allowedTime(for: begins.addingTimeInterval(60), plan: plan, night: coverage.night, calendar: calendar)
        guard fire > now.addingTimeInterval(1), coverage.currentGap(now: now) == nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Haven't logged in a while"
        let since = last.formatted(date: calendar.isDate(last, inSameDayAs: fire) ? .omitted : .abbreviated, time: .shortened)
        content.body = "Nothing logged for \(baby.displayName) since \(since). Catch up, or mark the time as not tracked."
        content.sound = .default
        content.threadIdentifier = identifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            try? await center.add(request)
        }
    }

    /// When the log last had something: the end of the latest entry or marked period. `nil` when
    /// one reaches past `now`.
    private static func lastTracked(in activities: [Activity], periods: [TrackingPeriod], now: Date) -> Date? {
        let ends = activities.map { activity in activity.kind == .sleep ? (activity.endDate ?? now) : activity.startDate }
            + periods.map(\.end)
        guard let last = ends.max(), last < now else { return nil }
        return last
    }

    /// `date`, or later if this iPhone's owner is off duty then (or it's night without a night plan).
    static func allowedTime(for date: Date, plan: NightPlan, night: Coverage.NightHours, calendar: Calendar) -> Date {
        guard plan.isEnabled else {
            return night.isNight(date, calendar: calendar) ? night.nextMorning(after: date, calendar: calendar) : date
        }
        var fire = date
        // A split night has two shifts; skipping a couple is always enough.
        for _ in 0..<4 {
            guard let shift = plan.shift(at: fire, calendar: calendar), !plan.alarmOwner.includes(shift.parent) else {
                return fire
            }
            fire = shift.end
        }
        return fire
    }
}
