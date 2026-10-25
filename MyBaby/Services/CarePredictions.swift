import CoreData
import Foundation

/// When the baby will probably want the next feed, or need the next diaper change, learned from the
/// last few days of the log. Today shows it under the "time since" cards, and smart reminders
/// (`SmartReminders`) go off around it.
///
/// It only describes what was logged, the same way Patterns does. It isn't medical advice: how long a
/// baby can go between feeds is a question for the pediatrician, and feed predictions never go past the
/// parent's own limit ("Never wait longer than…").
///
/// **Feeds** (`FeedPredictor`):
/// - It measures the time from the **start** of one feed to the **start** of the next, the way feeding
///   intervals are usually counted. Breastfeeds with minutes on each side still count from their start;
///   their length is only used to merge cluster feeds.
/// - Feeds less than `FeedPredictor.clusterGap` (40 min) after the previous one ended are one feed (a
///   breastfeed topped up with a bottle, or a feed in two goes), as long as the whole session spans less
///   than `FeedPredictor.maxSessionSpan` (90 min). Solids aren't counted.
/// - Only the last `lookback` (5 days) count, and each gap counts half as much for every `halfLife`
///   (1.5 days) it's older, because babies change fast.
/// - Day and night are learned separately: night is the night plan's hours when it's on, otherwise 7 PM
///   to 7 AM. A gap is day or night by when it began. With fewer than `minBucket` (4) gaps of the right
///   kind, all the gaps are used.
/// - The prediction is the weighted median; the likely range is the middle half (weighted 25th to 75th
///   percentile), so one odd gap doesn't move it.
/// - **Honest data:** a gap is skipped when it crosses time nobody tracked (*Not tracked* periods, and the
///   long stretches with nothing logged that `Coverage` marks as missing), when either end was added with
///   Catch up (approximate), or when it's longer than `longestGap` (8 hours), which means feeds weren't
///   logged. So a forgotten night doesn't teach it that the baby sleeps 9 hours.
/// - With fewer than `minIntervals` (8) usable gaps it's a rough guess (`.low`): the parent's "every few
///   hours" setting when there is one, or else a common gap for the baby's age (`FeedPredictor.typicalGap`).
/// - **Safety:** the prediction, day or night, is never later than the parent's maximum
///   (`CareSettings.maxInterval`).
/// - A breastfeeding timer that's running means "feeding now": there's no prediction until it's saved.
///
/// **Diapers** (`DiaperPredictor`) work the same way from the changes, with changes less than 10 minutes
/// apart counted once and no maximum. It also learns whether changes usually come soon after a feed (at
/// least 60% within 30 minutes of a feed ending); then the next change is expected after the next feed.
///
/// Everything here is a pure function of a `CareLog`, the settings and a time, so it can be checked
/// without Core Data (see `checkSampleScenarios()` in debug builds). Everything is worked out on the
/// iPhone; nothing is sent anywhere.
enum CarePredictions {
    /// How far back the log is read.
    static let lookback: TimeInterval = 5 * 86_400
    /// A gap counts half as much for every this much older it is.
    static let halfLife: TimeInterval = 1.5 * 86_400
    /// The night when the night plan is off: 7 PM to 7 AM.
    static let defaultNight = Coverage.NightHours(startMinutes: 19 * 60, endMinutes: 7 * 60)

    /// The night plan's hours when it's on, otherwise 7 PM to 7 AM.
    static func nightHours(plan: NightPlan) -> Coverage.NightHours {
        plan.isEnabled
            ? Coverage.NightHours(startMinutes: plan.nightStartMinutes, endMinutes: plan.nightEndMinutes)
            : defaultNight
    }

    // MARK: Gaps

    /// A feed session or a change, reduced to when it was and whether it was approximate.
    struct Point: Equatable {
        var date: Date
        var isApproximate = false
    }

    /// The time from one feed (or change) to the next.
    struct Gap: Equatable {
        /// When it began.
        var start: Date
        var length: TimeInterval
        /// 1 for a gap that began now, halving every `halfLife`.
        var weight: Double
        var isNight: Bool
    }

    struct Gaps: Equatable {
        var usable: [Gap]
        /// Gaps left out: they crossed untracked time, touched an approximate entry, or were too long.
        var excluded: Int
        /// How many separate untracked stretches made a gap be left out.
        var skippedStretches: Int
    }

