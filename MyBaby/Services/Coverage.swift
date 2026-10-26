import Foundation

/// How much of each day was actually tracked, so a time nobody logged isn't read as a time nothing
/// happened.
///
/// Worked out from the log alone, then corrected by the periods parents marked by hand:
/// - **Entries cover time.** A sleep covers its whole length (up to now while it's going), and every
///   entry covers `entryWindow` (2.5 hours) either side of it: someone was clearly looking after the baby.
/// - **Gaps are untracked.** A stretch with nothing logged is untracked when more than `dayGapThreshold`
///   (5 hours) of it falls in the waking hours (7 AM–9 PM, or outside the night plan's hours when it's on),
///   or when it's longer than `nightGapThreshold` (8 hours) in all. Shorter stretches that reach into the
///   night are fine: babies sleep without anyone logging a sleep. The untracked part is the stretch minus
///   the entry windows at its ends.
/// - **Marked periods win.** *Not tracked* is untracked whatever was logged; *Nothing happened* and
///   *Caught up* are tracked whatever the gaps say (`TrackingPeriod`).
///
/// A finished day is `.full` when at least `fullDayShare` (85%) of its waking hours were tracked,
/// `.none` when none of it was, and `.partial` in between. Today is `.inProgress`.
///
/// Everything here is a pure function of the entries, the periods, a time and a calendar, so it can
/// be tested without Core Data (see `Entry` and `Period`; `init(activities:periods:)` converts).
struct Coverage {
    // MARK: Limits

    /// Time either side of any entry that counts as tracked.
    static let entryWindow: TimeInterval = 2.5 * 3600
    /// A stretch with more than this much of the waking hours and nothing logged is untracked.
    static let dayGapThreshold: TimeInterval = 5 * 3600
    /// A stretch longer than this with nothing logged is untracked, even at night.
    static let nightGapThreshold: TimeInterval = 8 * 3600
    /// A day is fully tracked from this share of its waking hours.
    static let fullDayShare = 0.85
    /// Below this share, nothing of the day was tracked.
    static let noDataShare = 0.01
    /// A sleep timer running longer than this was probably forgotten (Today asks about it).
    static let forgottenSleep: TimeInterval = 12 * 3600

    // MARK: Input

    /// A logged entry reduced to the time it covers.
    struct Entry: Equatable {
        let start: Date
        /// When a sleep ended, `nil` while it's still going. For other entries, the same as `start`.
        let end: Date?

        init(start: Date, end: Date?) {
            self.start = start
            self.end = end
        }

        /// A feed, diaper, bath or anything else that happens at one moment.
        static func moment(_ date: Date) -> Entry {
            Entry(start: date, end: date)
        }
    }

    /// A period marked by hand (`TrackingPeriod`).
    struct Period: Equatable {
        let start: Date
        let end: Date
        /// *Nothing happened* or *Caught up*, rather than *Not tracked*.
        let isTracked: Bool
    }

    /// The night hours: 9 PM to 7 AM, or the night plan's when it's on. The rest of the day is the
    /// waking hours that a day's coverage is measured over.
    struct NightHours: Equatable {
        /// Minutes after midnight the night starts (in the evening) and ends (the next morning).
        var startMinutes = 21 * 60
        var endMinutes = 7 * 60

        init(startMinutes: Int = 21 * 60, endMinutes: Int = 7 * 60) {
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
        }

        /// The night plan's hours when it's on, otherwise 9 PM to 7 AM.
        init(plan: NightPlan) {
            if plan.isEnabled {
                self.init(startMinutes: plan.nightStartMinutes, endMinutes: plan.nightEndMinutes)
            } else {
                self.init()
            }
        }

        func isNight(_ date: Date, calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if startMinutes > endMinutes {
                return minute >= startMinutes || minute < endMinutes
            }
            return minute >= startMinutes && minute < endMinutes
        }

        /// The waking hours of `day`: from the morning the night ends to the evening the next one starts.
        func wakingWindow(forDay day: Date, calendar: Calendar) -> DateInterval {
            let dayStart = calendar.startOfDay(for: day)
            let start = calendar.date(bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: dayStart) ?? dayStart
            var end = calendar.date(bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: dayStart) ?? dayStart
            if end <= start {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? start.addingTimeInterval(86_400)
            }
            return DateInterval(start: start, end: max(start, end))
        }

