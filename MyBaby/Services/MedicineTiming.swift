import Foundation

/// The dose timing a parent entered for one medicine (see `MedicineSchedule`).
struct DoseRule: Equatable {
    var minHoursBetween: Double?
    var maxDosesPer24h: Int?

    var isEmpty: Bool {
        (minHoursBetween ?? 0) <= 0 && (maxDosesPer24h ?? 0) <= 0
    }

    /// "At least 6 hours apart · up to 4 in 24 hours".
    var summary: String {
        var parts: [String] = []
        if let hours = minHoursBetween, hours > 0 {
            parts.append("At least \(MedicineTiming.hoursText(hours)) apart")
        }
        if let max = maxDosesPer24h, max > 0 {
            parts.append("up to \(max) in 24 hours")
        }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Works out when the next dose is allowed, and whether a dose is being logged too soon,
/// only from the timing the parent entered. It never blocks a dose; it only warns.
enum MedicineTiming {
    private static let day: TimeInterval = 24 * 3600

    /// The earliest time the next dose fits the rule, or `nil` when it's fine to give it now.
    static func nextAllowed(rule: DoseRule, doseDates: [Date], now: Date = .now) -> Date? {
        let past = doseDates.filter { $0 <= now }.sorted()
        guard let last = past.last, !rule.isEmpty else { return nil }
        var next = last
        if let hours = rule.minHoursBetween, hours > 0 {
            next = max(next, last.addingTimeInterval(hours * 3600))
        }
        if let maxDoses = rule.maxDosesPer24h, maxDoses > 0 {
            let window = past.filter { $0 > now.addingTimeInterval(-day) }
            if window.count >= maxDoses {
                // Enough doses have to drop out of the last 24 hours to leave room for one more.
                next = max(next, window[window.count - maxDoses].addingTimeInterval(day))
            }
        }
        return next > now ? next : nil
    }

    /// Warnings for a dose given at `date`, compared with the other doses of the same medicine.
    static func warnings(rule: DoseRule, at date: Date, otherDoses: [Date]) -> [String] {
        var warnings: [String] = []
        if let hours = rule.minHoursBetween, hours > 0 {
            let limit = hours * 3600
            let close = otherDoses
                .filter { abs($0.timeIntervalSince(date)) < limit }
                .min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
            if let close {
                let gap = Format.duration(abs(close.timeIntervalSince(date)))
                let when = close <= date ? "after the dose at" : "before the dose at"
                warnings.append(
                    "This is only \(gap) \(when) \(close.formatted(date: .omitted, time: .shortened)). The timing you entered is at least \(hoursText(hours)) between doses."
                )
            }
        }
        if let maxDoses = rule.maxDosesPer24h, maxDoses > 0 {
            let count = otherDoses.filter { $0 > date.addingTimeInterval(-day) && $0 <= date }.count + 1
            if count > maxDoses {
                warnings.append("This would be dose \(count) in 24 hours. The timing you entered allows \(maxDoses).")
            }
        }
        return warnings
    }

    /// "Next dose allowed at 4:10 AM", "… tomorrow at 4:10 AM" or "… Tue 4:10 AM".
    static func nextDoseText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Next dose allowed at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Next dose allowed tomorrow at \(time)"
        }
        return "Next dose allowed \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// "6 hours", "1 hour", "4.5 hours".
    static func hoursText(_ hours: Double) -> String {
        let number = hours.formatted(.number.precision(.fractionLength(0...1)))
        return hours == 1 ? "1 hour" : "\(number) hours"
    }
}