    /// The gaps between consecutive `points` that began at or after `start`, with the ones that can't be
    /// trusted left out (see the type's notes).
    static func gaps(
        between points: [Point],
        since start: Date,
        now: Date,
        untracked: [DateInterval],
        longest: TimeInterval,
        night: Coverage.NightHours,
        calendar: Calendar
    ) -> Gaps {
        var usable: [Gap] = []
        var excluded = 0
        var stretches = Set<Int>()
        let sorted = points.sorted { $0.date < $1.date }
        for (from, to) in zip(sorted, sorted.dropFirst()) where from.date >= start && to.date <= now {
            let length = to.date.timeIntervalSince(from.date)
            guard length > 0 else { continue }
            let crossed = untracked.indices.filter { untracked[$0].start < to.date && untracked[$0].end > from.date }
            if !crossed.isEmpty {
                stretches.formUnion(crossed)
                excluded += 1
                continue
            }
            if from.isApproximate || to.isApproximate || length > longest {
                excluded += 1
                continue
            }
            let age = max(0, now.timeIntervalSince(from.date))
            usable.append(Gap(
                start: from.date,
                length: length,
                weight: pow(0.5, age / halfLife),
                isNight: night.isNight(from.date, calendar: calendar)
            ))
        }
        return Gaps(usable: usable, excluded: excluded, skippedStretches: stretches.count)
    }

    /// The `q` quantile (0 to 1) of the gaps' lengths, each counting by its weight. Each gap sits in the
    /// middle of its share of the total weight, with straight lines in between.
    static func weightedQuantile(_ gaps: [Gap], _ q: Double) -> TimeInterval? {
        let sorted = gaps.filter { $0.weight > 0 }.sorted { $0.length < $1.length }
        let total = sorted.reduce(0) { $0 + $1.weight }
        guard total > 0, let first = sorted.first, let last = sorted.last else { return nil }
        var positions: [Double] = []
        var running = 0.0
        for gap in sorted {
            positions.append((running + gap.weight / 2) / total)
            running += gap.weight
        }
        if q <= positions[0] { return first.length }
        for index in 1..<sorted.count where q <= positions[index] {
            let lower = positions[index - 1]
            let upper = positions[index]
            let fraction = upper > lower ? (q - lower) / (upper - lower) : 0
            return sorted[index - 1].length + (sorted[index].length - sorted[index - 1].length) * fraction
        }
        return last.length
    }

    /// How many whole days back the oldest usable gap began, 1 to 5.
    static func daysCovered(_ gaps: [Gap], now: Date) -> Int {
        guard let oldest = gaps.map(\.start).min() else { return Int(lookback / 86_400) }
        let days = Int((now.timeIntervalSince(oldest) / 86_400).rounded(.up))
        return max(1, min(Int(lookback / 86_400), days))
    }

    /// "Usually every 2 h 50 min in the daytime, about 3 h 30 min at night, from the last 3 days."
    static func usualSentence(_ gaps: [Gap], days: Int, minBucket: Int) -> String {
        let day = gaps.filter { !$0.isNight }
        let night = gaps.filter(\.isNight)
        let dayMedian = day.count >= minBucket ? weightedQuantile(day, 0.5) : nil
        let nightMedian = night.count >= minBucket ? weightedQuantile(night, 0.5) : nil
        let span = lastDays(days)
        switch (dayMedian, nightMedian) {
        case let (dayGap?, nightGap?):
            return "Usually every \(describe(dayGap)) in the daytime, about \(describe(nightGap)) at night, from \(span)."
        case let (dayGap?, nil):
            return "Usually every \(describe(dayGap)) in the daytime, from \(span)."
        case let (nil, nightGap?):
            return "Usually every \(describe(nightGap)) at night, from \(span)."
        case (nil, nil):
            return "Usually every \(describe(weightedQuantile(gaps, 0.5) ?? 0)), from \(span)."
        }
    }

    /// "the last day" or "the last 3 days".
    static func lastDays(_ days: Int) -> String {
        days == 1 ? "the last day" : "the last \(days) days"
    }

    // MARK: Wording

    /// "2 h 50 min", "45 min" or "3 h", rounded to 5 minutes from an hour up, the way a person would say it.
    static func describe(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let rounded = minutes >= 60 ? Int((Double(minutes) / 5).rounded()) * 5 : minutes
        let hours = rounded / 60
        let rest = rounded % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// `text` with "2 h 50 min" written out as "2 hours 50 minutes", for VoiceOver.
    static func spoken(_ text: String) -> String {
        var result = text
        for (pattern, unit) in [("(\\d+) h\\b", "hour"), ("(\\d+) min\\b", "minute")] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result),
                      let digits = Range(match.range(at: 1), in: result),
                      let number = Int(result[digits])
                else { continue }
                result.replaceSubrange(whole, with: Format.plural(number, unit))
            }
        }
        return result
    }

    /// "2:40 AM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Input and output

/// Which prediction or reminder.
enum PredictionKind: String, Codable, CaseIterable, Identifiable {
    case feed, diaper

    var id: String { rawValue }
}

/// What the predictors read: the last few days of one baby's log, without Core Data.
struct CareLog: Equatable {
    struct Feed: Equatable {
        var start: Date
        /// When a breastfeed with minutes on each side ended; the same as `start` for anything else.
        var end: Date
        /// Added with Catch up.
        var isApproximate = false
    }

    struct Change: Equatable {
        var date: Date
        var isApproximate = false
    }

    struct Sleep: Equatable {
        var start: Date
        /// `nil` while the baby is still asleep.
        var end: Date?
    }

