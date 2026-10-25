import Foundation

/// Rhythms in the last week or two of the log: when the baby usually wakes at night, how far
/// apart feeds are, the longest sleep, awake stretches between sleeps and the busiest diaper times.
///
/// Only describes what was logged. It doesn't judge whether any of it is normal; that's a
/// conversation for the pediatrician. Everything here is a pure function of the entries, a date
/// and a calendar, so it can be tested without Core Data (see `Event`).
enum PatternFinder {
    // MARK: Input

    /// A logged entry reduced to what the patterns use.
    struct Event: Equatable {
        enum Kind: Equatable {
            case feed, diaper, sleep
        }

        let kind: Kind
        let start: Date
        /// When a sleep ended; `nil` while it's still going, and for feeds and diapers.
        var end: Date?
    }

    /// The hours that count as night: 9 PM to 7 AM by default, the same as 3 AM mode without a
    /// night plan. `startHour` is in the evening and `endHour` the next morning.
    struct NightWindow {
        var startHour = 21
        var endHour = 7

        func contains(_ date: Date, calendar: Calendar) -> Bool {
            let hour = calendar.component(.hour, from: date)
            return hour >= startHour || hour < endHour
        }

        /// The evening that began the night `date` falls in, e.g. 9 PM on Monday for 2 AM on Tuesday.
        func nightStart(of date: Date, calendar: Calendar) -> Date {
            let day = calendar.startOfDay(for: date)
            let evening = calendar.component(.hour, from: date) < endHour
                ? calendar.date(byAdding: .day, value: -1, to: day) ?? day
                : day
            return calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: evening) ?? evening
        }
    }

    static func events(from activities: [Activity]) -> [Event] {
        activities.compactMap { activity -> Event? in
            switch activity.kind {
            case .feeding: return Event(kind: .feed, start: activity.startDate)
            case .diaper: return Event(kind: .diaper, start: activity.startDate)
            case .sleep: return Event(kind: .sleep, start: activity.startDate, end: activity.endDate)
            default: return nil
            }
        }
    }

    // MARK: Output

    /// A clock time babies often woke around, and on how many nights.
    struct WakeTime: Identifiable, Equatable {
        /// Minutes after midnight, rounded to the nearest 15 minutes.
        let minuteOfDay: Int
        let nights: Int
        var id: Int { minuteOfDay }
    }

    struct NightWakes {
        /// The times that came up on at least 40% of the nights (and at least two), earliest first.
        let usualTimes: [WakeTime]
        /// Nights with anything logged during the night hours.
        let nights: Int
        let averagePerNight: Double
        /// Every wake-up's clock time in minutes after midnight, for a chart.
        let allWakes: [Int]
    }

    struct FeedGaps {
        /// Average time from the start of one feed to the start of the next.
        let day: TimeInterval?
        let night: TimeInterval?
        let dayCount: Int
        let nightCount: Int
    }

    struct DayValue: Identifiable, Equatable {
        let day: Date
        let duration: TimeInterval
        var id: Date { day }
    }

    enum Trend: Equatable {
        case longer, steady, shorter
    }

    struct LongestSleep {
        /// The longest sleep on each day (7 AM to 7 AM, so a night's sleep counts for one day).
        let byDay: [DayValue]
        /// The longest of them all; `day` is when it started.
        let longest: DayValue
        /// The second half of the days compared with the first, once there are at least 4.
        let trend: Trend?
    }

    struct AwakeStretch: Identifiable, Equatable {
        /// When the baby woke up.
        let start: Date
        let duration: TimeInterval
        var id: Date { start }
    }

    struct AwakeStretches {
        let stretches: [AwakeStretch]
        let median: TimeInterval
        /// The middle half of the stretches: 25th to 75th percentile.
        let low: TimeInterval
        let high: TimeInterval
    }

    struct DiaperTimes {
        /// Changes logged in each hour of the day, 0 = midnight.
        let byHour: [Int]
        /// Starting hours of the busiest two-hour windows, busiest first (one or two).
        let busiest: [Int]
        let total: Int
    }

    struct Report {
        let nightWakes: NightWakes?
        let feedGaps: FeedGaps?
        let longestSleep: LongestSleep?
        let awake: AwakeStretches?
        let diapers: DiaperTimes?
    }

    // MARK: Limits

    /// Feeds closer together than this are one feed, e.g. a breastfeed topped up with a bottle.
    static let sameFeed: TimeInterval = 20 * 60
    /// Longer gaps between feeds are probably feeds that weren't logged, so they're left out.
    static let maxFeedGap: TimeInterval = 8 * 3600
    /// Night events this close together are one wake-up (a diaper, then a feed).
    static let sameWake: TimeInterval = 45 * 60
    /// Wake-ups within this window of each other on different nights count as the same time.
    static let wakeWindow = 60
    /// Sleeps longer than this are probably a timer left running.
    static let maxSleep: TimeInterval = 16 * 3600
    /// Longer gaps between sleeps are probably sleeps that weren't logged.
    static let maxAwake: TimeInterval = 6 * 3600

    // MARK: Report

    /// Patterns over the last `days` days, today included. `untracked` is the time nobody logged
    /// (`Coverage.untracked`): a stretch between two entries that crosses it isn't read as a long gap.
    static func report(
        for activities: [Activity],
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        night: NightWindow = NightWindow(),
        untracked: [DateInterval] = []
    ) -> Report {
        let start = ReportBuilder.startDay(days: days, now: now, calendar: calendar)
        return report(events: events(from: activities), from: start, to: now, calendar: calendar, night: night, untracked: untracked)
    }

    static func report(
        events: [Event],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current,
        night: NightWindow = NightWindow(),
        untracked: [DateInterval] = []
    ) -> Report {
        let inRange = events.filter { $0.start >= start && $0.start <= end }
        let feeds = inRange.filter { $0.kind == .feed }.map(\.start).sorted()
        let diapers = inRange.filter { $0.kind == .diaper }.map(\.start)
        // Sleeps that ended in the range count too, e.g. one that began the evening before.
        let sleeps = events
            .filter { $0.kind == .sleep && ($0.start >= start || ($0.end ?? $0.start) >= start) && $0.start <= end }
            .sorted { $0.start < $1.start }

        return Report(
            nightWakes: nightWakes(feeds: feeds, sleeps: sleeps, others: inRange, from: start, to: end, calendar: calendar, night: night),
            feedGaps: feedGaps(feeds, calendar: calendar, night: night, untracked: untracked),
            longestSleep: longestSleep(sleeps, from: start, calendar: calendar, night: night),
            awake: awakeStretches(sleeps, calendar: calendar, night: night, untracked: untracked),
            diapers: diaperTimes(diapers, calendar: calendar)
        )
    }

    // MARK: Night wake-ups

    /// A wake-up is a feed, or the end of a sleep, during the night hours. Events close together
    /// are one wake-up. Wake-ups at a similar time on several nights make a usual time.
    static func nightWakes(
        feeds: [Date],
        sleeps: [Event],
        others: [Event],
        from start: Date,
        to end: Date,
        calendar: Calendar,
        night: NightWindow
    ) -> NightWakes? {
        let candidates = (feeds + sleeps.compactMap(\.end))
            .filter { $0 >= start && $0 <= end && night.contains($0, calendar: calendar) }
            .sorted()

        var wakesByNight: [Date: [Date]] = [:]
        for time in candidates {
            let key = night.nightStart(of: time, calendar: calendar)
            if let last = wakesByNight[key]?.last, time.timeIntervalSince(last) < sameWake {
                continue
            }
            wakesByNight[key, default: []].append(time)
        }

        // Every night with something logged in it, so nights the baby slept through count too.
        let loggedTimes = others.map(\.start) + sleeps.compactMap(\.end)
        let nights = Set(
            loggedTimes
                .filter { $0 >= start && $0 <= end && night.contains($0, calendar: calendar) }
                .map { night.nightStart(of: $0, calendar: calendar) }
        )
        guard nights.count >= 2 else { return nil }

        // Minutes since the night began, so 11 PM and 1 AM are 2 hours apart, not 22.
        var wakes: [(night: Date, minute: Int)] = []
        for (key, times) in wakesByNight {
            for time in times {
                wakes.append((night: key, minute: Int(time.timeIntervalSince(key) / 60)))
            }
        }
        wakes.sort { $0.minute < $1.minute }

        let needed = max(2, Int((Double(nights.count) * 0.4).rounded(.up)))
        var remaining = wakes
        var usual: [WakeTime] = []
        while !remaining.isEmpty && usual.count < 4 {
            // The hour-long window that came up on the most nights.
            var candidate: (from: Int, to: Int, nights: Int)?
            for (index, wake) in remaining.enumerated() {
                var last = index
                while last + 1 < remaining.count && remaining[last + 1].minute - wake.minute <= wakeWindow {
                    last += 1
                }
                let nightsInWindow = Set(remaining[index...last].map { $0.night }).count
                if nightsInWindow > (candidate?.nights ?? 0) {
                    candidate = (from: index, to: last, nights: nightsInWindow)
                }
            }
            guard let best = candidate, best.nights >= needed else { break }
            let minutes = remaining[best.from...best.to].map { Double($0.minute) }
            let middle = median(minutes) ?? minutes[0]
            let clock = (night.startHour * 60 + Int(middle)) % (24 * 60)
            let rounded = ((clock + 7) / 15 * 15) % (24 * 60)
            usual.append(WakeTime(minuteOfDay: rounded, nights: best.nights))
            remaining.removeSubrange(best.from...best.to)
        }

        // Earliest in the night first, so 11 PM comes before 2 AM.
        let nightOrder = { (minute: Int) in (minute - night.startHour * 60 + 24 * 60) % (24 * 60) }
        usual.sort { nightOrder($0.minuteOfDay) < nightOrder($1.minuteOfDay) }

        let total = wakesByNight.values.reduce(0) { $0 + $1.count }
        return NightWakes(
            usualTimes: usual,
            nights: nights.count,
            averagePerNight: Double(total) / Double(nights.count),
            allWakes: wakes.map { (night.startHour * 60 + $0.minute) % (24 * 60) }
        )
    }

    // MARK: Feeds

    /// Average time between feeds, split by whether the gap's midpoint was at night.
    /// Gaps that cross untracked time are left out: the feeds in between just weren't logged.
    static func feedGaps(_ feeds: [Date], calendar: Calendar, night: NightWindow, untracked: [DateInterval] = []) -> FeedGaps? {
        var sessions: [Date] = []
        for time in feeds.sorted() {
            if let last = sessions.last, time.timeIntervalSince(last) < sameFeed { continue }
            sessions.append(time)
        }
        guard sessions.count >= 3 else { return nil }

        var dayGaps: [TimeInterval] = []
        var nightGaps: [TimeInterval] = []
        for (previous, next) in zip(sessions, sessions.dropFirst()) {
            let gap = next.timeIntervalSince(previous)
            guard gap > 0, gap <= maxFeedGap, !crossesUntracked(previous, next, untracked) else { continue }
            let middle = previous.addingTimeInterval(gap / 2)
            if night.contains(middle, calendar: calendar) {
                nightGaps.append(gap)
            } else {
                dayGaps.append(gap)
            }
        }
        guard dayGaps.count + nightGaps.count >= 2 else { return nil }
        return FeedGaps(
            day: mean(dayGaps),
            night: mean(nightGaps),
            dayCount: dayGaps.count,
            nightCount: nightGaps.count
        )
    }

    // MARK: Sleep

    /// The day a sleep counts for: days run 7 AM to 7 AM, so a sleep that starts after midnight
    /// belongs to the evening before.
    private static func sleepDay(_ date: Date, calendar: Calendar, night: NightWindow) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-Double(night.endHour) * 3600))
    }

    static func longestSleep(_ sleeps: [Event], from start: Date, calendar: Calendar, night: NightWindow) -> LongestSleep? {
        var byDay: [Date: TimeInterval] = [:]
        var longestSoFar: DayValue?
        for sleep in sleeps {
            guard let end = sleep.end else { continue }
            let duration = end.timeIntervalSince(sleep.start)
            guard duration > 0, duration <= maxSleep else { continue }
            let day = sleepDay(sleep.start, calendar: calendar, night: night)
            guard day >= calendar.startOfDay(for: start) else { continue }
            byDay[day] = max(byDay[day] ?? 0, duration)
            if duration > (longestSoFar?.duration ?? 0) {
                longestSoFar = DayValue(day: sleep.start, duration: duration)
            }
        }
        guard let longest = longestSoFar, byDay.count >= 2 else { return nil }

        let days = byDay.keys.sorted().map { DayValue(day: $0, duration: byDay[$0] ?? 0) }
        var trend: Trend?
        if days.count >= 4 {
            let half = days.count / 2
            let earlier = mean(days.prefix(half).map(\.duration)) ?? 0
            let later = mean(days.suffix(half).map(\.duration)) ?? 0
            let difference = later - earlier
            // Within 20 minutes either way is about the same.
            if difference > 20 * 60 {
                trend = .longer
            } else if difference < -20 * 60 {
                trend = .shorter
            } else {
                trend = .steady
            }
        }
        return LongestSleep(byDay: days, longest: longest, trend: trend)
    }

    /// Time awake between the end of one sleep and the start of the next, for wake-ups during the
    /// day. Night wake-ups are usually a quick feed and back to sleep, so they're left out.
    static func awakeStretches(
        _ sleeps: [Event],
        calendar: Calendar,
        night: NightWindow,
        untracked: [DateInterval] = []
    ) -> AwakeStretches? {
        var stretches: [AwakeStretch] = []
        for (previous, next) in zip(sleeps, sleeps.dropFirst()) {
            guard let woke = previous.end, !night.contains(woke, calendar: calendar) else { continue }
            let awake = next.start.timeIntervalSince(woke)
            guard awake >= 5 * 60, awake <= maxAwake, !crossesUntracked(woke, next.start, untracked) else { continue }
            stretches.append(AwakeStretch(start: woke, duration: awake))
        }
        let durations = stretches.map(\.duration)
        guard stretches.count >= 3,
              let middle = median(durations),
              let low = quantile(durations, 0.25),
              let high = quantile(durations, 0.75)
        else { return nil }
        return AwakeStretches(stretches: stretches, median: middle, low: low, high: high)
    }

    // MARK: Diapers

    /// Changes by hour of day, and the busiest two-hour windows. A second window is only named
    /// when it's well apart from the first and nearly as busy.
    static func diaperTimes(_ diapers: [Date], calendar: Calendar) -> DiaperTimes? {
        guard diapers.count >= 5 else { return nil }
        var byHour = Array(repeating: 0, count: 24)
        for time in diapers {
            byHour[calendar.component(.hour, from: time)] += 1
        }
        let windows = (0..<24).map { byHour[$0] + byHour[($0 + 1) % 24] }
        guard let top = windows.indices.max(by: { windows[$0] < windows[$1] }), windows[top] >= 2 else {
            return DiaperTimes(byHour: byHour, busiest: [], total: diapers.count)
        }
        var busiest = [top]
        let apart = windows.indices.filter { hour in
            let distance = abs(hour - top)
            return min(distance, 24 - distance) >= 3
        }
        if let second = apart.max(by: { windows[$0] < windows[$1] }),
           windows[second] >= 3, Double(windows[second]) >= Double(windows[top]) * 0.75 {
            busiest.append(second)
        }
        return DiaperTimes(byHour: byHour, busiest: busiest, total: diapers.count)
    }

    // MARK: Math

    /// Whether the time from `start` to `end` overlaps any of `untracked`.
    static func crossesUntracked(_ start: Date, _ end: Date, _ untracked: [DateInterval]) -> Bool {
        untracked.contains { $0.start < end && $0.end > start }
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        quantile(values, 0.5)
    }

    /// Linear interpolation between the closest ranks.
    static func quantile(_ values: [Double], _ q: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