        /// The first moment of the waking hours at or after `date`.
        func nextMorning(after date: Date, calendar: Calendar) -> Date {
            let today = wakingWindow(forDay: date, calendar: calendar)
            if date < today.start { return today.start }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            return wakingWindow(forDay: tomorrow, calendar: calendar).start
        }

        /// How much of `interval` falls in waking hours. Meant for stretches of a few hours to days.
        func wakingOverlap(_ interval: DateInterval, calendar: Calendar) -> TimeInterval {
            // Long stretches only ever need "more than 5 hours", so a month back is plenty.
            let start = max(interval.start, interval.end.addingTimeInterval(-31 * 86_400))
            guard interval.end > start else { return 0 }
            let clipped = DateInterval(start: start, end: interval.end)
            var total: TimeInterval = 0
            var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
            let lastDay = calendar.startOfDay(for: clipped.end)
            while day <= lastDay {
                total += Coverage.overlap(wakingWindow(forDay: day, calendar: calendar), clipped)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return total
        }
    }

    // MARK: Output

    enum Level: String, Equatable {
        /// At least 85% of the waking hours were tracked.
        case full
        case partial
        /// Nothing of the waking hours was tracked.
        case none
        /// Today, or a day whose waking hours haven't ended yet.
        case inProgress

        /// For the PDF's "Tracked" column.
        var title: String {
            switch self {
            case .full: return String(localized: "Full", comment: "How much of a day was tracked, in the PDF report's Tracked column")
            case .partial: return String(localized: "Partial", comment: "How much of a day was tracked, in the PDF report's Tracked column")
            case .none: return String(localized: "None", comment: "How much of a day was tracked, in the PDF report's Tracked column")
            case .inProgress: return String(localized: "Today", comment: "How much of a day was tracked, in the PDF report's Tracked column: the day isn't over")
            }
        }
    }

    struct DayCoverage: Equatable {
        let day: Date
        let level: Level
        /// The share of the waking hours (so far, for today) that was tracked, 0 to 1.
        let trackedShare: Double
    }

    /// A stretch with nothing logged, long enough to count as untracked.
    struct Gap: Identifiable, Equatable {
        /// When the last entry before it ended. `Date.distantPast` before anything was ever logged.
        let start: Date
        /// When the next entry started, or now for the gap that's still open.
        let end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
        var id: Date { start }
        /// Whether something was logged before it, so "since 9:10 AM" means something.
        var hasStart: Bool { start > .distantPast }
    }

    // MARK: State

    let now: Date
    let night: NightHours
    let calendar: Calendar
    /// Everything logged or marked, oldest first, never past `now`.
    private let anchors: [Anchor]
    /// The untracked time up to `now`, merged and oldest first.
    let untracked: [DateInterval]
    /// Every gap up to `now`, oldest first. The last one may still be open.
    let gaps: [Gap]

    /// Something that splits the timeline: an entry, or a marked period.
    private struct Anchor {
        let start: Date
        let end: Date
        /// Entries cover `entryWindow` around them; marked periods cover exactly their own time.
        let isEntry: Bool
    }

