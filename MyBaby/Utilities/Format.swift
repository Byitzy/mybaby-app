import Foundation

enum Format {
    /// "45m", "2h", "1h 20m".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// "Just now", "25m ago", "3h 10m ago".
    static func timeAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        return "\(duration(seconds)) ago"
    }

    static func hours(_ seconds: TimeInterval) -> String {
        "\((seconds / 3600).formatted(.number.precision(.fractionLength(0...1))))h"
    }

    /// "Today", "Yesterday", or "Monday, Oct 20".
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "5 days old", "3 weeks, 2 days old", "4 months, 1 week old", "1 year, 2 months old".
    static func age(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: birthDate)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        if days < 0 { return "Due in \(plural(-days, "day"))" }
        if days == 0 { return "Born today 🎉" }
        if days < 14 { return "\(plural(days, "day")) old" }
        if days < 84 {
            let weeks = days / 7
            let rest = days % 7
            return rest == 0 ? "\(plural(weeks, "week")) old" : "\(plural(weeks, "week")), \(plural(rest, "day")) old"
        }

        let parts = calendar.dateComponents([.year, .month, .day], from: start, to: end)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        if years > 0 {
            return months == 0 ? "\(plural(years, "year")) old" : "\(plural(years, "year")), \(plural(months, "month")) old"
        }
        let weeks = (parts.day ?? 0) / 7
        return weeks == 0 ? "\(plural(months, "month")) old" : "\(plural(months, "month")), \(plural(weeks, "week")) old"
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }

    // MARK: VoiceOver

    /// "2 hours, 10 minutes", for VoiceOver, which would read "2h 10m" letter by letter.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "less than a minute" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? duration(seconds)
    }

    /// "2 hours, 10 minutes ago", or "Just now".
    static func spokenTimeAgo(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        return "\(spokenDuration(seconds)) ago"
    }

    /// `text` with short durations written out and dots turned into pauses: "Sleeping · 1h 20m" becomes
    /// "Sleeping, 1 hour 20 minutes", and "1.5h" becomes "1.5 hours". For VoiceOver labels built from
    /// on-screen text.
    static func spoken(_ text: String) -> String {
        var result = text.replacingOccurrences(of: " · ", with: ", ")
        for (pattern, unit) in [("(\\d+)h\\b", "hour"), ("(\\d+)m\\b", "minute")] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            // From the end, so the ranges still to replace don't move.
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result),
                      let digits = Range(match.range(at: 1), in: result),
                      let number = Int(result[digits])
                else { continue }
                result.replaceSubrange(whole, with: plural(number, unit))
            }
        }
        return result
    }

    /// "Bath logged" for "🛁 Bath logged", so VoiceOver doesn't start with the emoji's name.
    static func withoutLeadingEmoji(_ text: String) -> String {
        guard let first = text.first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0xFF) })
        else { return text }
        return String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
