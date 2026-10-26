import CoreData
import Foundation
import UserNotifications

/// The optional "month birthday" nudge: "Mavie is 3 months today. Write something she'll love to read
/// one day?", at 10 AM on the day the baby turns another month old.
///
/// Off by default (Diary › Settings). Only the next one is ever pending, for the baby shown in the app
/// (see the budget at the top of `NotificationManager`); it's worked out again when the setting
/// changes, when the diary opens and whenever the log changes (`WidgetSnapshotWriter` calls `refresh`),
/// so the next month follows on its own.
enum DiaryReminder {
    static let identifier = "diary-month-birthday"
    /// The hour it comes at: 10 AM, a calm time of day.
    static let hour = 10

    @MainActor
    static func refresh(context: NSManagedObjectContext, now: Date = .now, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard UserDefaults.standard.bool(forKey: SettingsKey.diaryReminderEnabled),
              let baby = Baby.current(in: context),
              let birthDate = baby.birthDate,
              let next = nextMonthBirthday(birthDate: birthDate, after: now, calendar: calendar)
        else { return }
        let fire = next.date
        let months = next.months

        let content = UNMutableNotificationContent()
        content.title = title(name: baby.displayName, months: months)
        content.body = body(name: baby.displayName, sex: baby.sex)
        content.sound = .default
        content.threadIdentifier = identifier

        let interval = fire.timeIntervalSince(now)
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            try? await center.add(request)
        }
    }

    /// When the next month birthday's reminder is due after `now` (10 AM that day), and how many
    /// months old the baby turns then.
    static func nextMonthBirthday(birthDate: Date, after now: Date, calendar: Calendar = .current) -> (date: Date, months: Int)? {
        let birth = calendar.startOfDay(for: birthDate)
        let months = max(0, calendar.dateComponents([.month], from: birth, to: now).month ?? 0)
        // The month birthday just past may still be due today (before 10 AM); otherwise the next one.
        for candidate in max(1, months)...(months + 2) {
            guard let day = calendar.date(byAdding: .month, value: candidate, to: birth),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            else { continue }
            if fire > now { return (date: fire, months: candidate) }
        }
        return nil
    }

    /// "Mavie is 3 months today 🎉", "… 1 year today 🎉", "… 18 months today 🎉". Whole sentences, so
    /// each language can word the age its own way.
    static func title(name: String, months: Int) -> String {
        if months % 12 == 0 {
            let years = months / 12
            return years == 1
                ? String(localized: "\(name) is 1 year today 🎉", comment: "Diary reminder title on the first birthday; the baby's name")
                : String(localized: "\(name) is \(years) years today 🎉", comment: "Diary reminder title on a birthday; the baby's name, then the age in years")
        }
        return months == 1
            ? String(localized: "\(name) is 1 month today 🎉", comment: "Diary reminder title; the baby's name")
            : String(localized: "\(name) is \(months) months today 🎉", comment: "Diary reminder title; the baby's name, then the age in months")
    }

    /// "Write something she'll love to read one day?", or with the baby's name when their sex isn't set.
    static func body(name: String, sex: BabySex?) -> String {
        switch sex {
        case .female:
            return String(localized: "Write something she'll love to read one day?", comment: "Diary reminder, for a girl")
        case .male:
            return String(localized: "Write something he'll love to read one day?", comment: "Diary reminder, for a boy")
        case nil:
            return String(localized: "Write something \(name) will love to read one day?", comment: "Diary reminder; the baby's name")
        }
    }
}
