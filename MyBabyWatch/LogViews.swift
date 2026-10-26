import SwiftUI

/// Pick formula or breast milk, then tap an amount, in the unit chosen on the iPhone (ml or oz).
struct BottleView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let context: WatchContext
    @State private var type: WatchCommand.Bottle

    init(context: WatchContext) {
        self.context = context
        // The same as the last bottle, as Siri does.
        _type = State(initialValue: context.lastBottle ?? .formula)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(WatchCommand.Bottle.allCases, id: \.self) { option in
                        Button {
                            type = option
                        } label: {
                            // The checkmark shows the choice, not only the color.
                            VStack(spacing: 2) {
                                Image(systemName: type == option ? "checkmark.circle.fill" : "circle")
                                Text(option.shortTitle)
                                    .font(.footnote)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        // `nil` keeps the screen's tint (dim red at night).
                        .tint(type == option ? nil : Color.gray)
                        .accessibilityLabel(option.shortTitle)
                        .accessibilityAddTraits(type == option ? AccessibilityTraits.isSelected : [])
                    }
                }

                if context.bottlePresets.isEmpty {
                    Text("Open MyBaby on your iPhone to load the bottle amounts.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(context.bottlePresets, id: \.self) { preset in
                            BigButton(
                                emoji: "🍼",
                                title: preset.title,
                                tint: .orange,
                                label: type == .formula
                                    ? String(localized: "Log \(preset.title) of formula", comment: "Watch, VoiceOver. An amount, e.g. 120 ml")
                                    : String(localized: "Log \(preset.title) of breast milk", comment: "Watch, VoiceOver. An amount, e.g. 120 ml")
                            ) {
                                store.log(
                                    .logBottle(type: type, ml: preset.ml),
                                    message: type == .formula
                                        ? String(localized: "\(preset.title) formula logged", comment: "Watch. An amount, e.g. 120 ml")
                                        : String(localized: "\(preset.title) breast milk logged", comment: "Watch. An amount, e.g. 120 ml")
                                )
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bottle")
    }
}

/// The medicines given before, most recent first. A tap records it with the dose logged last time,
/// which the button shows. It never suggests a dose.
///
/// A medicine on the baby's allergy list shows ⚠︎ and isn't logged from here: a tap says why instead,
/// so it's logged on the iPhone after checking with a doctor or pharmacist. (The iPhone checks too,
/// in case the list changed since the watch last heard from it.)
struct MedicineView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isNightMode) private var isNightMode

    let medicines: [WatchContext.Medicine]
    let babyName: String

    init(medicines: [WatchContext.Medicine], babyName: String) {
        self.medicines = medicines
        self.babyName = babyName
    }

    private func tapped(_ medicine: WatchContext.Medicine) {
        if let allergy = medicine.allergies?.first {
            store.showNotice(WatchContext.allergyMessage(babyName: babyName, allergyName: allergy))
            return
        }
        store.log(.logMedicine(name: medicine.name), message: String(localized: "\(medicine.name) logged", comment: "Watch. The medicine"))
        dismiss()
    }

    private func voiceOverLabel(for medicine: WatchContext.Medicine) -> String {
        if medicine.isOnAllergyList {
            return String(localized: "\(medicine.name), on \(babyName)'s allergy list. Log it on the iPhone.", comment: "Watch, VoiceOver. First: the medicine; second: the baby's name")
        }
        return medicine.dosage.isEmpty
            ? String(localized: "Log \(medicine.name)", comment: "Watch, VoiceOver. The medicine")
            : String(localized: "Log \(medicine.name), recorded as \(medicine.dosage)", comment: "Watch, VoiceOver. First: the medicine; second: the dose as the parent wrote it")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if medicines.isEmpty {
                    Text("Medicines you log in MyBaby on your iPhone show up here, to log again with a tap.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(medicines, id: \.self) { medicine in
                        Button {
                            tapped(medicine)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "\(medicine.isOnAllergyList ? "⚠︎" : "💊") \(medicine.name)")
                                    .font(.footnote.weight(.semibold))
                                if medicine.isOnAllergyList {
                                    Text("On \(babyName)'s allergy list")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if !medicine.dosage.isEmpty {
                                    Text("Records \(medicine.dosage)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        // Gray, not purple, so it doesn't read as one more medicine to tap.
                        .tint(medicine.isOnAllergyList ? Color.gray : (isNightMode ? WatchTheme.night : Color.purple))
                        .accessibilityLabel(voiceOverLabel(for: medicine))
                    }
                    Text("Logs the dose you recorded last time; edit the entry on your iPhone if it was different. Always follow your pediatrician's dosing instructions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Medicine")
    }
}
