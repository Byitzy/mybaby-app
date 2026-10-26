import Foundation

/// The dose timing a parent entered for one medicine (see `MedicineSchedule`).
struct DoseRule: Equatable {
    var minHoursBetween: Double?
    var maxDosesPer24h: Int?

    var isEmpty: Bool {
        (minHoursBetween ?? 0) <= 0 && (maxDosesPer24h ?? 0) <= 0
    }

    /// "At least 6 hours apart · up to 4 in 24 hours", "At least 6 hours apart" or "Up to 4 in 24 hours".
    var summary: String {
        let hours = (minHoursBetween ?? 0) > 0 ? minHoursBetween : nil
        let doses = (maxDosesPer24h ?? 0) > 0 ? maxDosesPer24h : nil
        switch (hours, doses) {
        case let (hours?, doses?):
            let apart = MedicineTiming.hoursText(hours)
            return String(
                localized: "At least \(apart) apart · up to \(doses) in 24 hours",
                comment: "Dose timing; a number of hours like 6 hours, then the most doses in 24 hours"
            )
        case let (hours?, nil):
            let apart = MedicineTiming.hoursText(hours)
            return String(localized: "At least \(apart) apart", comment: "Dose timing; a number of hours like 6 hours")
        case let (nil, doses?):
            return String(localized: "Up to \(doses) in 24 hours", comment: "Dose timing; the most doses in 24 hours")
        case (nil, nil):
            return ""
        }
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
                let time = close.formatted(date: .omitted, time: .shortened)
                let least = hoursText(hours)
                warnings.append(close <= date
                    ? String(
                        localized: "This is only \(gap) after the dose at \(time). The timing you entered is at least \(least) between doses.",
                        comment: "Medicine warning; a duration like 2h 30m, a time, then a number of hours like 6 hours"
                    )
                    : String(
                        localized: "This is only \(gap) before the dose at \(time). The timing you entered is at least \(least) between doses.",
                        comment: "Medicine warning; a duration like 2h 30m, a time, then a number of hours like 6 hours"
                    )
                )
            }
        }
        if let maxDoses = rule.maxDosesPer24h, maxDoses > 0 {
            let count = otherDoses.filter { $0 > date.addingTimeInterval(-day) && $0 <= date }.count + 1
            if count > maxDoses {
                warnings.append(String(
                    localized: "This would be dose \(count) in 24 hours. The timing you entered allows \(maxDoses).",
                    comment: "Medicine warning; which dose this would be, then the most doses allowed in 24 hours"
                ))
            }
        }
        return warnings
    }

    /// "Next dose allowed at 4:10 AM", "… tomorrow at 4:10 AM" or "… Tue 4:10 AM".
    static func nextDoseText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Next dose allowed at \(time)", comment: "Medicine dose timing; a time today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Next dose allowed tomorrow at \(time)", comment: "Medicine dose timing; a time tomorrow")
        }
        let when = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return String(localized: "Next dose allowed \(when)", comment: "Medicine dose timing; a weekday and time, like Tue 4:10 AM")
    }

    /// "6 hours", "1 hour", "4.5 hours".
    static func hoursText(_ hours: Double) -> String {
        let number = hours.formatted(.number.precision(.fractionLength(0...1)))
        return hours == 1
            ? String(localized: "1 hour", comment: "Dose timing: one hour")
            : String(localized: "\(number) hours", comment: "Dose timing; a number of hours, which can have a decimal, like 4.5")
    }
}
