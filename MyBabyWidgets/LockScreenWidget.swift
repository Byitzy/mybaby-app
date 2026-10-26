import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen widgets: one detail, picked in Edit Widget (`LockScreenWidgetIntent`), for the baby picked
/// there. The default is as before: the time since the last feed (circular and inline), and the last
/// feed and diaper (rectangular).
///
/// The times come from the timeline's entry dates, a few minutes apart, which reads better in these
/// small spaces than a ticking `Text(_:style: .relative)`.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.lockScreen, intent: LockScreenWidgetIntent.self, provider: LockScreenProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Last feed")
        .description("How long ago baby last ate, and the last diaper. Tap it while customizing the Lock Screen to pick the baby and what it shows.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        content
            // Lock Screen widgets are small and fixed in size; text grows up to here.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var glance: Glance {
        LockScreenGlance(entry: entry).glance
    }

    /// With twins, and a baby picked in Edit Widget: the name, so widgets side by side can be told apart.
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

    /// Cry alerts listening on this iPhone at the entry's time, for a tiny mic beside the detail.
    private var listening: WidgetSnapshot.Listening? {
        entry.snapshot?.activeListening(at: entry.date)
    }

    /// `voiceOver`, then whether cry alerts are listening, for the sizes read as one label.
    private var voiceOverWithListening: String {
        guard let listening else { return voiceOver }
        return "\(voiceOver). \(ListeningBadge.voiceOver(listening))"
    }

    /// "🍼" over "2h 10m", with a tiny mic beside the emoji while cry alerts listen.
    private var circular: some View {
        let glance = self.glance
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Text(glance.emoji)
                        .font(.body)
                        .accessibilityHidden(true)
                    if let listening {
                        ListeningBadge(listening: listening, style: .glyph)
                    }
                }
                Text(glance.short)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverWithListening)
    }

    /// "🍼 2h 10m ago", after a mic while cry alerts listen. The inline widget is a single line of text,
    /// so the mic is a symbol in it, first, where it isn't cut off.
    private var inline: some View {
        let glance = self.glance
        let text = nameTag.map { "\(glance.emoji) \($0) · \(glance.line)" } ?? "\(glance.emoji) \(glance.line)"
        let line: Text
        if let listening {
            line = Text(Image(systemName: listening.isCrying ? "waveform" : "mic.fill")) + Text(verbatim: " \(text)")
        } else {
            line = Text(text)
        }
        return line
            .accessibilityLabel(voiceOverWithListening)
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
                details.insert(Glance.Detail(text: nameTag, isSecondary: true), at: 0)
            }
        }
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(verbatim: "\(glance.emoji) \(glance.line)")
                    .font(.headline)
                    .accessibilityLabel(voiceOver)
                // At the end of the first line, so the details below keep their lines.
                if let listening {
                    Spacer(minLength: 2)
                    ListeningBadge(listening: listening, style: .glyph)
                }
            }
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

/// What a Lock Screen widget shows, worked out once for all three sizes.
struct Glance {
    struct Detail {
        var text: String
        var isSecondary = false
        /// What VoiceOver reads, when it's not the text itself.
        var voiceOver: String?
    }

    var emoji: String
    /// "2h 10m", for the round widget.
    var short: String
    /// "2h 10m ago", after the emoji: the inline widget, and the rectangular one's first line.
    var line: String
    /// The rectangular widget's other lines.
    var details: [Detail] = []
    var voiceOver: String
}

/// The `Glance` for an entry's detail and baby.
private struct LockScreenGlance {
    let entry: SnapshotEntry

    private var now: Date { entry.date }

    var glance: Glance {
        let stat = entry.stats.first ?? .lastFeed
        guard let snapshot = entry.snapshot else {
            return Glance(emoji: emoji(for: stat), short: "—", line: String(localized: "Open MyBaby", comment: "Lock Screen widget: before there is anything to show"), voiceOver: String(localized: "Open MyBaby to add your baby", comment: "VoiceOver, Lock Screen widget"))
        }
        let baby = snapshot.baby(entry.babyID)
        switch stat {
        case .lastDiaper: return diaper(baby)
        case .sleep: return sleep(baby)
        case .nextDose: return dose(baby)
        case .onDuty: return onDuty(snapshot)
        default: return feed(snapshot, baby)
        }
    }

    private func emoji(for stat: WidgetStat) -> String {
        switch stat {
        case .lastDiaper: return "🧷"
        case .sleep: return "😴"
        case .nextDose: return "💊"
        case .onDuty: return "🌙"
        default: return "🍼"
        }
    }

    // MARK: Details

