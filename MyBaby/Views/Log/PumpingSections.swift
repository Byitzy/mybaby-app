import CoreData
import SwiftUI

/// What the pumping form holds while it's being edited. Amounts are in the units shown (ml or oz).
struct PumpingDraft {
    var left: Double = 0
    var right: Double = 0
    var minutes = 0
    /// Put the milk in the stash when saving a new session.
    var addToStash = false
    var storage: MilkStorage = .fridge
    /// The total split evenly into this many bags.
    var bagCount = 1

    var total: Double { left + right }

    mutating func load(from activity: Activity, unit: VolumeUnit) {
        left = activity.pumpLeftML.map(unit.fromML) ?? 0
        right = activity.pumpRightML.map(unit.fromML) ?? 0
        minutes = activity.durationMinutes ?? 0
    }

    func apply(to activity: Activity, unit: VolumeUnit) {
        activity.pumpLeftML = left > 0 ? unit.toML(left) : nil
        activity.pumpRightML = right > 0 ? unit.toML(right) : nil
        activity.amountML = total > 0 ? unit.toML(total) : nil
        activity.durationMinutes = minutes > 0 ? minutes : nil
    }

    /// Adds the bags to the stash, when that's switched on and something was pumped.
    func addBags(pumpedAt date: Date, unit: VolumeUnit, in context: NSManagedObjectContext) {
        guard addToStash, total > 0, bagCount > 0 else { return }
        let perBag = unit.toML(total) / Double(bagCount)
        for _ in 0..<bagCount {
            MilkBag.create(amountML: perBag, pumpedDate: date, storage: storage, in: context)
        }
    }
}

/// The pumping part of the activity editor: time, how long, and how much from each side.
struct PumpingSections: View {
    @Binding var draft: PumpingDraft
    @Binding var startDate: Date
    let unit: VolumeUnit
    /// The stash option is only offered for a new session, so editing never adds bags twice.
    let isNew: Bool
    @Environment(\.canEditLog) private var canEditLog

    var body: some View {
        Section {
            DateField("Time", selection: $startDate)
            Stepper(value: $draft.minutes, in: 0...120) {
                LabeledContent("Duration", value: draft.minutes > 0 ? "\(draft.minutes) min" : "Not set")
            }
        }

        Section {
            amountStepper("Left side", value: $draft.left)
            amountStepper("Right side", value: $draft.right)
            LabeledContent("Total", value: unit.format(value: draft.total))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        } header: {
            Text("How much")
        } footer: {
            Text("Only pumped one side, or into one bottle? Put the whole amount on one side.")
        }

        if isNew {
            Section {
                Toggle("Add to milk stash", isOn: $draft.addToStash)
                    .disabled(!canEditLog)
                if draft.addToStash {
                    Picker("Store in", selection: $draft.storage) {
                        ForEach(MilkStorage.allCases) { storage in
                            Text(storage.shortTitle).tag(storage)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $draft.bagCount, in: 1...8) {
                        LabeledContent("Bags", value: bagsText)
                    }
                }
            } footer: {
                if draft.addToStash {
                    Text(draft.total > 0 ? MilkStorageGuide.summary : "Add an amount to put it in the stash.")
                }
            }
        }
    }

    /// "1 bag" or "3 bags of 40 ml".
    private var bagsText: String {
        let bags = Format.plural(draft.bagCount, "bag")
        guard draft.bagCount > 1, draft.total > 0 else { return bags }
        return "\(bags) of \(unit.format(value: draft.total / Double(draft.bagCount)))"
    }

    private func amountStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...unit.maxValue, step: unit.step) {
            LabeledContent(title, value: unit.format(value: value.wrappedValue))
                .monospacedDigit()
        }
    }
}
