import Foundation

/// A week or month of the baby's life, counted from the birthday: "Week 6" is the sixth week (from
/// 5 weeks old to the day before 6 weeks old), and "Month 3" the third month (from the 2-month birthday
/// to the day before the 3-month one). Weeks are only used for the first 3 months (`firstWeeks`), when
/// a week is a long time; after that it's months.
///
/// Summaries are worked out from these on the fly (`DiarySummary`); nothing about them is stored except
/// the parents' notes, which point at a period by its `ID`.
struct DiaryPeriod: Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case week, month
    }

    /// Which period: "month 3". Stable whatever the time zone, so a note stays with its month.
    struct ID: Hashable, Codable {
        let kind: Kind
        let index: Int

        /// "month-3", for remembering things in `UserDefaults`.
        var key: String { "\(kind.rawValue)-\(index)" }
    }

    /// Weeks 1 to 13 make up the first 3 months.
    static let firstWeeks = 13

    let id: ID
    /// The first day, at midnight.
    let start: Date
    /// Midnight at the start of the day after the last day, so the period is [start, end).
    let end: Date

    var kind: Kind { id.kind }
    var index: Int { id.index }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }

    /// "Week 6" or "Month 3".
    var title: String {
        switch kind {
        case .week: return String(localized: "Week \(index)", comment: "A week of the baby's life, counted from the birthday")
        case .month: return String(localized: "Month \(index)", comment: "A month of the baby's life, counted from the birthday")
        }
    }

    /// "Your week" or "this month", for buttons like "Write about this month". English word order
    /// only: a sentence that names the period is better written whole for each `kind`.
    var noun: String {
        kind == .week
            ? String(localized: "week", comment: "A week of the baby's life, as in this week")
            : String(localized: "month", comment: "A month of the baby's life, as in this month")
    }

    /// The last day, at midnight.
    func lastDay(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end) ?? start
    }

    /// "12 Jan – 11 Feb", with years when they aren't this year's.
    func dateRange(calendar: Calendar = .current, now: Date = .now) -> String {
        let last = lastDay(calendar: calendar)
        let thisYear = calendar.component(.year, from: now)
        let showsYear = calendar.component(.year, from: start) != thisYear || calendar.component(.year, from: last) != thisYear
        let style: Date.FormatStyle = showsYear
            ? .dateTime.day().month(.abbreviated).year()
            : .dateTime.day().month(.abbreviated)
        return "\(start.formatted(style)) – \(last.formatted(style))"
    }

    /// "Month 3 · 12 Jan – 11 Feb".
    func fullTitle(calendar: Calendar = .current, now: Date = .now) -> String {
        "\(title) · \(dateRange(calendar: calendar, now: now))"
    }

    /// The age the baby reaches when it ends: "6 weeks", "3 months", "1 year", "18 months".
    var ageReached: String {
        switch kind {
        case .week:
            return Self.age(weeks: index)
        case .month:
            return index % 12 == 0 ? Self.age(years: index / 12) : Self.age(months: index)
        }
    }

    /// "1 week" or "6 weeks", a baby's age.
    static func age(weeks count: Int) -> String {
        count == 1
            ? String(localized: "1 week", comment: "A baby's age")
            : String(localized: "\(count) weeks", comment: "A baby's age")
    }

    /// "1 month" or "18 months", a baby's age.
    static func age(months count: Int) -> String {
        count == 1
            ? String(localized: "1 month", comment: "A baby's age")
            : String(localized: "\(count) months", comment: "A baby's age")
    }

    /// "1 year" or "2 years", a baby's age.
    static func age(years count: Int) -> String {
        count == 1
            ? String(localized: "1 year", comment: "A baby's age")
            : String(localized: "\(count) years", comment: "A baby's age")
    }

    func isFinished(now: Date = .now) -> Bool { now >= end }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Where a new note about this period is dated: its last day at noon, or now while it's still going.
    func noteDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        guard isFinished(now: now) else { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: lastDay(calendar: calendar)) ?? lastDay(calendar: calendar)
    }

    // MARK: Finding periods

    /// The period with `id` for a baby born on `birthDate`, or nil for an index below 1 (or a week
    /// past the first 3 months).
    static func period(_ id: ID, birthDate: Date, calendar: Calendar = .current) -> DiaryPeriod? {
        guard id.index >= 1 else { return nil }
        let birth = calendar.startOfDay(for: birthDate)
        switch id.kind {
        case .week:
            guard id.index <= firstWeeks,
                  let start = calendar.date(byAdding: .day, value: (id.index - 1) * 7, to: birth),
                  let end = calendar.date(byAdding: .day, value: id.index * 7, to: birth)
            else { return nil }
            return DiaryPeriod(id: id, start: start, end: end)
        case .month:
            // Always counted from the birthday, so a baby born on the 31st has months that end on the
            // last day of shorter months, rather than drifting.
            guard let start = calendar.date(byAdding: .month, value: id.index - 1, to: birth),
                  let end = calendar.date(byAdding: .month, value: id.index, to: birth)
            else { return nil }
            return DiaryPeriod(id: id, start: calendar.startOfDay(for: start), end: calendar.startOfDay(for: end))
        }
    }

    static func week(_ index: Int, birthDate: Date, calendar: Calendar = .current) -> DiaryPeriod? {
        period(ID(kind: .week, index: index), birthDate: birthDate, calendar: calendar)
    }

    static func month(_ index: Int, birthDate: Date, calendar: Calendar = .current) -> DiaryPeriod? {
        period(ID(kind: .month, index: index), birthDate: birthDate, calendar: calendar)
    }

    /// The month of the baby's life `date` falls in, or nil before the birth.
    static func month(containing date: Date, birthDate: Date, calendar: Calendar = .current) -> DiaryPeriod? {
        let birth = calendar.startOfDay(for: birthDate)
        guard date >= birth else { return nil }
        let months = calendar.dateComponents([.month], from: birth, to: calendar.startOfDay(for: date)).month ?? 0
        var index = max(1, months + 1)
        // Month lengths differ, so nudge the first guess until the month really contains the date.
        for _ in 0..<3 {
            guard let candidate = month(index, birthDate: birthDate, calendar: calendar) else { return nil }
            if date < candidate.start, index > 1 {
                index -= 1
            } else if date >= candidate.end {
                index += 1
            } else {
                return candidate
            }
        }
        return month(index, birthDate: birthDate, calendar: calendar)
    }

    /// The week of the first 3 months `date` falls in, or nil before the birth or after week 13.
    static func week(containing date: Date, birthDate: Date, calendar: Calendar = .current) -> DiaryPeriod? {
        let birth = calendar.startOfDay(for: birthDate)
        guard date >= birth else { return nil }
        let days = calendar.dateComponents([.day], from: birth, to: calendar.startOfDay(for: date)).day ?? 0
        return week(days / 7 + 1, birthDate: birthDate, calendar: calendar)
    }

    /// Every month that has begun by `now`, newest first (the one still going included).
    static func months(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> [DiaryPeriod] {
        guard let current = month(containing: now, birthDate: birthDate, calendar: calendar) else { return [] }
        return (1...current.index).reversed().compactMap { month($0, birthDate: birthDate, calendar: calendar) }
    }

    /// Every week of the first 3 months that has begun by `now`, newest first.
    static func weeks(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> [DiaryPeriod] {
        let birth = calendar.startOfDay(for: birthDate)
        guard now >= birth else { return [] }
        let days = calendar.dateComponents([.day], from: birth, to: calendar.startOfDay(for: now)).day ?? 0
        let latest = min(firstWeeks, days / 7 + 1)
        return (1...latest).reversed().compactMap { week($0, birthDate: birthDate, calendar: calendar) }
    }

    /// The summary that just became ready, for the card on Today: the latest finished month, or week
    /// in the first 3 months, while it's fresh (3 days for a week, a week for a month). A month wins
    /// when both end on the same day.
    static func justFinished(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> DiaryPeriod? {
        var candidates: [DiaryPeriod] = []
        if let current = month(containing: now, birthDate: birthDate, calendar: calendar), current.index > 1,
           let previous = month(current.index - 1, birthDate: birthDate, calendar: calendar) {
            candidates.append(previous)
        }
        if let current = week(containing: now, birthDate: birthDate, calendar: calendar), current.index > 1,
           let previous = week(current.index - 1, birthDate: birthDate, calendar: calendar) {
            candidates.append(previous)
        } else if let last = week(firstWeeks, birthDate: birthDate, calendar: calendar), last.isFinished(now: now) {
            candidates.append(last)
        }
        let fresh = candidates.filter { period in
            let days = period.kind == .week ? 3 : 7
            let until = calendar.date(byAdding: .day, value: days, to: period.end) ?? period.end
            return period.isFinished(now: now) && now < until
        }
        return fresh.max { a, b in
            a.end != b.end ? a.end < b.end : (a.kind == .week && b.kind == .month)
        }
    }
}
