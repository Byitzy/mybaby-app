import CoreData
import SwiftUI

/// Fills in a stretch nobody logged with rough counts: so many wet and dirty diapers, bottles (about
/// so much each), breastfeeds and naps. Each becomes an **approximate** entry (`Activity.isApproximate`,
/// shown with "≈"), spread evenly over the stretch, and the stretch is marked *caught up*, so Reports
/// count it as tracked.
struct CatchUpView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.canEditLog) private var canEditLog
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()

    /// After saving, with a short summary for a confirmation.
    var onSaved: ((String) -> Void)?

    @State private var start: Date
    @State private var end: Date
    @State private var wet = 0
    @State private var dirty = 0
    @State private var bottles = 0
    @State private var bottleType: FeedingType = .formula
    /// In the user's unit (ml or oz). Set when the sheet opens.
    @State private var bottleAmount: Double = 0
    @State private var breastfeeds = 0
    @State private var naps = 0
    @State private var napMinutes = 45
    @State private var notes = ""

    init(start: Date, end: Date, onSaved: ((String) -> Void)? = nil) {
        let now = Date.now
        _start = State(initialValue: min(start, end, now))
        _end = State(initialValue: min(max(start, end), now))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canEditLog {
                    Section { ViewOnlyBanner(message: "You can see this, but only the parents can add entries.") }
                }

                Section {
                    DateField("From", selection: $start, in: ...end)
                    DateField("To", selection: $end, in: start...Date.now)
                } header: {
                    Text("Time to catch up on")
                }

                Section {
                    countRow("💧", "Wet diapers", $wet)
                    countRow("💩", "Dirty diapers", $dirty)
                } header: {
                    EmojiTitle("🧷", "Diapers")
                }

                Section {
                    countRow("🍼", "Bottles", $bottles)
                    if bottles > 0 {
                        Picker("Bottle of", selection: $bottleType) {
                            Text("Formula").tag(FeedingType.formula)
                            Text("Breast milk").tag(FeedingType.breastMilkBottle)
                        }
                        Stepper(value: $bottleAmount, in: unit.step...unit.maxValue, step: unit.step) {
                            LabeledContent("About", value: "\(unit.format(value: bottleAmount)) each")
                        }
                    }
                    countRow("🤱", "Breastfeeds", $breastfeeds)
                } header: {
                    EmojiTitle("🍼", "Feeds")
                }

                Section {
                    countRow("😴", "Naps", $naps, upTo: 10)
                    if naps > 0 {
                        Stepper(value: $napMinutes, in: 10...240, step: 5) {
                            LabeledContent("About", value: "\(Format.duration(Double(napMinutes) * 60)) each")
                        }
                        .accessibilityValue("\(Format.spokenDuration(Double(napMinutes) * 60)) each")
                    }
                } header: {
                    EmojiTitle("😴", "Sleep")
                }

                Section {
                    TextField("Optional, e.g. what grandma said", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Notes")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Catch up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if bottleAmount == 0 {
                    bottleAmount = unit == .ml ? 90 : 3
                }
            }
        }
        .threeAMSheet()
    }

    // MARK: Pieces

    private func countRow(_ emoji: String, _ title: String, _ value: Binding<Int>, upTo limit: Int = 20) -> some View {
        Stepper(value: value, in: 0...limit) {
            LabeledContent {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
            } label: {
                EmojiTitle(emoji, title)
            }
        }
    }

    private var total: Int { wet + dirty + bottles + breastfeeds + naps }

    /// "1 approximate entry", "6 approximate entries".
    private var entriesText: String {
        total == 1 ? "1 approximate entry" : "\(total) approximate entries"
    }

    private var canSave: Bool {
        canEditLog && end > start && total > 0
    }

    private var footer: String {
        guard total > 0 else {
            return "Add a rough count of what happened. If nothing did, use Nothing happened instead."
        }
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "Adds \(entriesText) spread evenly from \(from) to \(to). They show ≈ in History, count in Reports, and this time counts as tracked."
    }

    // MARK: Saving

    private func save() {
        let range = DateInterval(start: min(start, end), end: max(start, end))
        let plan = NightPlan(data: nightPlanData)

        func add(_ kind: ActivityKind, at date: Date, configure: (Activity) -> Void) {
            let activity = Activity.create(kind, startDate: date, in: context)
            activity.isApproximate = true
            activity.caregiver = plan.shift(at: date)?.parent
            configure(activity)
        }

        for date in Coverage.evenlySpread(wet, over: range) {
            add(.diaper, at: date) { $0.diaperType = .wet }
        }
        for date in Coverage.evenlySpread(dirty, over: range) {
            add(.diaper, at: date) { $0.diaperType = .dirty }
        }
        let amountML = unit.toML(bottleAmount)
        for date in Coverage.evenlySpread(bottles, over: range) {
            add(.feeding, at: date) { feed in
                feed.feedingType = bottleType
                feed.amountML = amountML
            }
        }
        for date in Coverage.evenlySpread(breastfeeds, over: range) {
            add(.feeding, at: date) { $0.feedingType = .breast }
        }
        for nap in Coverage.napTimes(naps, minutes: napMinutes, over: range) {
            add(.sleep, at: nap.start) { $0.endDate = nap.end }
        }

        let period = TrackingPeriod.create(.caughtUp, start: range.start, end: range.end, in: context)
        period.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        context.saveIfChanged()
        if bottles + breastfeeds > 0 {
            NotificationManager.refreshFeedingReminder(context: context)
        }
        onSaved?("Caught up · \(entriesText) added")
        dismiss()
    }
}