    init(
        entries: [Entry],
        periods: [Period],
        now: Date = .now,
        night: NightHours = NightHours(),
        calendar: Calendar = .current
    ) {
        self.now = now
        self.night = night
        self.calendar = calendar

        var anchors: [Anchor] = entries.compactMap { entry in
            guard entry.start <= now else { return nil }
            let end = min(max(entry.end ?? now, entry.start), now)
            return Anchor(start: entry.start, end: end, isEntry: true)
        }
        for period in periods {
            let start = min(period.start, period.end)
            let end = min(max(period.start, period.end), now)
            guard start < end else { continue }
            anchors.append(Anchor(start: start, end: end, isEntry: false))
        }
        anchors.sort { $0.start < $1.start }
        self.anchors = anchors

        // Stretches between anchors, and which of them are gaps.
        var inferred: [DateInterval] = []
        var gaps: [Gap] = []
        var cursor = Date.distantPast
        var cursorIsEntry = false
        var stretches: [(start: Date, end: Date, leftIsEntry: Bool, rightIsEntry: Bool)] = []
        for anchor in anchors {
            if anchor.start > cursor {
                stretches.append((start: cursor, end: anchor.start, leftIsEntry: cursorIsEntry, rightIsEntry: anchor.isEntry))
            }
            if anchor.end > cursor {
                cursor = anchor.end
                cursorIsEntry = anchor.isEntry
            } else if anchor.end == cursor && anchor.isEntry {
                cursorIsEntry = true
            }
        }
        if now > cursor {
            // Still open: nothing logged since the last anchor.
            stretches.append((start: cursor, end: now, leftIsEntry: cursorIsEntry, rightIsEntry: false))
        }
        for stretch in stretches {
            let interval = DateInterval(start: stretch.start, end: stretch.end)
            guard Coverage.isGap(interval, night: night, calendar: calendar) else { continue }
            gaps.append(Gap(start: stretch.start, end: stretch.end))
            let from = stretch.leftIsEntry ? stretch.start.addingTimeInterval(Coverage.entryWindow) : stretch.start
            let to = stretch.rightIsEntry ? stretch.end.addingTimeInterval(-Coverage.entryWindow) : stretch.end
            if to > from {
                inferred.append(DateInterval(start: from, end: to))
            }
        }
        self.gaps = gaps

        // Marked periods override: tracked ones clear inferred gaps, and "not tracked" always counts.
        let trackedPeriods = periods.filter(\.isTracked).map(Coverage.interval)
        let notTracked = periods.filter { !$0.isTracked }.map(Coverage.interval)
            .compactMap { Coverage.clip($0, before: now) }
        self.untracked = Coverage.merge(Coverage.subtract(trackedPeriods, from: inferred) + notTracked)
    }

    // MARK: Questions

    /// How much of `day`'s waking hours were tracked.
    func coverage(for day: Date) -> DayCoverage {
        let dayStart = calendar.startOfDay(for: day)
        let window = night.wakingWindow(forDay: dayStart, calendar: calendar)
        let inProgress = calendar.isDate(dayStart, inSameDayAs: now) || window.end > now
        let end = min(window.end, now)
        guard end > window.start else {
            return DayCoverage(day: dayStart, level: inProgress ? .inProgress : .none, trackedShare: 0)
        }
        let counted = DateInterval(start: window.start, end: end)
        let missing = untracked.reduce(0) { $0 + Self.overlap($1, counted) }
        let share = max(0, min(1, 1 - missing / counted.duration))
        let level: Level
        if inProgress {
            level = .inProgress
        } else if share >= Self.fullDayShare {
            level = .full
        } else if share < Self.noDataShare {
            level = .none
        } else {
            level = .partial
        }
        return DayCoverage(day: dayStart, level: level, trackedShare: share)
    }

    /// The untracked stretch that's still open at `now`: nothing logged or marked since its `start`,
    /// for longer than the gap thresholds. `nil` while a sleep is going on, before anything was ever
    /// logged, or when the last entry is recent enough.
    func currentGap(now: Date) -> Gap? {
        let past = anchors.filter { $0.start <= now }
        guard !past.isEmpty else { return nil }
        let last = past.map { min($0.end, now) }.max() ?? now
        // A sleep still going on reaches `now` (its end was clipped to it).
        guard now > last else { return nil }
        let stretch = DateInterval(start: last, end: now)
        guard Self.isGap(stretch, night: night, calendar: calendar) else { return nil }
        return Gap(start: last, end: now)
    }

    /// The gaps that overlap `range`, cut to it, oldest first.
    func gaps(in range: DateInterval) -> [Gap] {
        gaps.compactMap { gap in
            let start = max(gap.start, range.start)
            let end = min(gap.end, range.end)
            guard end > start else { return nil }
            return Gap(start: start, end: end)
        }
    }

