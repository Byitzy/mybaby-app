import SwiftUI

/// What the temperature form holds while it's being edited.
struct TemperatureDraft {
    /// Tenths of a degree in the unit shown, e.g. 374 for 37.4 °C, so the wheel's tags compare exactly.
    var tenths = 370
    var method: TemperatureMethod = .rectal
    var symptoms: Set<Symptom> = []
    /// The reading as it was loaded, so an untouched one is saved as it was instead of being
    /// converted back from the rounded wheel value.
    private var loaded: (tenths: Int, celsius: Double)?

    init() {}

    /// The reading in °C.
    func celsius(unit: TemperatureUnit) -> Double {
        if let loaded, loaded.tenths == tenths { return loaded.celsius }
        return unit.toCelsius(Double(tenths) / 10)
    }

    static func tenths(celsius: Double, unit: TemperatureUnit) -> Int {
        Int((unit.fromCelsius(celsius) * 10).rounded())
    }

    /// The wheel's range: 34–43 °C, or the same span in °F.
    static func range(unit: TemperatureUnit) -> ClosedRange<Int> {
        Self.tenths(celsius: 34, unit: unit)...Self.tenths(celsius: 43, unit: unit)
    }

    /// A new reading starts at a normal temperature, with the method used last time.
    mutating func startNew(unit: TemperatureUnit, lastMethod: TemperatureMethod?) {
        tenths = Self.tenths(celsius: 37, unit: unit)
        method = lastMethod ?? .rectal
    }

    mutating func load(from activity: Activity, unit: TemperatureUnit) {
        if let celsius = activity.temperatureC {
            tenths = Self.tenths(celsius: celsius, unit: unit)
            loaded = (tenths, celsius)
        }
        method = activity.temperatureMethod ?? .rectal
        symptoms = Set(activity.symptoms)
    }

    func apply(to activity: Activity, unit: TemperatureUnit) {
        activity.temperatureC = celsius(unit: unit)
        activity.temperatureMethod = method
        activity.symptoms = Symptom.allCases.filter { symptoms.contains($0) }
    }
}

/// The temperature part of the activity editor, with a calm caution when it's a fever.
///
/// Fever guidance follows the American Academy of Pediatrics (AAP): any fever in a baby under
/// 3 months needs a call to the pediatrician right away. It's a tracking aid, not medical advice.
struct TemperatureSections: View {
    @Binding var draft: TemperatureDraft
    @Binding var startDate: Date
    let unit: TemperatureUnit
    /// For the baby's age on the day of the reading.
    let birthDate: Date?

    var body: some View {
        Section {
            DateField("Time", selection: $startDate)
            Picker("Temperature", selection: $draft.tenths) {
                ForEach(Array(TemperatureDraft.range(unit: unit)), id: \.self) { tenths in
                    Text(display(tenths)).tag(tenths)
                }
            }
            .pickerStyle(.wheel)
            Picker("Taken", selection: $draft.method) {
                ForEach(TemperatureMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
        } footer: {
            if draft.method != .rectal && isUnderThreeMonths != false {
                Text("For babies under 3 months, a rectal temperature is the most accurate (AAP).")
            }
        }

        if isFever {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(caution.title)
                            .font(.body.weight(.semibold))
                        Text(caution.message)
                            .font(.subheadline)
                    }
                } icon: {
                    // The title says "Fever" in words too, so the icon's color isn't the only signal.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(isUnderThreeMonths == false ? Palette.warning : Palette.danger)
                }
                .accessibilityElement(children: .combine)
            }
        }

        Section {
            ForEach(Symptom.allCases) { symptom in
                let isOn = draft.symptoms.contains(symptom)
                Button {
                    // Ticks it, or unticks it.
                    draft.symptoms.formSymmetricDifference([symptom])
                } label: {
                    HStack {
                        Text(symptom.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        } header: {
            Text("Symptoms")
        } footer: {
            Text("Call emergency services if your baby is struggling to breathe, is unusually hard to wake or floppy, has blue or gray lips, or has a seizure. Fever guidance from the American Academy of Pediatrics (AAP). MyBaby isn't medical advice.")
        }
    }

    private var isFever: Bool {
        FeverGuide.isFever(celsius: draft.celsius(unit: unit), method: draft.method)
    }

    private var isUnderThreeMonths: Bool? {
        FeverGuide.isUnderThreeMonths(birthDate: birthDate, on: startDate)
    }

    private var caution: (title: String, message: String) {
        FeverGuide.caution(underThreeMonths: isUnderThreeMonths)
    }

    /// "37.4 °C" for a wheel tag.
    private func display(_ tenths: Int) -> String {
        "\((Double(tenths) / 10).formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"
    }
}
