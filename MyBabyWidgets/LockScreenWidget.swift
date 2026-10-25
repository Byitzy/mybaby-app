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
            Text("\(glance.emoji) \(glance.line)")
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
            return Glance(emoji: emoji(for: stat), short: "—", line: "Open MyBaby", voiceOver: "Open MyBaby to add your baby")
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
            glance = Glance(
                emoji: "🤱",
                short: WidgetFormat.short(seconds),
                line: "Feeding \(WidgetFormat.short(seconds)) · \(timer.side.title)",
                voiceOver: "Breastfeeding for \(WidgetFormat.spoken(seconds)), \(timer.side.title) side"
            )
        } else if let feed = baby.lastFeed {
            let seconds = now.timeIntervalSince(feed.date)
            glance = Glance(
                emoji: "🍼",
                short: seconds < 60 ? "Now" : WidgetFormat.short(seconds),
                line: WidgetFormat.ago(feed.date, now: now),
                voiceOver: seconds < 60
                    ? "Last feed just now, \(feed.shortTitle)"
                    : "Last feed \(WidgetFormat.spoken(seconds)) ago, \(feed.shortTitle)"
            )
            glance.details.append(Glance.Detail(
                text: feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)",
                isSecondary: true
            ))
        } else {
            glance = Glance(emoji: "🍼", short: "—", line: "No feed yet", voiceOver: "No feed logged yet")
        }
        if let diaper = baby.lastDiaper {
            glance.details.append(Glance.Detail(
                text: "\(diaper.emoji) \(WidgetFormat.ago(diaper.date, now: now)) · \(diaper.title)",
                voiceOver: "Last diaper \(WidgetFormat.spoken(now.timeIntervalSince(diaper.date))) ago, \(diaper.title)"
            ))
        }
        if let start = baby.sleepStart {
            glance.details.append(Glance.Detail(
                text: "😴 Sleeping \(WidgetFormat.short(now.timeIntervalSince(start)))",
                voiceOver: "Sleeping for \(WidgetFormat.spoken(now.timeIntervalSince(start)))"
            ))
        }
        return glance
    }

    private func diaper(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        guard let diaper = baby.lastDiaper else {
            return Glance(emoji: "🧷", short: "—", line: "No diaper yet", voiceOver: "No diaper logged yet")
        }
        let seconds = now.timeIntervalSince(diaper.date)
        let count = baby.diapers(on: now)
        return Glance(
            emoji: diaper.emoji,
            short: seconds < 60 ? "Now" : WidgetFormat.short(seconds),
            line: "\(WidgetFormat.ago(diaper.date, now: now)) · \(diaper.title)",
            details: [Glance.Detail(text: count == 1 ? "1 diaper today" : "\(count) diapers today", isSecondary: true)],
            voiceOver: seconds < 60
                ? "Last diaper just now, \(diaper.title)"
                : "Last diaper \(WidgetFormat.spoken(seconds)) ago, \(diaper.title)"
        )
    }

    private func sleep(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        if let start = baby.sleepStart {
            let seconds = now.timeIntervalSince(start)
            return Glance(
                emoji: "😴",
                short: WidgetFormat.short(seconds),
                line: "Sleeping \(WidgetFormat.short(seconds))",
                details: [Glance.Detail(text: "Since \(WidgetFormat.time(start, now: now))", isSecondary: true)],
                voiceOver: "Sleeping for \(WidgetFormat.spoken(seconds))"
            )
        }
        if let wake = baby.lastWake {
            let seconds = now.timeIntervalSince(wake)
            return Glance(
                emoji: "🌤️",
                short: WidgetFormat.short(seconds),
                line: "Awake \(WidgetFormat.short(seconds))",
                details: [Glance.Detail(text: "Woke up at \(WidgetFormat.time(wake, now: now))", isSecondary: true)],
                voiceOver: "Awake for \(WidgetFormat.spoken(seconds))"
            )
        }
        return Glance(emoji: "😴", short: "—", line: "No sleep yet", voiceOver: "No sleep logged yet")
    }

    /// When the dose timing the parent entered allows the next dose, in the app's words.
    private func dose(_ baby: WidgetSnapshot.BabySnapshot) -> Glance {
        guard let dose = baby.nextDose else {
            return Glance(emoji: "💊", short: "—", line: "No dose timing set", voiceOver: "No medicine dose timing set")
        }
        if let next = dose.date, next > now {
            let time = WidgetFormat.time(next, now: now)
            let wait = next.timeIntervalSince(now)
            return Glance(
                emoji: "💊",
                short: WidgetFormat.short(wait),
                line: "\(dose.name) at \(time)",
                details: [Glance.Detail(text: "Next dose allowed in \(WidgetFormat.short(wait))", isSecondary: true)],
                voiceOver: "Next \(dose.name) dose allowed at \(time), in \(WidgetFormat.spoken(wait))"
            )
        }
        return Glance(
            emoji: "💊",
            short: "OK",
            line: "\(dose.name) OK to give now",
            details: [Glance.Detail(text: "From the dose timing you entered", isSecondary: true)],
            voiceOver: "\(dose.name): the dose timing you entered allows the next dose now"
        )
    }

    private func onDuty(_ snapshot: WidgetSnapshot) -> Glance {
        if let shift = snapshot.shift(at: now) {
            let until = WidgetFormat.time(shift.end, now: now)
            var details = [Glance.Detail(text: "Until \(until)", isSecondary: true)]
            if let next = snapshot.shifts.first(where: { $0.start >= shift.end }) {
                details.append(Glance.Detail(text: "Then \(next.parentName)"))
            }
            return Glance(
                emoji: "🌙",
                short: shift.parentName,
                line: "\(shift.parentName) on duty",
                details: details,
                voiceOver: "\(shift.parentName) is on night duty until \(until)"
            )
        }
        if let next = snapshot.shifts.first(where: { $0.start > now }) {
            let from = WidgetFormat.time(next.start, now: now)
            return Glance(
                emoji: "🌙",
                short: "Off",
                line: "\(next.parentName) from \(from)",
                details: [Glance.Detail(text: "Next night shift", isSecondary: true)],
                voiceOver: "Next night shift: \(next.parentName) from \(from)"
            )
        }
        return Glance(emoji: "🌙", short: "—", line: "Night shifts off", voiceOver: "Night shifts are off")
    }
}