    /// The untracked time that overlaps `range`, cut to it.
    func untracked(in range: DateInterval) -> [DateInterval] {
        untracked.compactMap { interval in
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
    }

    // MARK: Rules

    /// Whether a stretch with nothing logged is untracked: more than 5 waking hours, or more than
    /// 8 hours in all (see the type's notes).
    static func isGap(_ stretch: DateInterval, night: NightHours, calendar: Calendar) -> Bool {
        if stretch.duration > nightGapThreshold { return true }
        if stretch.duration <= dayGapThreshold { return false }
        return night.wakingOverlap(stretch, calendar: calendar) > dayGapThreshold
    }

    /// The moment a stretch that began at `last` with nothing logged becomes a gap.
    static func gapBegins(after last: Date, night: NightHours, calendar: Calendar) -> Date {
        let byLength = last.addingTimeInterval(nightGapThreshold)
        // Walk the waking hours from `last` until 5 of them have gone by.
        var remaining = dayGapThreshold
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: last) else { continue }
            let window = night.wakingWindow(forDay: day, calendar: calendar)
            let from = max(window.start, last)
            guard window.end > from else { continue }
            let available = window.end.timeIntervalSince(from)
            if available > remaining {
                return min(byLength, from.addingTimeInterval(remaining))
            }
            remaining -= available
        }
        return byLength
    }

    /// `count` moments spread evenly over `range`, each in the middle of its share of it.
    /// Catch up places its approximate entries at these times.
    static func evenlySpread(_ count: Int, over range: DateInterval) -> [Date] {
        guard count > 0 else { return [] }
        let step = range.duration / Double(count)
        return (0..<count).map { range.start.addingTimeInterval(step * (Double($0) + 0.5)) }
    }

    /// `count` naps of about `minutes` each, one in the middle of each equal share of `range`, and
    /// never longer than most of their share, so they don't overlap.
    static func napTimes(_ count: Int, minutes: Int, over range: DateInterval) -> [DateInterval] {
        guard count > 0, range.duration > 0 else { return [] }
        let slot = range.duration / Double(count)
        let length = max(60, min(Double(minutes) * 60, slot * 0.9))
        return (0..<count).map { index in
            let start = range.start.addingTimeInterval(slot * Double(index) + max(0, slot - length) / 2)
            return DateInterval(start: start, end: start.addingTimeInterval(min(length, slot)))
        }
    }

    // MARK: Interval math

    static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }

    /// Overlapping or touching intervals joined, oldest first.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// `intervals` with every part that falls in `holes` cut out.
    static func subtract(_ holes: [DateInterval], from intervals: [DateInterval]) -> [DateInterval] {
        let holes = merge(holes)
        var result: [DateInterval] = []
        for interval in intervals {
            var pieces = [interval]
            for hole in holes where hole.end > interval.start && hole.start < interval.end {
                pieces = pieces.flatMap { piece -> [DateInterval] in
                    guard hole.end > piece.start && hole.start < piece.end else { return [piece] }
                    var parts: [DateInterval] = []
                    if hole.start > piece.start { parts.append(DateInterval(start: piece.start, end: hole.start)) }
                    if hole.end < piece.end { parts.append(DateInterval(start: hole.end, end: piece.end)) }
                    return parts
                }
            }
            result += pieces
        }
        return result
    }

    private static func interval(_ period: Period) -> DateInterval {
        DateInterval(start: min(period.start, period.end), end: max(period.start, period.end))
    }

    private static func clip(_ interval: DateInterval, before now: Date) -> DateInterval? {
        guard interval.start < now else { return nil }
        return DateInterval(start: interval.start, end: min(interval.end, now))
    }
}

// MARK: - From the log

extension Coverage {
    /// Coverage of the log: `activities` (any kinds) and the marked `periods`, with the night plan's hours.
    init(
        activities: [Activity],
        periods: [TrackingPeriod],
        now: Date = .now,
        plan: NightPlan = .load(),
        calendar: Calendar = .current
    ) {
        // A deleted entry (here, or by the partner) can still be in a fetch's results for a moment,
        // and its dates can't be read any more.
        let entries = activities
            .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            .map(Coverage.entry)
        let marked = periods
            .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            .map(\.coveragePeriod)
        self.init(entries: entries, periods: marked, now: now, night: NightHours(plan: plan), calendar: calendar)
    }

    static func entry(_ activity: Activity) -> Entry {
        activity.kind == .sleep
            ? Entry(start: activity.startDate, end: activity.endDate)
            : .moment(activity.startDate)
    }
}
