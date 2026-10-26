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
    @Environment(\.widgetFamily) private var family

    /// With 4 lines on a medium widget there's no room for the feed's second line.
    private var showsFeedDetail: Bool { isLarge || layout.rows.count <= 3 }

    /// With twins, the name stays at the top during a night shift too, so widgets side by side can be told apart.
    private var namesBaby: Bool { snapshot.babyCount > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 6) {
            HStack(spacing: 4) {
                header
                // At the end of the top line, so it takes no line of its own. The small widget has room
                // for the mic only; VoiceOver reads the same either way.
                if let listening = snapshot.activeListening(at: date) {
                    Spacer(minLength: 4)
                    ListeningBadge(listening: listening, style: family == .systemSmall ? .compact : .full)
                }
            }
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
        namesBaby
            ? "\(baby.name) · 🌙 \(shift.parentName)"
            : String(localized: "🌙 \(shift.parentName) on duty", comment: "Widget: the parent on night duty now")
    }

    private func dutyVoiceOver(_ shift: WidgetSnapshot.Shift) -> String {
        namesBaby
            ? String(localized: "\(baby.name). \(shift.parentName) is on night duty", comment: "VoiceOver, widget. First: the baby's name; second: a parent's name")
            : String(localized: "\(shift.parentName) is on night duty", comment: "VoiceOver, widget. A parent's name")
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
        case .feedsToday:
            let count = baby.feeds(on: date)
            countRow(emoji: "🍼", text: String(localized: "\(count) feeds today", comment: "Widget: how many feeds were logged today"))
        case .diapersToday:
            let count = baby.diapers(on: date)
            countRow(emoji: "🧷", text: String(localized: "\(count) diapers today", comment: "Widget: how many diapers were logged today"))
        }
    }

    @ViewBuilder
    private var feedRow: some View {
        if let timer = snapshot.timer(for: baby) {
            StatusLine(emoji: "🤱", label: timer.side == .left ? "Breastfeeding, left side" : "Breastfeeding, right side") {
                Text(timer.side.title) + Text(verbatim: " ") + timerText(timer)
            }
        } else if let feed = baby.lastFeed {
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(emoji: feed.emoji, label: "Last feed") {
                    Text("\(feed.date, style: .relative) ago", comment: "Widget: a time that counts up, e.g. 2 hr, 10 min ago")
                }
                if showsFeedDetail {
                    Text(feed.detail.isEmpty ? feed.shortTitle : "\(feed.shortTitle) · \(feed.detail)")
                        .font(isLarge ? Font.caption : Font.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
                // Only the large widget has room for a third line.
                if isLarge, let next = baby.nextFeedExpected, next > date {
                    Text("Next feed around \(next, style: .time)")
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
                Text("\(diaper.date, style: .relative) ago", comment: "Widget: a time that counts up, e.g. 2 hr, 10 min ago")
            }
        } else {
            StatusLine(emoji: "🧷", label: "Last diaper") { Text("No diaper yet") }
        }
    }

    @ViewBuilder
    private var sleepRow: some View {
        if let start = baby.sleepStart {
            StatusLine(emoji: "😴", label: "Sleeping for") {
                Text("Sleeping \(start, style: .relative)", comment: "Widget: how long the baby has been asleep, counting up")
            }
        } else if let wake = baby.lastWake {
            StatusLine(emoji: "🌤️", label: "Awake for") {
                Text("Awake \(wake, style: .relative)", comment: "Widget: how long the baby has been awake, counting up")
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
                    Text("Next \(dose.name) \(timeText(next))", comment: "Widget: when the next dose of a medicine is allowed. First: the medicine; second: a time")
                }
                .accessibilityLabel(Text("Next \(dose.name) dose allowed at \(timeText(next))", comment: "VoiceOver, widget. First: the medicine; second: a time"))
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
                if pumping.amountText.isEmpty {
                    Text("\(pumping.date, style: .relative) ago", comment: "Widget: a time that counts up, e.g. 2 hr, 10 min ago")
                } else {
                    Text("\(pumping.date, style: .relative) ago · \(pumping.amountText)", comment: "Widget: the last pumping. First: a time that counts up; second: the amount, e.g. 150 ml")
                }
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
    private func countRow(emoji: String, text: String) -> some View {
        StatusLine(emoji: emoji, label: nil) {
            Text(text)
        }
    }

    /// "840 ml in the stash", or "3 bags in the stash" when no bag has an amount.
    private func stashText(_ stash: WidgetSnapshot.BabySnapshot.Stash) -> String {
        if !stash.totalText.isEmpty {
            return String(localized: "\(stash.totalText) in the stash", comment: "Widget: how much milk is in the milk stash, e.g. 840 ml")
        }
        let count = stash.bagCount
        return String(localized: "\(count) bags in the stash", comment: "Widget: how many bags of milk are in the milk stash")
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
        let clock = FeedingTimerState.clock(timer.seconds(on: timer.side))
        return Text("\(clock) paused", comment: "Widget: a paused breastfeeding clock, e.g. 4:05 paused")
    }
}

/// An emoji and a value. VoiceOver reads `label` instead of the emoji's name, then the value; with no
/// `label` (when the value says it all) it skips the emoji.
private struct StatusLine<Value: View>: View {
    let emoji: String
    let label: LocalizedStringKey?
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

    /// With twins, VoiceOver says whose log it goes to ("Log a wet diaper for Emma").
    private var namesBaby: Bool { snapshot.babyCount > 1 }

    /// `forBaby` with the baby's name with twins, or else `plain`: whole sentences, so each language can
    /// word them its own way.
    private func voiceOver(_ plain: String, forBaby: (String) -> String) -> String {
        namesBaby ? forBaby(baby.name) : plain
    }

    var body: some View {
        switch kind {
        case .wet:
            Button(intent: LogDiaperButtonIntent(choice: .wet, babyID: babyID)) {
                ButtonLabel(emoji: "💧", title: String(localized: "Wet", comment: "Widget button: log a wet diaper"), stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel(voiceOver(String(localized: "Log a wet diaper")) { String(localized: "Log a wet diaper for \($0)") })
        case .dirty:
            Button(intent: LogDiaperButtonIntent(choice: .dirty, babyID: babyID)) {
                ButtonLabel(emoji: "💩", title: String(localized: "Dirty", comment: "Widget button: log a dirty diaper"), stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel(voiceOver(String(localized: "Log a dirty diaper")) { String(localized: "Log a dirty diaper for \($0)") })
        case .both:
            Button(intent: LogDiaperButtonIntent(choice: .both, babyID: babyID)) {
                ButtonLabel(emoji: "🧷", title: String(localized: "Both", comment: "Widget button: log a wet and dirty diaper"), stacked: stacked)
            }
            .tint(.teal)
            .accessibilityLabel(voiceOver(String(localized: "Log a wet and dirty diaper")) { String(localized: "Log a wet and dirty diaper for \($0)") })
        case .sleepToggle:
            if baby.isSleeping {
                Button(intent: SleepButtonIntent(start: false, sleepID: baby.sleepID, babyID: babyID)) {
                    ButtonLabel(emoji: "🌤️", title: String(localized: "Woke up", comment: "Widget button: end the sleep"), stacked: stacked)
                }
                .tint(.indigo)
                .accessibilityLabel(voiceOver(String(localized: "Baby woke up, stop the sleep timer")) { String(localized: "\($0) woke up, stop the sleep timer", comment: "VoiceOver, widget button. The baby's name") })
            } else {
                Button(intent: SleepButtonIntent(start: true, babyID: babyID)) {
                    ButtonLabel(emoji: "😴", title: String(localized: "Sleep", comment: "Widget button: start a sleep"), stacked: stacked)
                }
                .tint(.indigo)
                .accessibilityLabel(voiceOver(String(localized: "Start the sleep timer")) { String(localized: "Start the sleep timer for \($0)") })
            }
        case .bottle:
            if let bottle = baby.usualBottle {
                Button(intent: LogBottleButtonIntent(formula: bottle.isFormula, amountML: bottle.ml, babyID: babyID)) {
                    ButtonLabel(emoji: "🍼", title: bottle.amountText.isEmpty ? String(localized: "Bottle", comment: "Widget button: log a bottle") : bottle.amountText, stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel(bottleVoiceOver(bottle))
            } else {
                InactiveButton(emoji: "🍼", title: String(localized: "Bottle", comment: "Widget button: log a bottle"), stacked: stacked)
                    .accessibilityLabel("Bottle. Log a first bottle in MyBaby, then this button logs the same again.")
            }
        case .breastfeed:
            if let timer = snapshot.timer(for: baby) {
                Button(intent: SwitchFeedingSideIntent()) {
                    ButtonLabel(emoji: "🔁", title: String(localized: "Switch", comment: "Widget button: switch breastfeeding side"), stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel(timer.side.other == .left ? Text("Switch breastfeeding to the left side") : Text("Switch breastfeeding to the right side"))
            } else if let timer = snapshot.feedingTimer {
                // There's one timer, and it's going for the other baby.
                InactiveButton(emoji: "🤱", title: timer.babyName, stacked: stacked)
                    .accessibilityLabel("The breastfeeding timer is going for \(timer.babyName)")
            } else {
                Button(intent: StartBreastfeedingButtonIntent(babyID: babyID)) {
                    ButtonLabel(emoji: "🤱", title: String(localized: "Breastfeed", comment: "Widget button: start the breastfeeding timer"), stacked: stacked)
                }
                .tint(.pink)
                .accessibilityLabel(voiceOver(String(localized: "Start the breastfeeding timer")) { String(localized: "Start the breastfeeding timer for \($0)") })
            }
        case .medicine:
            if let medicine = baby.lastMedicine, !medicine.name.isEmpty {
                if let allergy = medicine.allergyName {
                    // It matches a medicine allergy on the baby's list: never logged from here. Tapping
                    // opens the app, where the warning says more and the parent can still log it.
                    InactiveButton(emoji: "⚠️", title: String(localized: "Check allergy list", comment: "Widget button, in place of logging a medicine on the baby's allergy list"), stacked: stacked)
                        .accessibilityLabel("\(medicine.name). \(baby.name)'s allergy list includes \(allergy.lowercased()). Opens MyBaby.")
                } else if let next = medicine.nextAllowed, next > date {
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
                InactiveButton(emoji: "💊", title: String(localized: "Medicine", comment: "Widget button: log a medicine"), stacked: stacked)
                    .accessibilityLabel("Medicine. Log a medicine in MyBaby, then this button logs it again with the same dose.")
            }
        }
    }

    /// "Log a bottle of formula, 120 ml".
    private func bottleVoiceOver(_ bottle: WidgetSnapshot.BabySnapshot.Bottle) -> String {
        let amount = bottle.amountText
        switch (bottle.isFormula, amount.isEmpty) {
        case (true, true):
            return voiceOver(String(localized: "Log a bottle of formula")) {
                String(localized: "Log a bottle of formula for \($0)")
            }
        case (false, true):
            return voiceOver(String(localized: "Log a bottle of breast milk")) {
                String(localized: "Log a bottle of breast milk for \($0)")
            }
        case (true, false):
            return voiceOver(String(localized: "Log a bottle of formula, \(amount)", comment: "VoiceOver, widget button. The amount, e.g. 120 ml")) {
                String(localized: "Log a bottle of formula, \(amount) for \($0)", comment: "VoiceOver, widget button. First: the amount, e.g. 120 ml; second: the baby's name")
            }
        case (false, false):
            return voiceOver(String(localized: "Log a bottle of breast milk, \(amount)", comment: "VoiceOver, widget button. The amount, e.g. 120 ml")) {
                String(localized: "Log a bottle of breast milk, \(amount) for \($0)", comment: "VoiceOver, widget button. First: the amount, e.g. 120 ml; second: the baby's name")
            }
        }
    }

    /// "Log Tylenol, 2.5 ml".
    private func medicineVoiceOver(_ medicine: WidgetSnapshot.BabySnapshot.Medicine) -> String {
        let name = medicine.name
        let dose = medicine.dosage
        if dose.isEmpty {
            return voiceOver(String(localized: "Log \(name)", comment: "VoiceOver, widget button. The medicine")) {
                String(localized: "Log \(name) for \($0)", comment: "VoiceOver, widget button. First: the medicine; second: the baby's name")
            }
        }
        return voiceOver(String(localized: "Log \(name), \(dose)", comment: "VoiceOver, widget button. First: the medicine; second: the dose as the parent wrote it")) {
            String(localized: "Log \(name), \(dose) for \($0)", comment: "VoiceOver, widget button. First: the medicine; second: the dose; third: the baby's name")
        }
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
