import Foundation

extension Format {
    /// An hour on the clock for a sentence, like the 10 in "A gentle note at 10 AM": "10 AM" where the
    /// clock uses AM and PM, "10:00" where it's 24-hour. From the formatters, so it reads the way the
    /// person's own clock does.
    static func clockHour(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        let usesAMPM = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
        return usesAMPM ? date.formatted(.dateTime.hour()) : date.formatted(.dateTime.hour().minute())
    }
}