    /// Oldest first. Solids aren't included.
    var feeds: [Feed] = []
    /// Diaper changes, oldest first.
    var changes: [Change] = []
    /// Oldest first.
    var sleeps: [Sleep] = []
    /// Time nobody tracked (`Coverage.untracked`): *Not tracked* periods, and long stretches with nothing logged.
    var untracked: [DateInterval] = []
    var night = CarePredictions.defaultNight
    var birthDate: Date?
    /// A breastfeeding timer is running for this baby.
    var isFeedingNow = false

    /// Whether a sleep is going on at `now`.
    func isAsleep(at now: Date) -> Bool {
        sleeps.contains { $0.end == nil && $0.start <= now }
    }

    /// The sleep that ended most recently.
    var lastFinishedSleep: Sleep? {
        sleeps.filter { $0.end != nil }.max { ($0.end ?? .distantPast) < ($1.end ?? .distantPast) }
    }
}

/// The parent's settings the feed predictor needs.
struct CareSettings: Equatable {
    /// The "every few hours" reminder setting, when the parent has one.
    var fixedInterval: TimeInterval?
    /// "Never wait longer than…": no feed prediction is later than this after the last feed.
    var maxInterval: TimeInterval = 3 * 3600

    /// From Settings: the maximum defaults to the "every few hours" setting, or 3 hours.
    static func load(from defaults: UserDefaults = .shared) -> CareSettings {
        let hours = defaults.object(forKey: SettingsKey.feedingReminderHours) as? Double
        let fixed = hours ?? (FeedReminderMode.current(defaults) == .fixed ? 3 : nil)
        let maximum = (defaults.object(forKey: SettingsKey.feedMaxIntervalHours) as? Double).flatMap { $0 > 0 ? $0 : nil }
        return CareSettings(
            fixedInterval: fixed.map { $0 * 3600 },
            maxInterval: (maximum ?? hours ?? 3) * 3600
        )
    }
}

/// When the next feed or change will probably be, how sure that is, and why.
struct CarePrediction: Equatable, Identifiable {
    enum Confidence: Int, Comparable {
        /// Not enough logged yet: a fixed or typical gap. Today doesn't show these.
        case low
        case medium
        /// Plenty of recent gaps of the same kind (day or night), close together.
        case high

        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .low: return "Rough guess: not much logged yet"
            case .medium: return "Fairly steady pattern"
            case .high: return "Steady pattern"
            }
        }

        var systemImage: String {
            switch self {
            case .low: return "questionmark.circle"
            case .medium: return "chart.bar"
            case .high: return "chart.bar.fill"
            }
        }
    }

    /// What it was worked out from, for "From 24 feeds in the last 3 days; 2 missing stretches skipped".
    struct Basis: Equatable {
        /// Feed sessions (cluster feeds counted once) or changes in the last 5 days.
        var events: Int
        var usableGaps: Int
        var excludedGaps: Int
        var days: Int
        var skippedStretches: Int
        /// How many usable gaps a learned prediction needs.
        var gapsNeeded: Int
    }

    let kind: PredictionKind
    let expected: Date
    let earliest: Date
    let latest: Date
    let confidence: Confidence
    /// "Usually every 2 h 50 min in the daytime, about 3 h 30 min at night, from the last 3 days."
    let explanation: String
    /// The learned usual gap; `nil` for a rough guess.
    let usualInterval: TimeInterval?
    /// What it counts from: the start of the last feed, or the last change.
    let lastEvent: Date
    let basis: Basis
    /// The feed prediction was moved earlier to the parent's maximum.
    var wasCapped = false
    /// Diapers: most changes come soon after a feed, so this one is expected after the next feed.
    var followsFeeds = false

    var id: String { "\(kind.rawValue)-\(expected.timeIntervalSince1970)" }

    /// "From 24 feeds in the last 3 days; 2 missing stretches skipped."
    var dataSummary: String {
        let things = Format.plural(basis.events, kind == .feed ? "feed" : "change")
        var text = "From \(things) in \(CarePredictions.lastDays(basis.days))"
        switch basis.skippedStretches {
        case 0: break
        case 1: text += "; 1 missing stretch skipped"
        default: text += "; \(basis.skippedStretches) missing stretches skipped"
        }
        text += "."
        if confidence == .low {
            let between = kind == .feed ? "feeds" : "changes"
            text += " That's \(Format.plural(basis.usableGaps, "usable gap")) between \(between); about \(basis.gapsNeeded) are needed to learn a pattern."
        }
        return text
    }

    /// For the reminder: "usually every 2 h 50 min", "your 3 h limit" or "3 h since the last feed".
    var reminderReason: String {
        let since = CarePredictions.describe(expected.timeIntervalSince(lastEvent))
        if wasCapped { return "your \(since) limit" }
        if let usualInterval, confidence > .low { return "usually every \(CarePredictions.describe(usualInterval))" }
        return "\(since) since the last feed"
    }
}