    /// As the widget always showed it: the time since the last feed, or the breastfeeding timer.
    private func feed(_ snapshot: WidgetSnapshot, _ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        var glance: Glance
        if let timer = snapshot.timer(for: baby) {
            let seconds = timer.totalSeconds(at: now)
            let short = WidgetFormat.short(seconds)
            let spoken = WidgetFormat.spoken(seconds)
            glance = Glance(
                emoji: "🤱",
                short: WidgetFormat.short(seconds),
                line: timer.side == .left
                    ? String(localized: "Feeding \(short) · Left", comment: "Lock Screen widget: how long the breastfeeding timer has run, short, e.g. 12m, on the left side")
                    : String(localized: "Feeding \(short) · Right", comment: "Lock Screen widget: how long the breastfeeding timer has run, short, e.g. 12m, on the right side"),
                voiceOver: timer.side == .left
                    ? String(localized: "Breastfeeding for \(spoken), left side", comment: "VoiceOver, Lock Screen widget. How long, e.g. 12 minutes")
                    : String(localized: "Breastfeeding for \(spoken), right side", comment: "VoiceOver, Lock Screen widget. How long, e.g. 12 minutes")
            )
        } else if let feed = baby.lastFeed {
            let seconds = now.timeIntervalSince(feed.date)
            glance = Glance(
                emoji: "🍼",
                short: seconds < 60 ? String(localized: "Now", comment: "Lock Screen widget, very short: it happened under a minute ago") : WidgetFormat.short(seconds),
                line: WidgetFormat.ago(feed.date, now: now),
                voiceOver: seconds < 60
                    ? String(localized: "Last feed just now, \(feed.shortTitle)", comment: "VoiceOver, Lock Screen widget. What the feed was, e.g. Formula")
                    : String(localized: "Last feed \(WidgetFormat.spoken(seconds)) ago, \(feed.shortTitle)", comment: "VoiceOver, Lock Screen widget. First: how long ago; second: what the feed was, e.g. Formula")
            )
            glance.details.append(Glance.Detail(
                text: feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)",
                isSecondary: true
            ))
        } else {
            glance = Glance(emoji: "🍼", short: "—", line: String(localized: "No feed yet", comment: "Lock Screen widget, short"), voiceOver: String(localized: "No feed logged yet", comment: "VoiceOver, Lock Screen widget"))
        }
        if let diaper = baby.lastDiaper {
            glance.details.append(Glance.Detail(
                text: "\(diaper.emoji) \(WidgetFormat.ago(diaper.date, now: now)) · \(diaper.title)",
                voiceOver: String(localized: "Last diaper \(WidgetFormat.spoken(now.timeIntervalSince(diaper.date))) ago, \(diaper.title)", comment: "VoiceOver, Lock Screen widget. First: how long ago; second: what it was, e.g. Pee")
            ))
        }
        if let start = baby.sleepStart {
            glance.details.append(Glance.Detail(
                text: String(localized: "😴 Sleeping \(WidgetFormat.short(now.timeIntervalSince(start)))", comment: "Lock Screen widget: how long the baby has been asleep, short, e.g. 1h 20m"),
                voiceOver: String(localized: "Sleeping for \(WidgetFormat.spoken(now.timeIntervalSince(start)))", comment: "VoiceOver, Lock Screen widget. How long, e.g. 1 hour, 20 minutes")
            ))
        }
        return glance
    }

    private func diaper(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        guard let diaper = baby.lastDiaper else {
            return Glance(emoji: "🧷", short: "—", line: String(localized: "No diaper yet", comment: "Lock Screen widget, short"), voiceOver: String(localized: "No diaper logged yet", comment: "VoiceOver, Lock Screen widget"))
        }
        let seconds = now.timeIntervalSince(diaper.date)
        let count = baby.diapers(on: now)
        return Glance(
            emoji: diaper.emoji,
            short: seconds < 60 ? String(localized: "Now", comment: "Lock Screen widget, very short: it happened under a minute ago") : WidgetFormat.short(seconds),
            line: "\(WidgetFormat.ago(diaper.date, now: now)) · \(diaper.title)",
            details: [Glance.Detail(text: String(localized: "\(count) diapers today", comment: "Lock Screen widget: how many diapers were logged today"), isSecondary: true)],
            voiceOver: seconds < 60
                ? String(localized: "Last diaper just now, \(diaper.title)", comment: "VoiceOver, Lock Screen widget. What it was, e.g. Pee")
                : String(localized: "Last diaper \(WidgetFormat.spoken(seconds)) ago, \(diaper.title)", comment: "VoiceOver, Lock Screen widget. First: how long ago; second: what it was, e.g. Pee")
        )
    }

    private func sleep(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        if let start = baby.sleepStart {
            let seconds = now.timeIntervalSince(start)
            return Glance(
                emoji: "😴",
                short: WidgetFormat.short(seconds),
                line: String(localized: "Sleeping \(WidgetFormat.short(seconds))", comment: "Lock Screen widget: how long the baby has been asleep, short, e.g. 1h 20m"),
                details: [Glance.Detail(text: String(localized: "Since \(WidgetFormat.time(start, now: now))", comment: "Lock Screen widget: when the sleep started, e.g. Since 9:10 PM"), isSecondary: true)],
                voiceOver: String(localized: "Sleeping for \(WidgetFormat.spoken(seconds))", comment: "VoiceOver, Lock Screen widget. How long, e.g. 1 hour, 20 minutes")
            )
        }
        if let wake = baby.lastWake {
            let seconds = now.timeIntervalSince(wake)
            return Glance(
                emoji: "🌤️",
                short: WidgetFormat.short(seconds),
                line: String(localized: "Awake \(WidgetFormat.short(seconds))", comment: "Lock Screen widget: how long the baby has been awake, short, e.g. 1h 5m"),
                details: [Glance.Detail(text: String(localized: "Woke up at \(WidgetFormat.time(wake, now: now))", comment: "Lock Screen widget: when the last sleep ended, e.g. Woke up at 7:10 AM"), isSecondary: true)],
                voiceOver: String(localized: "Awake for \(WidgetFormat.spoken(seconds))", comment: "VoiceOver, Lock Screen widget. How long, e.g. 1 hour, 5 minutes")
            )
        }
        return Glance(emoji: "😴", short: "—", line: String(localized: "No sleep yet", comment: "Lock Screen widget, short"), voiceOver: String(localized: "No sleep logged yet", comment: "VoiceOver, Lock Screen widget"))
    }

    /// When the dose timing the parent entered allows the next dose, in the app's words.
    private func dose(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        guard let dose = baby.nextDose else {
            return Glance(emoji: "💊", short: "—", line: String(localized: "No dose timing set", comment: "Lock Screen widget, short"), voiceOver: String(localized: "No medicine dose timing set", comment: "VoiceOver, Lock Screen widget"))
        }
        if let next = dose.date, next > now {
            let time = WidgetFormat.time(next, now: now)
            let wait = next.timeIntervalSince(now)
            return Glance(
                emoji: "💊",
                short: WidgetFormat.short(wait),
                line: String(localized: "\(dose.name) at \(time)", comment: "Lock Screen widget: when the next dose of a medicine is allowed. First: the medicine; second: a time"),
                details: [Glance.Detail(text: String(localized: "Next dose allowed in \(WidgetFormat.short(wait))", comment: "Lock Screen widget: how long until the next dose is allowed, short, e.g. 1h 20m"), isSecondary: true)],
                voiceOver: String(localized: "Next \(dose.name) dose allowed at \(time), in \(WidgetFormat.spoken(wait))", comment: "VoiceOver, Lock Screen widget. First: the medicine; second: a time; third: how long until then")
            )
        }
        return Glance(
            emoji: "💊",
            short: String(localized: "OK", comment: "Lock Screen widget, very short: the dose timing the parent entered allows the next dose now"),
            line: String(localized: "\(dose.name) OK to give now", comment: "Lock Screen widget: The medicine"),
            details: [Glance.Detail(text: String(localized: "From the dose timing you entered", comment: "Lock Screen widget, short"), isSecondary: true)],
            voiceOver: String(localized: "\(dose.name): the dose timing you entered allows the next dose now", comment: "VoiceOver, Lock Screen widget. The medicine")
        )
    }

    private func onDuty(_ snapshot: WidgetSnapshot) -> Glance {
        if let shift = snapshot.shift(at: now) {
            let until = WidgetFormat.time(shift.end, now: now)
            var details = [Glance.Detail(text: String(localized: "Until \(until)", comment: "Lock Screen widget: the end of the night shift going on, e.g. Until 2:00 AM"), isSecondary: true)]
            if let next = snapshot.shifts.first(where: { $0.start >= shift.end }) {
                details.append(Glance.Detail(text: String(localized: "Then \(next.parentName)", comment: "Lock Screen widget: who is on night duty next. A parent's name")))
            }
            return Glance(
                emoji: "🌙",
                short: shift.parentName,
                line: String(localized: "\(shift.parentName) on duty", comment: "Lock Screen widget: who is on night duty now. A parent's name"),
                details: details,
                voiceOver: String(localized: "\(shift.parentName) is on night duty until \(until)", comment: "VoiceOver, Lock Screen widget. First: a parent's name; second: a time")
            )
        }
        if let next = snapshot.shifts.first(where: { $0.start > now }) {
            let from = WidgetFormat.time(next.start, now: now)
            return Glance(
                emoji: "🌙",
                short: String(localized: "Off", comment: "Lock Screen widget, very short: no parent is on night duty right now"),
                line: String(localized: "\(next.parentName) from \(from)", comment: "Lock Screen widget: the next night shift. First: a parent's name; second: a time"),
                details: [Glance.Detail(text: String(localized: "Next night shift", comment: "Lock Screen widget, short"), isSecondary: true)],
                voiceOver: String(localized: "Next night shift: \(next.parentName) from \(from)", comment: "VoiceOver, Lock Screen widget. First: a parent's name; second: a time")
            )
        }
        return Glance(emoji: "🌙", short: "—", line: String(localized: "Night shifts off", comment: "Lock Screen widget, short"), voiceOver: String(localized: "Night shifts are off", comment: "VoiceOver, Lock Screen widget"))
    }
}
