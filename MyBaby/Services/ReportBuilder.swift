import Foundation

/// Totals for one calendar day.
struct DaySummary: Identifiable {
    let day: Date
    var id: Date { day }

    var feedings = 0
    var bottleML: Double = 0
    var breastMinutes = 0
    var solids = 0
    var diapers = 0
    var wet = 0
    var dirty = 0
    var sleepSeconds: TimeInterval = 0
    var sleeps = 0
    var baths = 0
    var medications = 0
    var pumpSessions = 0
    var pumpedML: Double = 0
    var temperatures = 0
    /// How much of the day was tracked (see `Coverage`). `.full` unless the summaries were made with one.
    var coverage: Coverage.Level = .full

    var sleepHours: Double { sleepSeconds / 3600 }

    var hasData: Bool {
        feedings + diapers + sleeps + baths + medications + pumpSessions + temperatures > 0
    }
}

/// Per-day averages over a report range.
struct ReportAverages {
    /// Which days the averages come from.
    enum Basis: Equatable {
        /// Fully tracked finished days only.
        case fullyTracked
        /// No finished day was fully tracked, so partly tracked ones are used.
        case partlyTracked
        /// Nothing has finished yet, so today so far.
        case todaySoFar
    }

    let basedOnDays: Int
    let basis: Basis
    /// Partly tracked days left out because there were fully tracked ones.
    let partialDaysSkipped: Int
    let feedings: Double
    let bottleML: Double
    let breastMinutes: Double
    let wet: Double
    let dirty: Double
    let sleepHours: Double
    let totalBaths: Int
    let totalMedications: Int

    /// Averages use finished, fully tracked days (see `Coverage`), so today, days nobody logged and
    /// days only partly logged don't drag the numbers down. Without any, partly tracked days are used,
    /// and the note says so.
    init(_ summaries: [DaySummary], calendar: Calendar = .current) {
        let finished = summaries.filter { $0.hasData && $0.coverage != .inProgress && !calendar.isDateInToday($0.day) }
        let full = finished.filter { $0.coverage == .full }
        let partial = finished.filter { $0.coverage == .partial }
        var days = full
        var basis = Basis.fullyTracked
        var skipped = partial.count
        if days.isEmpty && !partial.isEmpty {
            days = partial
            basis = .partlyTracked
            skipped = 0
        }
        if days.isEmpty {
            days = summaries.filter { $0.hasData && $0.coverage != .none }
            basis = .todaySoFar
            skipped = 0
        }
        let count = Double(max(days.count, 1))

        basedOnDays = days.count
        self.basis = basis
        partialDaysSkipped = skipped
        feedings = Double(days.reduce(0) { $0 + $1.feedings }) / count
        bottleML = days.reduce(0) { $0 + $1.bottleML } / count
        breastMinutes = Double(days.reduce(0) { $0 + $1.breastMinutes }) / count
        wet = Double(days.reduce(0) { $0 + $1.wet }) / count
        dirty = Double(days.reduce(0) { $0 + $1.dirty }) / count
        sleepHours = days.reduce(0) { $0 + $1.sleepHours } / count
        totalBaths = summaries.reduce(0) { $0 + $1.baths }
        totalMedications = summaries.reduce(0) { $0 + $1.medications }
    }

    /// "Based on 5 fully tracked days (2 partly tracked days not counted)." Shown under the averages
    /// on Reports, the PDF and the visit summary.
    var basisNote: String {
        guard basedOnDays > 0 else {
            return String(localized: "Averages appear once you've logged a full day.", comment: "Under the daily averages")
        }
        let days = basedOnDays
        let skipped = partialDaysSkipped
        switch basis {
        case .fullyTracked:
            // Whole sentences for one day and for several, with and without days left out.
            switch (days == 1, skipped) {
            case (true, 0):
                return String(localized: "Based on 1 fully tracked day.", comment: "Under the daily averages")
            case (false, 0):
                return String(localized: "Based on \(days) fully tracked days.", comment: "Under the daily averages; a number of days")
            case (true, 1):
                return String(localized: "Based on 1 fully tracked day (1 partly tracked day not counted).", comment: "Under the daily averages")
            case (true, _):
                return String(
                    localized: "Based on 1 fully tracked day (\(skipped) partly tracked days not counted).",
                    comment: "Under the daily averages; the number of days left out"
                )
            case (false, 1):
                return String(
                    localized: "Based on \(days) fully tracked days (1 partly tracked day not counted).",
                    comment: "Under the daily averages; a number of days"
                )
            case (false, _):
                return String(
                    localized: "Based on \(days) fully tracked days (\(skipped) partly tracked days not counted).",
                    comment: "Under the daily averages; the number of days counted, then the number left out"
                )
            }
        case .partlyTracked:
            return days == 1
                ? String(
                    localized: "Based on 1 partly tracked day, since no day was fully tracked. They may undercount.",
                    comment: "Under the daily averages"
                )
                : String(
                    localized: "Based on \(days) partly tracked days, since no day was fully tracked. They may undercount.",
                    comment: "Under the daily averages; a number of days"
                )
        case .todaySoFar:
            return String(localized: "Based on today so far.", comment: "Under the daily averages")
        }
    }

    /// The caution for days that weren't fully tracked, on the PDF and the visit summary.
    static var undercountNote: String {
        String(localized: "Days not fully tracked may undercount; low numbers on those days may not be real.")
    }
}

enum ReportBuilder {
    /// First day included in a report covering the last `days` days (today included).
    static func startDay(days: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }

    /// One summary per day, oldest first. Sleep that crosses midnight is split between the days.
    /// With `coverage`, each day also says how much of it was tracked.
    static func summaries(
        for activities: [Activity],
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        coverage: Coverage? = nil
    ) -> [DaySummary] {
        let first = startDay(days: days, now: now, calendar: calendar)
        let dayStarts = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        var byDay = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, DaySummary(day: $0)) })

        for activity in activities {
            let day = calendar.startOfDay(for: activity.startDate)
            switch activity.kind {
            case .feeding:
                byDay[day]?.feedings += 1
                switch activity.feedingType {
                case .breast:
                    byDay[day]?.breastMinutes += activity.breastMinutes
                case .solids:
                    byDay[day]?.solids += 1
                default:
                    byDay[day]?.bottleML += activity.amountML ?? 0
                }
            case .diaper:
                byDay[day]?.diapers += 1
                if activity.isWet { byDay[day]?.wet += 1 }
                if activity.isDirty { byDay[day]?.dirty += 1 }
            case .sleep:
                byDay[day]?.sleeps += 1
                var cursor = activity.startDate
                let end = min(activity.endDate ?? now, now)
                while cursor < end {
                    let dayStart = calendar.startOfDay(for: cursor)
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                    let segmentEnd = min(end, nextDay)
                    byDay[dayStart]?.sleepSeconds += segmentEnd.timeIntervalSince(cursor)
                    cursor = segmentEnd
                }
            case .bath:
                byDay[day]?.baths += 1
            case .medication:
                byDay[day]?.medications += 1
            case .pumping:
                byDay[day]?.pumpSessions += 1
                byDay[day]?.pumpedML += activity.pumpedTotalML ?? 0
            case .temperature:
                byDay[day]?.temperatures += 1
            }
        }

        if let coverage {
            for day in dayStarts {
                byDay[day]?.coverage = coverage.coverage(for: day).level
            }
        }
        return dayStarts.compactMap { byDay[$0] }
    }
}