// MARK: - Feeds

enum FeedPredictor {
    /// Feeds starting less than this after the previous one ended are one session.
    static let clusterGap: TimeInterval = 40 * 60
    /// …unless the session would then span longer than this, so an evening of cluster feeding still
    /// counts as several feeds.
    static let maxSessionSpan: TimeInterval = 90 * 60
    /// Longer gaps mean feeds weren't logged.
    static let longestGap: TimeInterval = 8 * 3600
    /// Usable gaps needed to learn a pattern.
    static let minIntervals = 8
    /// Gaps of the same kind (day or night) needed to use only those.
    static let minBucket = 4
    /// For `.high`: at least this many gaps of the same kind…
    static let highConfidenceCount = 12
    /// …with the middle half within this share of the median.
    static let highConfidenceSpread = 0.35
    /// The likely range either side of a rough guess.
    static let roughSpread: TimeInterval = 15 * 60

    /// Feeds merged into sessions (see `clusterGap`), oldest first.
    struct Session: Equatable {
        var start: Date
        var end: Date
        var feedCount: Int
        var isApproximate: Bool
    }

    static func sessions(_ feeds: [CareLog.Feed]) -> [Session] {
        var result: [Session] = []
        for feed in feeds.sorted(by: { $0.start < $1.start }) {
            let end = max(feed.end, feed.start)
            if var last = result.last,
               feed.start.timeIntervalSince(last.end) < clusterGap,
               end.timeIntervalSince(last.start) < maxSessionSpan {
                last.end = max(last.end, end)
                last.feedCount += 1
                last.isApproximate = last.isApproximate || feed.isApproximate
                result[result.count - 1] = last
            } else {
                result.append(Session(start: feed.start, end: end, feedCount: 1, isApproximate: feed.isApproximate))
            }
        }
        return result
    }

    /// A common gap between feeds for the baby's age, only used until there's enough logged: 2.5 hours in
    /// the first 4 weeks, 3 hours to 3 months, 3.5 hours to 6 months, then 4 hours (3 hours without a
    /// birth date). Always capped by the parent's maximum. Not a recommendation.
    static func typicalGap(birthDate: Date?, now: Date) -> TimeInterval {
        guard let birthDate else { return 3 * 3600 }
        let days = now.timeIntervalSince(birthDate) / 86_400
        switch days {
        case ..<28: return 2.5 * 3600
        case ..<91: return 3 * 3600
        case ..<182: return 3.5 * 3600
        default: return 4 * 3600
        }
    }

    /// The next feed after the last one logged by `now`. `nil` while breastfeeding (`isFeedingNow`) and
    /// before any feed was logged.
    static func predict(
        _ log: CareLog,
        settings: CareSettings,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CarePrediction? {
        guard !log.isFeedingNow else { return nil }
        let sessions = self.sessions(log.feeds.filter { $0.start <= now })
        guard let last = sessions.last else { return nil }

        let windowStart = now.addingTimeInterval(-CarePredictions.lookback)
        let gaps = CarePredictions.gaps(
            between: sessions.map { CarePredictions.Point(date: $0.start, isApproximate: $0.isApproximate) },
            since: windowStart,
            now: now,
            untracked: log.untracked,
            longest: longestGap,
            night: log.night,
            calendar: calendar
        )
        let days = CarePredictions.daysCovered(gaps.usable, now: now)
        let basis = CarePrediction.Basis(
            events: sessions.filter { $0.start >= windowStart }.count,
            usableGaps: gaps.usable.count,
            excludedGaps: gaps.excluded,
            days: days,
            skippedStretches: gaps.skippedStretches,
            gapsNeeded: minIntervals
        )
        // Never less than half an hour, whatever was saved.
        let cap = max(settings.maxInterval, 30 * 60)
        let limit = last.start.addingTimeInterval(cap)

        let isNight = log.night.isNight(last.start, calendar: calendar)
        let bucket = gaps.usable.filter { $0.isNight == isNight }
        let sample = bucket.count >= minBucket ? bucket : gaps.usable
        guard gaps.usable.count >= minIntervals,
              let median = CarePredictions.weightedQuantile(sample, 0.5),
              let lower = CarePredictions.weightedQuantile(sample, 0.25),
              let upper = CarePredictions.weightedQuantile(sample, 0.75)
        else {
            return roughGuess(after: last.start, log: log, settings: settings, cap: cap, basis: basis, now: now)
        }

        let spread = median > 0 ? (upper - lower) / median : 1
        let confidence: CarePrediction.Confidence =
            bucket.count >= highConfidenceCount && spread <= highConfidenceSpread ? .high : .medium
        let capped = median > cap
        let usual = min(median, cap)
        var explanation = CarePredictions.usualSentence(gaps.usable, days: days, minBucket: minBucket)
        if capped {
            explanation += " That's longer than your \(CarePredictions.describe(cap)) limit, so this uses the limit."
        }
        return CarePrediction(
            kind: .feed,
            expected: last.start.addingTimeInterval(usual),
            earliest: last.start.addingTimeInterval(min(lower, usual)),
            latest: min(last.start.addingTimeInterval(upper), limit),
            confidence: confidence,
            explanation: explanation,
            usualInterval: median,
            lastEvent: last.start,
            basis: basis,
            wasCapped: capped
        )
    }

    /// Not enough logged: the parent's "every few hours" setting, or a typical gap for the age.
    private static func roughGuess(
        after start: Date,
        log: CareLog,
        settings: CareSettings,
        cap: TimeInterval,
        basis: CarePrediction.Basis,
        now: Date
    ) -> CarePrediction {
        let wanted = settings.fixedInterval ?? typicalGap(birthDate: log.birthDate, now: now)
        let interval = min(wanted, cap)
        let expected = start.addingTimeInterval(interval)
        let source = settings.fixedInterval != nil
            ? "your \(CarePredictions.describe(wanted)) reminder setting"
            : "about \(CarePredictions.describe(wanted)), a common gap at this age"
        var explanation = "Not enough feeds logged in the last few days to learn a pattern yet, so this uses \(source)."
        if wanted > cap {
            explanation += " That's longer than your \(CarePredictions.describe(cap)) limit, so this uses the limit."
        }
        return CarePrediction(
            kind: .feed,
            expected: expected,
            earliest: expected.addingTimeInterval(-roughSpread),
            latest: min(expected.addingTimeInterval(roughSpread), start.addingTimeInterval(cap)),
            confidence: .low,
            explanation: explanation,
            usualInterval: nil,
            lastEvent: start,
            basis: basis,
            wasCapped: wanted > cap
        )
    }
}

// MARK: - Diapers

enum DiaperPredictor {
    /// Changes less than this apart are one (logged twice, or a change and a quick fix).
    static let sameChange: TimeInterval = 10 * 60
    static let longestGap: TimeInterval = 8 * 3600
    /// A change this soon after a feed ended "follows" it.
    static let followWindow: TimeInterval = 30 * 60
    /// The share of changes that must follow a feed to expect the next one after the next feed.
    static let followShare = 0.6
    static let minIntervals = 8
    static let minBucket = 4
    /// Until there's enough logged.
    static let roughGap: TimeInterval = 3 * 3600
    static let roughSpread: TimeInterval = 30 * 60

