import AppIntents
import SwiftUI
import WidgetKit

/// The watch face complications (circular, rectangular, inline and corner): one detail, for the baby
/// shown on the iPhone or one picked in the face editor (`ComplicationIntent`). Left as they are, they
/// look as they always did: the time since the last feed (circular, inline), and the last feed and
/// diaper (rectangular).
///
/// They read the `WatchContext` the watch app keeps in its App Group (Shared/WatchContext.swift), which
/// has every baby's part (`WidgetSnapshot.babies`), so they keep working from the last summary while
/// the iPhone is out of reach. The watch app reloads them whenever a new one arrives from the iPhone or
/// after a tap. Tapping one opens the app.
@main
struct MyBabyWatchWidgets: WidgetBundle {
    var body: some Widget {
        LastFeedComplication()
    }
}

/// The kind is the one the first, fixed complication had, so ones already on a watch face keep their
/// place and show the defaults: the baby shown on the iPhone, and the last feed.
struct LastFeedComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MyBabyWatchLastFeed", intent: ComplicationIntent.self, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Baby at a glance")
        .description("The last feed and diaper, sleep, the next medicine dose or who's on night duty, for the baby shown on your iPhone or one you pick.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    let date: Date
    /// `nil` before the watch has heard from the iPhone, or before a baby was added.
    let snapshot: WidgetSnapshot?
    /// The baby picked in the face editor (`Baby.uuid`), or `nil` to follow the iPhone.
    var babyID: String? = nil
    var stat: ComplicationStat = .lastFeed

    /// The baby to show: the one picked, or the one shown on the iPhone (also when the one picked isn't
    /// in the summary any more). `nil` without a snapshot.
    var baby: WidgetSnapshot.BabySnapshot? { snapshot?.baby(babyID) }
}

