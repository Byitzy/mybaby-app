import AppIntents
import SwiftUI
import WidgetKit

/// Home Screen widget: time since the last feed and diaper, asleep or awake, and who's on night duty.
/// The medium and large sizes add buttons, which log for the widget's baby.
///
/// Each widget is set up in Edit Widget (`StatusWidgetIntent`): the baby (or "Follow the app"), the
/// details in order, and the buttons. The defaults are the widget as it was before.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.status, intent: StatusWidgetIntent.self, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baby at a glance")
        .description("Time since the last feed and diaper, and how long baby has been asleep or awake. Touch and hold, then Edit Widget, to pick the baby, the details and the buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Which of the details and buttons picked in Edit Widget a widget size has room for.
struct StatusLayout {
    /// Who's on night duty shows at the top during a night shift, instead of the baby's name.
    let showsOnDuty: Bool
    /// A line each, in the order picked, without repeats, as many as fit.
    let rows: [WidgetStat]
    /// None on the small widget.
    let buttons: [WidgetButton]

    static let maxButtons = 4

    init(family: WidgetFamily, stats: [WidgetStat], buttons: [WidgetButton]) {
        showsOnDuty = stats.contains(.onDuty)
        var seenStats = Set<WidgetStat>()
        let lines = stats.filter { $0 != .onDuty && seenStats.insert($0).inserted }
        rows = Array(lines.prefix(Self.maxRows(for: family)))
        var seenButtons = Set<WidgetButton>()
        let unique = buttons.filter { seenButtons.insert($0).inserted }
        self.buttons = family == .systemSmall ? [] : Array(unique.prefix(Self.maxButtons))
    }

    /// Small 3 (the last feed, diaper and sleep, as before), medium 4, large 6.
    static func maxRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 6
        }
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        content
            // A widget's size is fixed, so very large text would be cut off; it grows up to here.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            let baby = snapshot.baby(entry.babyID)
            let layout = StatusLayout(family: family, stats: entry.stats, buttons: entry.buttons)
            if family == .systemLarge {
                VStack(alignment: .leading, spacing: 12) {
                    StatusRows(snapshot: snapshot, baby: baby, layout: layout, date: entry.date, isLarge: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if !layout.buttons.isEmpty {
                        WidgetButtons(snapshot: snapshot, baby: baby, buttons: layout.buttons, date: entry.date, inRow: true)
                    }
                }
            } else if family == .systemMedium && !layout.buttons.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    StatusRows(snapshot: snapshot, baby: baby, layout: layout, date: entry.date)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WidgetButtons(snapshot: snapshot, baby: baby, buttons: layout.buttons, date: entry.date)
                        .frame(width: 104)
                }
            } else {
                StatusRows(snapshot: snapshot, baby: baby, layout: layout, date: entry.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            NoBabyView()
        }
    }
}

/// The baby's name or who's on night duty, then a line for each detail.
private struct StatusRows: View {
    let snapshot: WidgetSnapshot
    let baby: WidgetSnapshot.BabySnapshot
    let layout: StatusLayout
    let date: Date
    var isLarge = false

    /// With 4 lines on a medium widget there's no room for the feed's second line.
    private var showsFeedDetail: Bool { isLarge || layout.rows.count <= 3 }