    /// Changes with the ones close together merged, oldest first.
    static func merged(_ changes: [CareLog.Change]) -> [CareLog.Change] {
        var result: [CareLog.Change] = []
        for change in changes.sorted(by: { $0.date < $1.date }) {
            if let last = result.last, change.date.timeIntervalSince(last.date) < sameChange {
                result[result.count - 1].isApproximate = last.isApproximate || change.isApproximate
                continue
            }
            result.append(change)
        }
        return result
    }

    /// How often changes follow a feed, and how long after the feed began they usually come.
    static func feedLink(
        changes: [CareLog.Change],
        sessions: [FeedPredictor.Session]
    ) -> (share: Double, delay: TimeInterval?) {
        guard !changes.isEmpty else { return (0, nil) }
        var delays: [Double] = []
        for change in changes {
            let feed = sessions.last { $0.start <= change.date && change.date <= $0.end.addingTimeInterval(followWindow) }
            if let feed { delays.append(change.date.timeIntervalSince(feed.start)) }
        }
        return (Double(delays.count) / Double(changes.count), PatternFinder.median(delays))
    }

    /// The next change after the last one logged by `now`, or `nil` before any. `nextFeed` is the feed
    /// prediction, used when changes usually follow feeds.
    static func predict(
        _ log: CareLog,
        nextFeed: CarePrediction?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CarePrediction? {
        let changes = merged(log.changes.filter { $0.date <= now })
        guard let last = changes.last else { return nil }

        let windowStart = now.addingTimeInterval(-CarePredictions.lookback)
        let gaps = CarePredictions.gaps(
            between: changes.map { CarePredictions.Point(date: $0.date, isApproximate: $0.isApproximate) },
            since: windowStart,
            now: now,
            untracked: log.untracked,
            longest: longestGap,
            night: log.night,
            calendar: calendar
        )
        let recent = changes.filter { $0.date >= windowStart }
        let days = CarePredictions.daysCovered(gaps.usable, now: now)
        let basis = CarePrediction.Basis(
            events: recent.count,
            usableGaps: gaps.usable.count,
            excludedGaps: gaps.excluded,
            days: days,
            skippedStretches: gaps.skippedStretches,
            gapsNeeded: minIntervals
        )
        let usualSentence = gaps.usable.count >= minIntervals
            ? " " + CarePredictions.usualSentence(gaps.usable, days: days, minBucket: minBucket)
            : ""

        // Changes that usually come soon after a feed.
        let sessions = FeedPredictor.sessions(log.feeds.filter { $0.start <= now })
        let link = feedLink(changes: recent.filter { !$0.isApproximate }, sessions: sessions)
        if recent.count >= minIntervals, link.share >= followShare, let delay = link.delay {
            let percent = Int((link.share * 100).rounded())
            let linked = "About \(percent)% of changes come within \(CarePredictions.describe(followWindow)) after a feed"
            // A feed going on or just finished, with no change since: soon after it.
            if let feed = sessions.last, feed.start > last.date, now <= feed.end.addingTimeInterval(followWindow) {
                let expected = feed.start.addingTimeInterval(delay)
                return CarePrediction(
                    kind: .diaper,
                    expected: expected,
                    earliest: min(feed.end, expected),
                    latest: max(feed.end.addingTimeInterval(followWindow), expected),
                    confidence: .medium,
                    explanation: linked + ", so one is probably due soon after this feed." + usualSentence,
                    usualInterval: nil,
                    lastEvent: last.date,
                    basis: basis,
                    followsFeeds: true
                )
            }
            if let nextFeed {
                let confidence: CarePrediction.Confidence =
                    link.share >= 0.8 && nextFeed.confidence == .high ? .high : min(.medium, nextFeed.confidence)
                return CarePrediction(
                    kind: .diaper,
                    expected: nextFeed.expected.addingTimeInterval(delay),
                    earliest: nextFeed.earliest.addingTimeInterval(delay),
                    latest: nextFeed.latest.addingTimeInterval(delay),
                    confidence: confidence,
                    explanation: linked + ", so the next one will probably be after the next feed." + usualSentence,
                    usualInterval: nil,
                    lastEvent: last.date,
                    basis: basis,
                    followsFeeds: true
                )
            }
        }

        let isNight = log.night.isNight(last.date, calendar: calendar)
        let bucket = gaps.usable.filter { $0.isNight == isNight }
        let sample = bucket.count >= minBucket ? bucket : gaps.usable
        guard gaps.usable.count >= minIntervals,
              let median = CarePredictions.weightedQuantile(sample, 0.5),
              let lower = CarePredictions.weightedQuantile(sample, 0.25),
              let upper = CarePredictions.weightedQuantile(sample, 0.75)
        else {
            let expected = last.date.addingTimeInterval(roughGap)
            return CarePrediction(
                kind: .diaper,
                expected: expected,
                earliest: expected.addingTimeInterval(-roughSpread),
                latest: expected.addingTimeInterval(roughSpread),
                confidence: .low,
                explanation: "Not enough changes logged in the last few days to learn a pattern yet, so this uses \(CarePredictions.describe(roughGap)) after the last change.",
                usualInterval: nil,
                lastEvent: last.date,
                basis: basis
            )
        }
        let spread = median > 0 ? (upper - lower) / median : 1
        return CarePrediction(
            kind: .diaper,
            expected: last.date.addingTimeInterval(median),
            earliest: last.date.addingTimeInterval(lower),
            latest: last.date.addingTimeInterval(upper),
            confidence: bucket.count >= FeedPredictor.highConfidenceCount && spread <= FeedPredictor.highConfidenceSpread ? .high : .medium,
            explanation: CarePredictions.usualSentence(gaps.usable, days: days, minBucket: minBucket),
            usualInterval: median,
            lastEvent: last.date,
            basis: basis
        )
    }
}

// MARK: - From the log

extension CareLog {
    /// `activities` (any kinds, e.g. the last few days plus a sleep still going on) and the marked
    /// `periods`, with the untracked time worked out by `Coverage`.
    init(
        activities: [Activity],
        periods: [TrackingPeriod],
        birthDate: Date?,
        now: Date = .now,
        plan: NightPlan = .load(),
        isFeedingNow: Bool = false,
        calendar: Calendar = .current
    ) {
        // A deleted entry can still be in a fetch's results for a moment, and its dates can't be read.
        var seen = Set<NSManagedObjectID>()
        let entries = activities.filter { activity in
            !activity.isDeleted && activity.managedObjectContext != nil && seen.insert(activity.objectID).inserted
        }
        let marked = periods.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        let coverage = Coverage(activities: entries, periods: marked, now: now, plan: plan, calendar: calendar)
        // Before the first entry read here isn't missing data, just older than what was fetched.
        let earliest = entries.map(\.startDate).min() ?? now
        let untracked = coverage.untracked.filter { $0.end > earliest }

        var feeds: [Feed] = []
        var changes: [Change] = []
        var sleeps: [Sleep] = []
        for activity in entries {
            switch activity.kind {
            case .feeding where activity.feedingType != .solids:
                let minutes = activity.feedingType == .breast ? activity.breastMinutes : 0
                feeds.append(Feed(
                    start: activity.startDate,
                    end: activity.startDate.addingTimeInterval(Double(minutes) * 60),
                    isApproximate: activity.isApproximate
                ))
            case .diaper:
                changes.append(Change(date: activity.startDate, isApproximate: activity.isApproximate))
            case .sleep:
                sleeps.append(Sleep(start: activity.startDate, end: activity.endDate))
            default:
                break
            }
        }
        self.init(
            feeds: feeds.sorted { $0.start < $1.start },
            changes: changes.sorted { $0.date < $1.date },
            sleeps: sleeps.sorted { $0.start < $1.start },
            untracked: untracked,
            night: CarePredictions.nightHours(plan: plan),
            birthDate: birthDate,
            isFeedingNow: isFeedingNow
        )
    }