/// Entries every 5 minutes for the next 4 hours, so "2h 10m" moves on without the app, plus each
/// night-shift handoff, when a medicine's next dose is allowed, and midnight.
struct ComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .complicationExample)
    }

    func snapshot(for configuration: ComplicationIntent, in context: Context) async -> ComplicationEntry {
        let snapshot = WatchContext.load()?.snapshot ?? (context.isPreview ? .complicationExample : nil)
        return entry(at: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: ComplicationIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        let now = Date.now
        let snapshot = WatchContext.load()?.snapshot
        let horizon = now.addingTimeInterval(4 * 3600)
        var dates = Set((1...48).map { now.addingTimeInterval(Double($0) * 5 * 60) })
        if let snapshot {
            var boundaries = snapshot.shifts.flatMap { [$0.start, $0.end] }
            if let next = snapshot.baby(configuration.baby?.babyID).nextDose?.date {
                boundaries.append(next)
            }
            let calendar = Calendar.current
            if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                boundaries.append(midnight)
            }
            for boundary in boundaries where boundary > now && boundary < horizon {
                dates.insert(boundary)
            }
        }
        let entries = ([now] + dates.sorted()).map { date in
            entry(at: date, snapshot: snapshot, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The face editor's list: every detail for the baby shown on the iPhone, the last feed first (the
    /// complication as it always was), then the last feed for each baby by name. With twins or
    /// siblings, also each one's last diaper and sleep, so two complications side by side can show one
    /// baby each.
    func recommendations() -> [AppIntentRecommendation<ComplicationIntent>] {
        var list = ComplicationStat.allCases.map { stat in
            recommendation(baby: .followApp, stat: stat, description: stat.title)
        }
        let babies = WatchContext.load()?.snapshot?.watchBabies ?? []
        let stats: [ComplicationStat] = babies.count > 1 ? [.lastFeed, .lastDiaper, .sleep] : [.lastFeed]
        for baby in babies {
            let entity = BabyEntity(id: baby.id, name: baby.name)
            for stat in stats {
                list.append(recommendation(baby: entity, stat: stat, description: stat.editorTitle(babyName: baby.name)))
            }
        }
        return list
    }

    private func recommendation(baby: BabyEntity, stat: ComplicationStat, description: String) -> AppIntentRecommendation<ComplicationIntent> {
        AppIntentRecommendation(intent: ComplicationIntent(baby: baby, stat: stat), description: description)
    }

    private func entry(at date: Date, snapshot: WidgetSnapshot?, configuration: ComplicationIntent) -> ComplicationEntry {
        ComplicationEntry(
            date: date,
            snapshot: snapshot,
            babyID: configuration.baby?.babyID,
            stat: configuration.stat
        )
    }
}

extension WidgetSnapshot {
    /// Sample data for the watch face editor.
    static var complicationExample: WidgetSnapshot {
        let now = Date.now
        var snapshot = WidgetSnapshot(babyName: String(localized: "Baby", comment: "A baby without a name"))
        snapshot.lastFeed = Feed(
            date: now.addingTimeInterval(-(2 * 3600 + 10 * 60)),
            title: String(localized: "Bottle (formula)"),
            shortTitle: String(localized: "Formula", comment: "A bottle of formula, short"),
            emoji: "🍼",
            detail: String(localized: "\(120) ml", comment: "An amount in milliliters")
        )
        snapshot.lastDiaper = Diaper(
            date: now.addingTimeInterval(-45 * 60),
            title: String(localized: "Pee", comment: "A wet diaper, short"),
            emoji: "💧"
        )
        snapshot.lastWake = now.addingTimeInterval(-65 * 60)
        return snapshot
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) var family

    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    private var glance: ComplicationGlance {
        ComplicationGlance.make(for: entry)
    }

    /// With twins, and a baby picked in the face editor: the name, so complications side by side can be
    /// told apart.
    private var nameTag: String? {
        guard let snapshot = entry.snapshot, let baby = entry.baby, entry.babyID != nil, snapshot.babyCount > 1
        else { return nil }
        return baby.name
    }

    private var voiceOver: String {
        let glance = self.glance
        guard let nameTag else { return glance.voiceOver }
        return "\(nameTag): \(glance.voiceOver)"
    }

    /// "🍼" over "2h 10m".
    private var circular: some View {
        let glance = self.glance
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(glance.emoji)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(glance.short)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOver)
    }

    /// "🍼 2h 10m ago".
    private var inline: some View {
        let glance = self.glance
        let text = nameTag.map { "\(glance.emoji) \($0) · \(glance.line)" } ?? "\(glance.emoji) \(glance.line)"
        return Text(text)
            .accessibilityLabel(voiceOver)
    }

    /// The emoji in the corner, with "2h 10m ago" along the edge.
    private var corner: some View {
        let glance = self.glance
        let label = nameTag.map { "\($0) · \(glance.corner)" } ?? glance.corner
        return Text(glance.emoji)
            .font(.title3)
            .widgetLabel {
                Text(label)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOver)
    }

    /// The detail, with a few lines under it: for the last feed, as before, its type, the last diaper,
    /// and the sleep going on.
    private var rectangular: some View {
        let glance = self.glance
        var details = glance.details
        if let nameTag {
            if let first = details.first, first.isSecondary {
                details[0].text = "\(nameTag) · \(first.text)"
            } else {
                details.insert(ComplicationGlance.Detail(text: nameTag, isSecondary: true), at: 0)
            }
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "\(glance.emoji) \(glance.line)")
                .font(.headline)
                .accessibilityLabel(voiceOver)
            ForEach(Array(details.prefix(3).enumerated()), id: \.offset) { _, detail in
                Text(detail.text)
                    .foregroundStyle(detail.isSecondary ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    .accessibilityLabel(detail.voiceOver ?? detail.text)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One stop for VoiceOver, reading each line's label in turn.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - What it shows

/// What a complication shows, worked out once for all four families. Like the iPhone's Lock Screen
/// widgets (`LockScreenGlance` in MyBabyWidgets), in the watch's words.
struct ComplicationGlance {
    struct Detail {
        var text: String
        var isSecondary = false
        /// What VoiceOver reads, when it's not the text itself.
        var voiceOver: String?
    }

    var emoji: String
    /// "2h 10m", for the circular complication.
    var short: String
    /// "2h 10m ago", after the emoji: the inline complication, and the rectangular one's first line.
    var line: String
    /// The rectangular complication's other lines.
    var details: [Detail] = []
    var voiceOver: String
    /// Along the edge of a corner complication, where there's little room. The `line` unless shorter
    /// words are needed.
    var cornerText: String?

    var corner: String { cornerText ?? line }

    static func make(for entry: ComplicationEntry) -> ComplicationGlance {
        let now = entry.date
        guard let snapshot = entry.snapshot else {
            return ComplicationGlance(
                emoji: emoji(for: entry.stat),
                short: "—",
                line: String(localized: "Open MyBaby", comment: "Complication: before there is anything to show"),
                voiceOver: String(localized: "Open MyBaby on your iPhone to connect", comment: "VoiceOver, Complication")
            )
        }
        let baby = snapshot.baby(entry.babyID)
        switch entry.stat {
        case .lastFeed: return feed(snapshot, baby, now: now)
        case .lastDiaper: return diaper(baby, now: now)
        case .sleep: return sleep(baby, now: now)
        case .nextDose: return dose(baby, now: now)
        case .onDuty: return onDuty(snapshot, now: now)
        }
    }

    private static func emoji(for stat: ComplicationStat) -> String {
        switch stat {
        case .lastFeed: return "🍼"
        case .lastDiaper: return "🧷"
        case .sleep: return "😴"
        case .nextDose: return "💊"
        case .onDuty: return "🌙"
        }
    }

    // MARK: Details

    /// As the complication always showed it: the time since the last feed, or the breastfeeding timer,
    /// then the feed's type, the last diaper and the sleep going on.
    private static func feed(_ snapshot: WidgetSnapshot, _ baby: WidgetSnapshot.BabySnapshot, now: Date) -> ComplicationGlance {
        var glance: ComplicationGlance
        if let timer = snapshot.timer(for: baby) {
            let seconds = timer.totalSeconds(at: now)
            let short = ComplicationFormat.short(seconds)
            let spoken = ComplicationFormat.spoken(seconds)
            glance = ComplicationGlance(
                emoji: "🤱",
                short: ComplicationFormat.short(seconds),
                line: timer.side == .left
                    ? String(localized: "Feeding \(short) · Left", comment: "Complication: how long the breastfeeding timer has run, short, e.g. 12m, on the left side")
                    : String(localized: "Feeding \(short) · Right", comment: "Complication: how long the breastfeeding timer has run, short, e.g. 12m, on the right side"),
                voiceOver: timer.side == .left
                    ? String(localized: "Breastfeeding for \(spoken), left side", comment: "VoiceOver, Complication. How long, e.g. 12 minutes")
                    : String(localized: "Breastfeeding for \(spoken), right side", comment: "VoiceOver, Complication. How long, e.g. 12 minutes")
            )
        } else if let feed = baby.lastFeed {
            let seconds = now.timeIntervalSince(feed.date)
            glance = ComplicationGlance(
                emoji: "🍼",
                short: seconds < 60 ? String(localized: "Now", comment: "Complication, very short: it happened under a minute ago") : ComplicationFormat.short(seconds),
                line: ComplicationFormat.ago(feed.date, now: now),
                voiceOver: seconds < 60
                    ? String(localized: "Last feed just now, \(feed.shortTitle)", comment: "VoiceOver, Complication. What the feed was, e.g. Formula")
                    : String(localized: "Last feed \(ComplicationFormat.spoken(seconds)) ago, \(feed.shortTitle)", comment: "VoiceOver, Complication. First: how long ago; second: what the feed was, e.g. Formula")
            )
            glance.details.append(Detail(
                text: feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)",
                isSecondary: true
            ))
        } else {
            glance = ComplicationGlance(emoji: "🍼", short: "—", line: String(localized: "No feed yet", comment: "Complication, short"), voiceOver: String(localized: "No feed logged yet", comment: "VoiceOver, Complication"))
        }
        if let diaper = baby.lastDiaper {
            glance.details.append(Detail(
                text: "\(diaper.emoji) \(ComplicationFormat.ago(diaper.date, now: now)) · \(diaper.title)",
                voiceOver: String(localized: "Last diaper \(ComplicationFormat.spoken(now.timeIntervalSince(diaper.date))) ago, \(diaper.title)", comment: "VoiceOver, Complication. First: how long ago; second: what it was, e.g. Pee")
            ))
        }
        if let start = baby.sleepStart {
            glance.details.append(Detail(
                text: String(localized: "😴 Asleep \(ComplicationFormat.short(now.timeIntervalSince(start)))", comment: "Complication: how long the baby has been asleep, short, e.g. 1h 20m"),
                voiceOver: String(localized: "Asleep for \(ComplicationFormat.spoken(now.timeIntervalSince(start)))", comment: "VoiceOver, Complication. How long, e.g. 1 hour, 20 minutes")
            ))
        }
        return glance
    }

    private static func diaper(_ baby: WidgetSnapshot.BabySnapshot, now: Date) -> ComplicationGlance {
        guard let diaper = baby.lastDiaper else {
            return ComplicationGlance(emoji: "🧷", short: "—", line: String(localized: "No diaper yet", comment: "Complication, short"), voiceOver: String(localized: "No diaper logged yet", comment: "VoiceOver, Complication"))
        }
        let seconds = now.timeIntervalSince(diaper.date)
        var details: [Detail] = []
        // Only once the iPhone has counted today (not from an iPhone app older than per-baby counts).
        if Calendar.current.isDate(now, inSameDayAs: baby.countedDay) {
            let count = baby.diapers(on: now)
            details.append(Detail(text: String(localized: "\(count) diapers today", comment: "Complication: how many diapers were logged today"), isSecondary: true))
        }
        return ComplicationGlance(
            emoji: diaper.emoji,
            short: seconds < 60 ? String(localized: "Now", comment: "Complication, very short: it happened under a minute ago") : ComplicationFormat.short(seconds),
            line: "\(ComplicationFormat.ago(diaper.date, now: now)) · \(diaper.title)",
            details: details,
            voiceOver: seconds < 60
                ? String(localized: "Last diaper just now, \(diaper.title)", comment: "VoiceOver, Complication. What it was, e.g. Pee")
                : String(localized: "Last diaper \(ComplicationFormat.spoken(seconds)) ago, \(diaper.title)", comment: "VoiceOver, Complication. First: how long ago; second: what it was, e.g. Pee"),
            cornerText: ComplicationFormat.ago(diaper.date, now: now)
        )
    }

    private static func sleep(_ baby: WidgetSnapshot.BabySnapshot, now: Date) -> ComplicationGlance {
        if let start = baby.sleepStart {
            let seconds = now.timeIntervalSince(start)
            return ComplicationGlance(
                emoji: "😴",
                short: ComplicationFormat.short(seconds),
                line: String(localized: "Asleep \(ComplicationFormat.short(seconds))", comment: "Complication: how long the baby has been asleep, short, e.g. 1h 20m"),
                details: [Detail(text: String(localized: "Since \(ComplicationFormat.time(start, now: now))", comment: "Complication: when the sleep started, e.g. Since 9:10 PM"), isSecondary: true)],
                voiceOver: String(localized: "Asleep for \(ComplicationFormat.spoken(seconds))", comment: "VoiceOver, Complication. How long, e.g. 1 hour, 20 minutes")
            )
        }
        if let wake = baby.lastWake {
            let seconds = now.timeIntervalSince(wake)
            return ComplicationGlance(
                emoji: "🌤️",
                short: ComplicationFormat.short(seconds),
                line: String(localized: "Awake \(ComplicationFormat.short(seconds))", comment: "Complication: how long the baby has been awake, short, e.g. 1h 5m"),
                details: [Detail(text: String(localized: "Woke up at \(ComplicationFormat.time(wake, now: now))", comment: "Complication: when the last sleep ended, e.g. Woke up at 7:10 AM"), isSecondary: true)],
                voiceOver: String(localized: "Awake for \(ComplicationFormat.spoken(seconds))", comment: "VoiceOver, Complication. How long, e.g. 1 hour, 5 minutes")
            )
        }
        return ComplicationGlance(emoji: "😴", short: "—", line: String(localized: "No sleep yet", comment: "Complication, short"), voiceOver: String(localized: "No sleep logged yet", comment: "VoiceOver, Complication"))
    }

    /// When the dose timing the parent entered allows the next dose, in the app's words. It never
    /// suggests a dose.
    private static func dose(_ baby: WidgetSnapshot.BabySnapshot, now: Date) -> ComplicationGlance {
        guard let dose = baby.nextDose else {
            return ComplicationGlance(
                emoji: "💊",
                short: "—",
                line: String(localized: "No dose timing set", comment: "Complication, short"),
                voiceOver: String(localized: "No medicine dose timing set", comment: "VoiceOver, Complication")
            )
        }
        if let next = dose.date, next > now {
            let time = ComplicationFormat.time(next, now: now)
            let wait = next.timeIntervalSince(now)
            return ComplicationGlance(
                emoji: "💊",
                short: ComplicationFormat.short(wait),
                line: String(localized: "\(dose.name) at \(time)", comment: "Complication: when the next dose of a medicine is allowed. First: the medicine; second: a time"),
                details: [Detail(text: String(localized: "Next dose allowed in \(ComplicationFormat.short(wait))", comment: "Complication: how long until the next dose is allowed, short, e.g. 1h 20m"), isSecondary: true)],
                voiceOver: String(localized: "Next \(dose.name) dose allowed at \(time), in \(ComplicationFormat.spoken(wait))", comment: "VoiceOver, Complication. First: the medicine; second: a time; third: how long until then")
            )
        }
        return ComplicationGlance(
            emoji: "💊",
            short: String(localized: "OK", comment: "Complication, very short: the dose timing the parent entered allows the next dose now"),
            line: String(localized: "\(dose.name) OK to give now", comment: "Complication: The medicine"),
            details: [Detail(text: String(localized: "From the dose timing you entered", comment: "Complication, short"), isSecondary: true)],
            voiceOver: String(localized: "\(dose.name): the dose timing you entered allows the next dose now", comment: "VoiceOver, Complication. The medicine"),
            cornerText: String(localized: "\(dose.name) OK now", comment: "Complication: very short, along the edge of a corner complication. The medicine")
        )
    }

    private static func onDuty(_ snapshot: WidgetSnapshot, now: Date) -> ComplicationGlance {
        if let shift = snapshot.shift(at: now) {
            let until = ComplicationFormat.time(shift.end, now: now)
            var details = [Detail(text: String(localized: "Until \(until)", comment: "Complication: the end of the night shift going on, e.g. Until 2:00 AM"), isSecondary: true)]
            if let next = snapshot.shifts.first(where: { $0.start >= shift.end }) {
                details.append(Detail(text: String(localized: "Then \(next.parentName)", comment: "Complication: who is on night duty next. A parent's name")))
            }
            return ComplicationGlance(
                emoji: "🌙",
                short: shift.parentName,
                line: String(localized: "\(shift.parentName) on duty", comment: "Complication: who is on night duty now. A parent's name"),
                details: details,
                voiceOver: String(localized: "\(shift.parentName) is on night duty until \(until)", comment: "VoiceOver, Complication. First: a parent's name; second: a time")
            )
        }
        if let next = snapshot.shifts.first(where: { $0.start > now }) {
            let from = ComplicationFormat.time(next.start, now: now)
            return ComplicationGlance(
                emoji: "🌙",
                short: String(localized: "Off", comment: "Complication, very short: no parent is on night duty right now"),
                line: String(localized: "\(next.parentName) from \(from)", comment: "Complication: the next night shift. First: a parent's name; second: a time"),
                details: [Detail(text: String(localized: "Next night shift", comment: "Complication, short"), isSecondary: true)],
                voiceOver: String(localized: "Next night shift: \(next.parentName) from \(from)", comment: "VoiceOver, Complication. First: a parent's name; second: a time")
            )
        }
        return ComplicationGlance(emoji: "🌙", short: "—", line: String(localized: "Night shifts off", comment: "Complication, short"), voiceOver: String(localized: "Night shifts are off", comment: "VoiceOver, Complication"))
    }
}

// MARK: - Formatting

/// Like the iPhone widgets' `WidgetFormat`.
enum ComplicationFormat {
    /// "45m", "2h 10m", in the words of the watch's language ("2 h 10 min" in French). Whole minutes,
    /// rounded down.
    static func short(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        return shortFormatter.string(from: TimeInterval(totalMinutes * 60)) ?? "\(totalMinutes)"
    }

    private static let shortFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    /// "2h 10m ago", or "Just now".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return String(localized: "Just now", comment: "When something was logged, under a minute ago")
        }
        let duration = short(seconds)
        return String(localized: "\(duration) ago", comment: "How long ago something was logged, short, e.g. 2h 10m ago")
    }

    /// "4:10 AM", or "Tue 4:10 AM" when it's not the same day as `now`.
    static func time(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "2 hours, 10 minutes", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? short(seconds)
    }
}
