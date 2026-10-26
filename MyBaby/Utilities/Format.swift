import Foundation

enum Format {
    /// "45m", "2h", "1h 20m".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return String(localized: "\(minutes)m", comment: "Short duration in minutes, e.g. “45m”") }
        if minutes == 0 { return String(localized: "\(hours)h", comment: "Short duration in hours, e.g. “2h”") }
        return String(localized: "\(hours)h \(minutes)m", comment: "Short duration in hours and minutes, e.g. “1h 20m”")
    }

    /// "Just now", "25m ago", "3h 10m ago".
    static func timeAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "Just now") }
        let length = duration(seconds)
        return String(localized: "\(length) ago", comment: "How long ago something happened, e.g. “25m ago”")
    }

    /// "1.5h".
    static func hours(_ seconds: TimeInterval) -> String {
        let number = (seconds / 3600).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(number)h", comment: "A number of hours, maybe with a decimal, e.g. “1.5h”")
    }

    /// "Today", "Yesterday", or "Monday, Oct 20".
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "5 days old", "3 weeks, 2 days old", "4 months, 1 week old", "1 year, 2 months old".
    static func age(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        if days < 0 {
            let wait = count(-days, .day)
            return String(localized: "Due in \(wait)", comment: "A baby who isn't born yet: the time until the due date, e.g. “Due in 5 days”")
        }
        if days == 0 { return String(localized: "Born today 🎉") }
        if days < 14 { return old(count(days, .day)) }
        if days < 84 {
            let weeks = days / 7
            let rest = days % 7
            return rest == 0 ? old(count(weeks, .week)) : old(count(weeks, .week), count(rest, .day))
        }

        let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years > 0 {
            return months == 0 ? old(count(years, .year)) : old(count(years, .year), count(months, .month))
        }
        let weeks = (parts.day ?? 0) / 7
        return weeks == 0 ? old(count(months, .month)) : old(count(months, .month), count(weeks, .week))
    }

    private enum AgeUnit {
        case day, week, month, year
    }

    /// "1 day", "5 days", "3 weeks", for an age.
    private static func count(_ value: Int, _ unit: AgeUnit) -> String {
        switch unit {
        case .day: return value == 1 ? String(localized: "1 day") : String(localized: "\(value) days")
        case .week: return value == 1 ? String(localized: "1 week") : String(localized: "\(value) weeks")
        case .month: return value == 1 ? String(localized: "1 month") : String(localized: "\(value) months")
        case .year: return value == 1 ? String(localized: "1 year") : String(localized: "\(value) years")
        }
    }

    /// "5 days old".
    private static func old(_ amount: String) -> String {
        String(localized: "\(amount) old", comment: "A baby's age, e.g. “5 days old”")
    }

    /// "3 weeks, 2 days old".
    private static func old(_ amount: String, _ rest: String) -> String {
        String(localized: "\(amount), \(rest) old", comment: "A baby's age in two parts, e.g. “3 weeks, 2 days old”")
    }

    /// "3 days", in English only: it adds an "s". For text people read, write each form as its own
    /// localized string instead (`n == 1 ? String(localized: "1 feed") : String(localized: "\(n) feeds")`).
    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }

    // MARK: VoiceOver

    /// "2 hours, 10 minutes", for VoiceOver, which would read "2h 10m" letter by letter.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(localized: "less than a minute", comment: "Spoken duration, for VoiceOver") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? duration(seconds)
    }

    /// "2 hours, 10 minutes ago", or "Just now".
    static func spokenTimeAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "Just now") }
        let length = spokenDuration(seconds)
        return String(localized: "\(length) ago", comment: "How long ago something happened, e.g. “25m ago”")
    }

    /// `text` with short durations written out and dots turned into pauses: "Sleeping · 1h 20m" becomes
    /// "Sleeping, 1 hour 20 minutes", and "1.5h" becomes "1.5 hours". For VoiceOver labels built from
    /// on-screen text.
    static func spoken(_ text: String) -> String {
        var result = text.replacingOccurrences(of: " · ", with: ", ")
        for (pattern, isHours) in [("(\\d+)h\\b", true), ("(\\d+)m\\b", false)] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            // From the end, so the ranges still to replace don't move.
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result),
                      let digits = Range(match.range(at: 1), in: result),
                      let number = Int(result[digits])
                else { continue }
                result.replaceSubrange(whole, with: isHours ? spokenHours(number) : spokenMinutes(number))
            }
        }
        return result
    }

    /// "1 hour", "2 hours".
    private static func spokenHours(_ count: Int) -> String {
        count == 1 ? String(localized: "1 hour") : String(localized: "\(count) hours")
    }

    /// "1 minute", "20 minutes".
    private static func spokenMinutes(_ count: Int) -> String {
        count == 1 ? String(localized: "1 minute") : String(localized: "\(count) minutes")
    }

    /// "Bath logged" for "🛁 Bath logged", so VoiceOver doesn't start with the emoji's name.
    static func withoutLeadingEmoji(_ text: String) -> String {
        guard let first = text.first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF) })
        else { return text }
        return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