    /// Where a fetch for the predictors starts: midnight a day before the lookback begins. It's the same
    /// all day, so a view's fetch request doesn't change every minute.
    static func fetchStart(now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now.addingTimeInterval(-CarePredictions.lookback))
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    /// `baby`'s recent log, read from `context`.
    static func load(
        for baby: Baby,
        context: NSManagedObjectContext,
        now: Date = .now,
        plan: NightPlan = .load(),
        timer: FeedingTimerState? = FeedingTimerState.load()
    ) -> CareLog {
        let since = fetchStart(now: now)
        let recent = (try? context.fetch(baby.entries(Activity.since(since)))) ?? []
        let ongoing = (try? context.fetch(baby.entries(Activity.ongoingSleep))) ?? []
        let periods = (try? context.fetch(baby.entries(TrackingPeriod.overlapping(since, now)))) ?? []
        return CareLog(
            activities: recent + ongoing,
            periods: periods,
            birthDate: baby.birthDate,
            now: now,
            plan: plan,
            isFeedingNow: isFeeding(baby, timer: timer)
        )
    }

    /// Whether `timer` is feeding `baby`. A timer without a baby is for the one shown in the app.
    static func isFeeding(_ baby: Baby, timer: FeedingTimerState?) -> Bool {
        guard let timer else { return false }
        if let id = timer.babyID { return id == baby.uuid?.uuidString }
        guard let context = baby.managedObjectContext else { return true }
        return Baby.current(in: context) == baby
    }
}

extension CarePredictions {
    /// When `baby`'s next feed is expected, for the widgets: only a learned prediction (not a rough
    /// guess), to the minute. `nil` while breastfeeding.
    static func nextFeedForWidget(baby: Baby, context: NSManagedObjectContext, now: Date = .now) -> Date? {
        let log = CareLog.load(for: baby, context: context, now: now)
        guard let prediction = FeedPredictor.predict(log, settings: .load(), now: now),
              prediction.confidence > .low
        else { return nil }
        return Date(timeIntervalSince1970: (prediction.expected.timeIntervalSince1970 / 60).rounded() * 60)
    }
}

// MARK: - Sample scenarios

#if DEBUG
extension CarePredictions {
    /// Sample scenarios for the predictors, to check them by hand (the project has no test target). Run
    /// `po CarePredictions.checkSampleScenarios()` in the debugger: it returns what didn't come out as
    /// expected, so an empty list means every scenario passed. Each one builds a `CareLog` by hand on a
    /// fixed UTC calendar, so the results don't depend on the time zone or the date.
    ///
    /// 1. **Steady log**: feeds every 3 h in the day and every 4 h at night for 4 days. The next feed is
    ///    3 h (or 4 h at night) after the last, with high confidence.
    /// 2. **Cluster feed**: a 20-minute breastfeed topped up with a bottle 20 minutes later is one session.
    /// 3. **Forgotten night**: 6 hours with nothing logged one night, marked Not tracked. The 8-hour gap
    ///    across it is skipped (1 missing stretch), so no usable gap is longer than 4 h.
    /// 4. **Too little data**: 4 feeds. Low confidence, using the 2.5 h "every few hours" setting.
    /// 5. **Safety limit**: feeds every 4 h with a 3 h maximum. Expected exactly 3 h after the last feed,
    ///    marked as capped, and the range never goes past it.
    /// 6. **Feeding now**: a running breastfeeding timer. No feed prediction.
    /// 7. **Diapers after feeds**: a change 10 minutes after most feeds. Expected 10 minutes after the
    ///    next feed, marked as following feeds.
    static func checkSampleScenarios() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)) ?? .now
        let night = defaultNight
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let roomy = CareSettings(fixedInterval: nil, maxInterval: 5 * 3600)

