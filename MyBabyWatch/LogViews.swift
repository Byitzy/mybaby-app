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
                                label: "Log \(preset.title) of \(type.shortTitle.lowercased())"
                            ) {
                                store.log(
                                    .logBottle(type: type, ml: preset.ml),
                                    message: "\(preset.title) \(type.shortTitle.lowercased()) logged"
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
struct MedicineView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isNightMode) private var isNightMode

    let medicines: [WatchContext.Medicine]

    init(medicines: [WatchContext.Medicine]) {
        self.medicines = medicines
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
                            store.log(.logMedicine(name: medicine.name), message: "\(medicine.name) logged")
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("💊 \(medicine.name)")
                                    .font(.footnote.weight(.semibold))
                                if !medicine.dosage.isEmpty {
                                    Text("Records \(medicine.dosage)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(isNightMode ? WatchTheme.night : .purple)
                        .accessibilityLabel(
                            medicine.dosage.isEmpty
                                ? "Log \(medicine.name)"
                                : "Log \(medicine.name), recorded as \(medicine.dosage)"
                        )
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