    /// With twins, the name stays at the top during a night shift too, so widgets side by side can be told apart.
    private var namesBaby: Bool { snapshot.babyCount > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 6) {
            header
            ForEach(layout.rows, id: \.self) { stat in
                row(stat)
            }
        }
        .font(isLarge ? Font.body : Font.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var header: some View {
        if layout.showsOnDuty, let shift = snapshot.shift(at: date) {
            // The name says who; the dot only matches their color in the app.
            HStack(spacing: 4) {
                Circle()
                    .fill(shift.color)
                    .frame(width: 6, height: 6)
                Text(dutyText(shift))
                    .foregroundStyle(.primary)
            }
            .font(.caption.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(dutyVoiceOver(shift))
        } else {
            Text(baby.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "🌙 Sam on duty", or "Emma · 🌙 Sam" with twins.
    private func dutyText(_ shift: WidgetSnapshot.Shift) -> String {
        namesBaby ? "\(baby.name) · 🌙 \(shift.parentName)" : "🌙 \(shift.parentName) on duty"
    }

    private func dutyVoiceOver(_ shift: WidgetSnapshot.Shift) -> String {
        namesBaby ? "\(baby.name). \(shift.parentName) is on night duty" : "\(shift.parentName) is on night duty"
    }

    @ViewBuilder
    private func row(_ stat: WidgetStat) -> some View {
        switch stat {
        case .lastFeed: feedRow
        case .lastDiaper: diaperRow
        case .sleep: sleepRow
        case .onDuty: EmptyView() // In the header.
        case .nextDose: doseRow
        case .lastPumping: pumpingRow
        case .stashTotal: stashRow
        case .feedsToday: countRow(emoji: "🍼", count: baby.feeds(on: date), thing: "feed")
        case .diapersToday: countRow(emoji: "🧷", count: baby.diapers(on: date), thing: "diaper")
        }
    }

    @ViewBuilder
    private var feedRow: some View {
        if let timer = snapshot.timer(for: baby) {
            StatusLine(emoji: "🤱", label: "Breastfeeding, \(timer.side.title) side") {
                Text("\(timer.side.title) ") + timerText(timer)
            }
        } else if let feed = baby.lastFeed {
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(emoji: feed.emoji, label: "Last feed") {
                    Text(feed.date, style: .relative) + Text(" ago")
                }
                if showsFeedDetail {
                    Text(feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)")
                        .font(isLarge ? Font.caption : Font.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
                // Only the large widget has room for a third line.
                if isLarge, let next = baby.nextFeedExpected, next > date {
                    (Text("Next feed around ") + Text(next, style: .time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
            // "Last feed, 2 hours, 10 minutes ago, Formula · 120 ml" in one stop.
            .accessibilityElement(children: .combine)
        } else {
            StatusLine(emoji: "🍼", label: "Last feed") { Text("No feed yet") }
        }
    }

    @ViewBuilder
    private var diaperRow: some View {
        if let diaper = baby.lastDiaper {
            StatusLine(emoji: diaper.emoji, label: "Last diaper") {
                Text(diaper.date, style: .relative) + Text(" ago")
            }
        } else {
            StatusLine(emoji: "🧷", label: "Last diaper") { Text("No diaper yet") }
        }
    }

    @ViewBuilder
    private var sleepRow: some View {
        if let start = baby.sleepStart {
            StatusLine(emoji: "😴", label: "Sleeping for") {
                Text("Sleeping ") + Text(start, style: .relative)
            }
        } else if let wake = baby.lastWake {
            StatusLine(emoji: "🌤️", label: "Awake for") {
                Text("Awake ") + Text(wake, style: .relative)
            }
        } else {
            StatusLine(emoji: "😴", label: "Sleep") { Text("No sleep yet") }
        }
    }

    /// The medicine whose next dose is allowed soonest, from the dose timing the parent entered, in the
    /// app's words. It never suggests giving one.
    @ViewBuilder
    private var doseRow: some View {
        if let dose = baby.nextDose {
            if let next = dose.date, next > date {
                StatusLine(emoji: "💊", label: nil) {
                    Text("Next \(dose.name) ") + timeText(next)
                }
                .accessibilityLabel(Text("Next \(dose.name) dose allowed at ") + timeText(next))
            } else {
                StatusLine(emoji: "💊", label: nil) { Text("\(dose.name) OK to give now") }
                    .accessibilityLabel("\(dose.name): the dose timing you entered allows the next dose now")
            }
        } else {
            StatusLine(emoji: "💊", label: "Medicine") { Text("No dose timing set") }
        }
    }

    @ViewBuilder
    private var pumpingRow: some View {
        if let pumping = baby.lastPumping {
            StatusLine(emoji: "🫙", label: "Last pumping") {
                Text(pumping.date, style: .relative)
                    + Text(pumping.amountText.isEmpty ? " ago" : " ago · " + pumping.amountText)
            }
        } else {
            StatusLine(emoji: "🫙", label: "Last pumping") { Text("No pumping yet") }
        }
    }

    @ViewBuilder
    private var stashRow: some View {
        if let stash = baby.stash {
            StatusLine(emoji: "🧊", label: "Milk stash") { Text(stashText(stash)) }
        } else {
            StatusLine(emoji: "🧊", label: "Milk stash") { Text("Stash is empty") }
        }
    }

    /// "5 feeds today", "1 diaper today".
    private func countRow(emoji: String, count: Int, thing: String) -> some View {
        let text = count == 1 ? "1 \(thing) today" : "\(count) \(thing)s today"
        return StatusLine(emoji: emoji, label: nil) {
            Text(text)
        }
    }

    /// "840 ml in the stash", or "3 bags in the stash" when no bag has an amount.
    private func stashText(_ stash: WidgetSnapshot.BabySnapshot.Stash) -> String {
        if !stash.totalText.isEmpty { return "\(stash.totalText) in the stash" }
        return stash.bagCount == 1 ? "1 bag in the stash" : "\(stash.bagCount) bags in the stash"
    }

    /// "4:10 AM", or "Tue 4:10 AM" when it's not today.
    private func timeText(_ next: Date) -> Text {
        if Calendar.current.isDate(next, inSameDayAs: date) {
            return Text(next, style: .time)
        }
        return Text(next, format: .dateTime.weekday(.abbreviated).hour().minute())
    }

    /// The breastfeeding clock as a `Text`, so it can be joined to a label.
    private func timerText(_ timer: FeedingTimerState) -> Text {
        if let start = timer.timerStart(for: timer.side) {
            return Text(start, style: .timer)
        }
        return Text("\(FeedingTimerState.clock(timer.seconds(on: timer.side))) paused")
    }
}

/// An emoji and a value. VoiceOver reads `label` instead of the emoji's name, then the value; with no
/// `label` (when the value says it all) it skips the emoji.
private struct StatusLine<Value: View>: View {
    let emoji: String
    let label: String?
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .frame(width: 20)
                .accessibilityLabel(label ?? "")
                .accessibilityHidden(label == nil)
            value()
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// The buttons picked in Edit Widget: a column beside the details (medium) or a row under them (large).
/// They run in the app (see Shared/ButtonIntents.swift) and log for the baby the widget shows.
private struct WidgetButtons: View {
    let snapshot: WidgetSnapshot
    let baby: WidgetSnapshot.BabySnapshot
    let buttons: [WidgetButton]
    let date: Date
    var inRow = false

    var body: some View {
        Group {
            if inRow {
                HStack(spacing: 8) { items }
            } else {
                // Four buttons fit the medium widget's height only at the small size.
                VStack(spacing: buttons.count > 3 ? 4 : 6) { items }
                    .controlSize(buttons.count > 3 ? .small : .regular)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    private var items: some View {
        ForEach(buttons, id: \.self) { button in
            WidgetButtonView(kind: button, snapshot: snapshot, baby: baby, date: date, stacked: inRow)
        }
    }
}

private struct WidgetButtonView: View {
    let kind: WidgetButton
    let snapshot: WidgetSnapshot
    let baby: WidgetSnapshot.BabySnapshot
    let date: Date
    /// Emoji over the title, for the large widget's row.
    let stacked: Bool

    /// The baby whose details are on the widget, so a tap always logs for them.
    private var babyID: String? { baby.id.isEmpty ? nil : baby.id }

    /// " for Emma" with twins, so VoiceOver says whose log it goes to.
    private var forBaby: String { snapshot.babyCount > 1 ? " for \(baby.name)" : "" }

    /// "Emma" with twins, "Baby" otherwise.
    private var babyWord: String { snapshot.babyCount > 1 ? baby.name : "Baby" }

    var body: some View {
        switch kind {
        case .wet:
            Button(intent: LogDiaperButtonIntent(choice: .wet, babyID: babyID)) {
                ButtonLabel(emoji: "💧", title: "Wet", stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel("Log a wet diaper\(forBaby)")
        case .dirty:
            Button(intent: LogDiaperButtonIntent(choice: .dirty, babyID: babyID)) {
                ButtonLabel(emoji: "💩", title: "Dirty", stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel("Log a dirty diaper\(forBaby)")
        case .both:
            Button(intent: LogDiaperButtonIntent(choice: .both, babyID: babyID)) {
                ButtonLabel(emoji: "🧷", title: "Both", stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel("Log a wet and dirty diaper\(forBaby)")
        case .sleepToggle:
            if baby.isSleeping {
                Button(intent: SleepButtonIntent(start: false, sleepID: baby.sleepID, babyID: babyID)) {
                    ButtonLabel(emoji: "🌤️", title: "Woke up", stacked: stacked)
                }
                .tint(.indigo)
                .accessibilityLabel("\(babyWord) woke up, stop the sleep timer")
            } else {
                Button(intent: SleepButtonIntent(start: true, babyID: babyID)) {
                    ButtonLabel(emoji: "😴", title: "Sleep", stacked: stacked)
                }
                .tint(.indigo)
                .accessibilityLabel("Start the sleep timer\(forBaby)")
            }
        case .bottle:
            if let bottle = baby.usualBottle {
                Button(intent: LogBottleButtonIntent(formula: bottle.isFormula, amountML: bottle.ml, babyID: babyID)) {
                    ButtonLabel(emoji: "🍼", title: bottle.amountText.isEmpty ? "Bottle" : bottle.amountText, stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel(bottleVoiceOver(bottle))
            } else {
                InactiveButton(emoji: "🍼", title: "Bottle", stacked: stacked)
                    .accessibilityLabel("Bottle. Log a first bottle in MyBaby, then this button logs the same again.")
            }
        case .breastfeed:
            if let timer = snapshot.timer(for: baby) {
                Button(intent: SwitchFeedingSideIntent()) {
                    ButtonLabel(emoji: "🔁", title: "Switch", stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel("Switch breastfeeding to the \(timer.side.other.title.lowercased()) side")
            } else if let timer = snapshot.feedingTimer {
                // There's one timer, and it's going for the other baby.
                InactiveButton(emoji: "🤱", title: timer.babyName, stacked: stacked)
                    .accessibilityLabel("The breastfeeding timer is going for \(timer.babyName)")
            } else {
                Button(intent: StartBreastfeedingButtonIntent(babyID: babyID)) {
                    ButtonLabel(emoji: "🤱", title: "Breastfeed", stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel("Start the breastfeeding timer\(forBaby)")
            }
        case .medicine:
            if let medicine = baby.lastMedicine, !medicine.name.isEmpty {
                if let next = medicine.nextAllowed, next > date {
                    // Not a button while the dose timing entered doesn't allow a dose: tapping opens the app.
                    let time = WidgetFormat.time(next, now: date)
                    InactiveButton(emoji: "💊", title: time, stacked: stacked)
                        .accessibilityLabel("Next \(medicine.name) dose allowed at \(time)")
                } else {
                    Button(intent: LogMedicineButtonIntent(name: medicine.name, babyID: babyID)) {
                        ButtonLabel(emoji: "💊", title: medicine.name, detail: medicine.dosage, stacked: stacked)
                    }
                    .tint(.orange)
                    .accessibilityLabel(medicineVoiceOver(medicine))
                }
            } else {
                InactiveButton(emoji: "💊", title: "Medicine", stacked: stacked)
                    .accessibilityLabel("Medicine. Log a medicine in MyBaby, then this button logs it again with the same dose.")
            }
        }
    }

    /// "Log a bottle of formula, 120 ml".
    private func bottleVoiceOver(_ bottle: WidgetSnapshot.BabySnapshot.Bottle) -> String {
        let what = bottle.isFormula ? "formula" : "breast milk"
        let amount = bottle.amountText.isEmpty ? "" : ", \(bottle.amountText)"
        return "Log a bottle of \(what)\(amount)\(forBaby)"
    }

    /// "Log Tylenol, 2.5 ml".
    private func medicineVoiceOver(_ medicine: WidgetSnapshot.BabySnapshot.Medicine) -> String {
        let dose = medicine.dosage.isEmpty ? "" : ", \(medicine.dosage)"
        return "Log \(medicine.name)\(dose)\(forBaby)"
    }
}

private struct ButtonLabel: View {
    let emoji: String
    let title: String
    /// A second line under the title, for the large widget's row only (e.g. the medicine's dose).
    var detail = ""
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                VStack(spacing: 2) {
                    Text(emoji)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Text(emoji)
                        .accessibilityHidden(true)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Looks like a button but isn't one, for a button that can't log anything yet. Tapping it opens the
/// app, like the rest of the widget.
private struct InactiveButton: View {
    let emoji: String
    let title: String
    var stacked = false

    var body: some View {
        ButtonLabel(emoji: emoji, title: title, stacked: stacked)
            .foregroundStyle(.secondary)
            .padding(.vertical, stacked ? 8 : 6)
            .padding(.horizontal, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
    }
}