        // 1. Steady log.
        let steady = CareLog(feeds: sampleFeeds(until: now, days: 4, day: 3 * 3600, night: 4 * 3600, nightHours: night, calendar: calendar), night: night)
        if let prediction = FeedPredictor.predict(steady, settings: roomy, now: now, calendar: calendar),
           let last = steady.feeds.last {
            let wanted: TimeInterval = night.isNight(last.start, calendar: calendar) ? 4 * 3600 : 3 * 3600
            check(abs(prediction.expected.timeIntervalSince(last.start) - wanted) < 60, "1: expected \(describe(wanted)) after the last feed")
            check(prediction.confidence == .high, "1: confidence should be high, was \(prediction.confidence)")
        } else {
            failures.append("1: no prediction")
        }

        // 2. Cluster feed.
        let breastfeed = CareLog.Feed(start: now, end: now.addingTimeInterval(20 * 60))
        let topUp = CareLog.Feed(start: now.addingTimeInterval(40 * 60), end: now.addingTimeInterval(40 * 60))
        check(FeedPredictor.sessions([breastfeed, topUp]).count == 1, "2: a top-up should merge into the feed")

        // 3. Forgotten night.
        let missing = DateInterval(
            start: now.addingTimeInterval(-2 * 86_400 + 10 * 3600),
            end: now.addingTimeInterval(-2 * 86_400 + 16 * 3600)
        )
        var forgotten = steady
        forgotten.feeds.removeAll { missing.contains($0.start) }
        forgotten.untracked = [missing]
        let found = Self.gaps(
            between: forgotten.feeds.map { Point(date: $0.start) },
            since: now.addingTimeInterval(-lookback),
            now: now,
            untracked: forgotten.untracked,
            longest: FeedPredictor.longestGap,
            night: night,
            calendar: calendar
        )
        check(found.skippedStretches == 1, "3: the not-tracked night should be skipped")
        check(found.usable.allSatisfy { $0.length <= 4 * 3600 }, "3: no gap across the missing night")

