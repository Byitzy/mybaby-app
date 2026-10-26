import Foundation
import UserNotifications

extension SettingsKey {
    // In `UserDefaults.standard`: Parent care's own settings, for this iPhone only. The keys keep
    // their old "mom" names so saved settings carry over.
    /// Whether the daily check-in reminder is on. Off by default.
    static let momCheckInReminder = "momCheckInReminder"
    /// Minutes after midnight for the check-in reminder.
    static let momCheckInReminderMinutes = "momCheckInReminderMinutes"
    /// "I gave birth", which shows Parent care's birth recovery section. Not set until the switch is
    /// used; until then it counts as on only if there are recovery notes already.
    static let gaveBirth = "parentCareGaveBirth"
}

/// What the care screen is called on this iPhone: named after the person it belongs to
/// (Settings › Parents), like "Sam's care", or "My care" on a shared iPhone or before there's a name.
enum CareTitle {
    static func title(plan: NightPlan) -> String {
        // The stored name only: "Parent 1's care" would read oddly.
        guard let owner = plan.alarmOwner.parent, !plan.givenName(of: owner).isEmpty else {
            return String(localized: "My care", comment: "Title of the parent's private care page")
        }
        let name = plan.name(of: owner)
        return String(localized: "\(name)'s care", comment: "Title of the parent's private care page, after their name")
    }
}

/// The optional once-a-day nudge to check in. The notification says nothing about how you've been
/// feeling, since it can show on the Lock Screen.
enum MomCareReminder {
    private static let identifier = "mom-care-check-in"
    /// 8 PM, once the day has settled a little.
    static let defaultMinutes = 20 * 60

    /// Schedules the reminder, or removes it when it's off. Returns false if notifications aren't
    /// allowed, so the screen can turn the switch back off and explain.
    @discardableResult
    static func refresh() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.momCheckInReminder) else { return true }
        guard await NotificationManager.requestAuthorization() else { return false }

        let minutes = defaults.object(forKey: SettingsKey.momCheckInReminderMinutes) as? Int ?? defaultMinutes
        var time = DateComponents()
        time.hour = minutes / 60
        time.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.title = String(localized: "A moment for you 💛")
        content.body = String(localized: "How are you doing today? Your check-in takes less than a minute.")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }
}

/// "Export my care log": the parent's own entries as a CSV, separate from the baby's export.
enum CareLogExport {
    /// "MyBaby-Sams-care-log.csv", or "MyBaby-My-care-log.csv", after the screen's title (`CareTitle`).
    static func fileName(title: String) -> String {
        // Without apostrophes, so "Sam's" stays one word.
        let words = title
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return "MyBaby-\(words.isEmpty ? "My-care" : words.joined(separator: "-"))-log.csv"
    }

    static func csv(_ entries: [CareEntry]) -> String {
        // Not localized: the headers stay English, like the baby's CSV export.
        var rows = [[
            "Type", "Date", "Mood (1-5)", "Mood", "Sleep (hours)", "Medicine", "Dose", "Pain (0-10)", "Bleeding", "Notes",
        ]]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            rows.append([
                e.kind.title,
                timestampFormatter.string(from: e.date),
                e.mood.map { String($0.rawValue) } ?? "",
                e.mood?.title ?? "",
                e.sleepHours.map(decimal) ?? "",
                e.medicationName ?? "",
                e.dosage ?? "",
                e.painLevel.map { String($0) } ?? "",
                e.bleeding?.shortTitle ?? "",
                e.notes,
            ])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Written to the temporary folder, and removed once the share sheet closes (see `ShareSheet`).
    static func write(_ entries: [CareEntry], title: String) throws -> URL {
        try Exporter.write(csv(entries), named: fileName(title: title))
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// "5.5", always with a period so spreadsheets in any region read it the same way.
    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