        // 4. Too little data.
        var fewFeeds: [CareLog.Feed] = []
        for hoursAgo in [9.0, 6.0, 3.0, 0.0] {
            let time = now.addingTimeInterval(-hoursAgo * 3600)
            fewFeeds.append(CareLog.Feed(start: time, end: time))
        }
        let few = CareLog(feeds: fewFeeds, night: night)
        let fixed = CareSettings(fixedInterval: 2.5 * 3600, maxInterval: 3 * 3600)
        if let prediction = FeedPredictor.predict(few, settings: fixed, now: now, calendar: calendar) {
            check(prediction.confidence == .low, "4: confidence should be low")
            check(prediction.expected == now.addingTimeInterval(2.5 * 3600), "4: should use the 2.5 h setting")
        } else {
            failures.append("4: no prediction")
        }

        // 5. Safety limit.
        let slow = CareLog(feeds: sampleFeeds(until: now, days: 4, day: 4 * 3600, night: 4 * 3600, nightHours: night, calendar: calendar), night: night)
        let strict = CareSettings(fixedInterval: nil, maxInterval: 3 * 3600)
        if let prediction = FeedPredictor.predict(slow, settings: strict, now: now, calendar: calendar),
           let last = slow.feeds.last {
            check(prediction.expected == last.start.addingTimeInterval(3 * 3600), "5: should be capped at 3 h")
            check(prediction.wasCapped, "5: should say it was capped")
            check(prediction.latest <= last.start.addingTimeInterval(3 * 3600), "5: the range should stay within the limit")
        } else {
            failures.append("5: no prediction")
        }

        // 6. Feeding now.
        var feeding = steady
        feeding.isFeedingNow = true
        check(FeedPredictor.predict(feeding, settings: roomy, now: now, calendar: calendar) == nil, "6: no prediction while feeding")

        // 7. Diapers after feeds: after 5 of every 6 feeds.
        var linked = steady
        linked.changes = steady.feeds.enumerated()
            .filter { $0.offset % 6 != 5 }
            .map { CareLog.Change(date: $0.element.start.addingTimeInterval(10 * 60)) }
            .filter { $0.date <= now }
        let nextFeed = FeedPredictor.predict(linked, settings: roomy, now: now, calendar: calendar)
        if let nextFeed, let lastFeed = linked.feeds.last?.start,
           let diaper = DiaperPredictor.predict(linked, nextFeed: nextFeed, now: now, calendar: calendar) {
            check(diaper.followsFeeds, "7: changes should follow feeds")
            let justFed = diaper.lastEvent < lastFeed && now <= lastFeed.addingTimeInterval(DiaperPredictor.followWindow)
            if justFed {
                // The last feed has no change yet: soon after it.
                check(abs(diaper.expected.timeIntervalSince(lastFeed) - 10 * 60) < 60, "7: 10 min after this feed")
            } else {
                check(abs(diaper.expected.timeIntervalSince(nextFeed.expected) - 10 * 60) < 60, "7: 10 min after the next feed")
            }
        } else {
            failures.append("7: no diaper prediction")
        }
        return failures
    }

    /// Feeds every `day` in the day and every `night` at night, for `days` days up to `now`.
    private static func sampleFeeds(
        until now: Date,
        days: Double,
        day: TimeInterval,
        night: TimeInterval,
        nightHours: Coverage.NightHours,
        calendar: Calendar
    ) -> [CareLog.Feed] {
        var feeds: [CareLog.Feed] = []
        var time = now.addingTimeInterval(-days * 86_400)
        while time <= now {
            feeds.append(CareLog.Feed(start: time, end: time))
            time = time.addingTimeInterval(nightHours.isNight(time, calendar: calendar) ? night : day)
        }
        return feeds
    }
}
#endif
