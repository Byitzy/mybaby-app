import CoreData
import Foundation

// Pumping sessions and temperature readings are `Activity` entries too, so they show up in the
// timeline, History, the CSV export and the PDF like everything else.
extension Activity {
    // Pumping. The total is also kept in `amountMLNumber`, so the CSV's amount column has it.
    @NSManaged var pumpLeftMLNumber: NSNumber?
    @NSManaged var pumpRightMLNumber: NSNumber?
    /// How long a pumping session took.
    @NSManaged var durationMinutesNumber: NSNumber?

    // Temperature, always stored in degrees Celsius.
    @NSManaged var temperatureCNumber: NSNumber?
    @NSManaged var temperatureMethodRaw: String?
    /// `Symptom` raw values, comma separated, e.g. "cough,runnyNose".
    @NSManaged var symptomsRaw: String?

    var pumpLeftML: Double? {
        get { pumpLeftMLNumber?.doubleValue }
        set { pumpLeftMLNumber = newValue.map { NSNumber(value: $0) } }
    }

    var pumpRightML: Double? {
        get { pumpRightMLNumber?.doubleValue }
        set { pumpRightMLNumber = newValue.map { NSNumber(value: $0) } }
    }

    var durationMinutes: Int? {
        get { durationMinutesNumber?.intValue }
        set { durationMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Both sides together, or the stored total when the sides weren't recorded.
    var pumpedTotalML: Double? {
        if pumpLeftML == nil && pumpRightML == nil { return amountML }
        return (pumpLeftML ?? 0) + (pumpRightML ?? 0)
    }

    var temperatureC: Double? {
        get { temperatureCNumber?.doubleValue }
        set { temperatureCNumber = newValue.map { NSNumber(value: $0) } }
    }

    var temperatureMethod: TemperatureMethod? {
        get { temperatureMethodRaw.flatMap(TemperatureMethod.init(rawValue:)) }
        set { temperatureMethodRaw = newValue?.rawValue }
    }

    /// The symptoms ticked, in the order they're listed in the editor.
    var symptoms: [Symptom] {
        get {
            let raw = Set((symptomsRaw ?? "").split(separator: ",").map(String.init))
            return Symptom.allCases.filter { raw.contains($0.rawValue) }
        }
        set {
            symptomsRaw = newValue.isEmpty ? nil : newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// At or above the AAP fever line for how it was measured.
    var isFever: Bool {
        guard let temperatureC else { return false }
        return FeverGuide.isFever(celsius: temperatureC, method: temperatureMethod ?? .rectal)
    }

    /// "Total 120 ml · Left 60 ml · Right 60 ml · 15 min".
    func pumpingDetailParts(unit: VolumeUnit) -> [String] {
        var parts: [String] = []
        if let total = pumpedTotalML, total > 0 {
            parts.append(String(localized: "Total \(unit.format(ml: total))", comment: "Milk pumped from both sides"))
        }
        if let left = pumpLeftML, left > 0 {
            parts.append(String(localized: "Left \(unit.format(ml: left))", comment: "Milk pumped from the left side"))
        }
        if let right = pumpRightML, right > 0 {
            parts.append(String(localized: "Right \(unit.format(ml: right))", comment: "Milk pumped from the right side"))
        }
        if let minutes = durationMinutes, minutes > 0 {
            parts.append(String(localized: "\(minutes) min", comment: "How long a pumping session took, in minutes"))
        }
        return parts
    }

    /// "38.4 °C · Fever · Rectal · Cough, Runny nose".
    func temperatureDetailParts(unit: TemperatureUnit = .current) -> [String] {
        var parts: [String] = []
        if let temperatureC {
            parts.append(unit.format(celsius: temperatureC))
            if isFever { parts.append(String(localized: "Fever")) }
        }
        if let temperatureMethod { parts.append(temperatureMethod.title) }
        let symptoms = self.symptoms
        if !symptoms.isEmpty { parts.append(symptoms.map(\.title).joined(separator: ", ")) }
        return parts
    }
}

/// Where a temperature was taken. The fever line depends on it.
enum TemperatureMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    case rectal, armpit, ear, forehead, oral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectal: return String(localized: "Rectal", comment: "Where a temperature was taken")
        case .armpit: return String(localized: "Armpit", comment: "Where a temperature was taken")
        case .ear: return String(localized: "Ear", comment: "Where a temperature was taken")
        case .forehead: return String(localized: "Forehead", comment: "Where a temperature was taken")
        case .oral: return String(localized: "Oral", comment: "Where a temperature was taken: by mouth")
        }
    }

    /// The CSV export's Temperature method column, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .rectal: return "Rectal"
        case .armpit: return "Armpit"
        case .ear: return "Ear"
        case .forehead: return "Forehead"
        case .oral: return "Oral"
        }
    }
}

/// Common signs of sickness to note next to a temperature.
enum Symptom: String, CaseIterable, Identifiable, Codable {
    case cough, runnyNose, vomiting, diarrhea, rash, fussy, poorFeeding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cough: return String(localized: "Cough", comment: "Symptom")
        case .runnyNose: return String(localized: "Runny nose", comment: "Symptom")
        case .vomiting: return String(localized: "Vomiting", comment: "Symptom")
        case .diarrhea: return String(localized: "Diarrhea", comment: "Symptom")
        case .rash: return String(localized: "Rash", comment: "Symptom")
        case .fussy: return String(localized: "Fussy", comment: "Symptom: the baby is fussy")
        case .poorFeeding: return String(localized: "Poor feeding", comment: "Symptom: the baby isn't feeding well")
        }
    }

    /// The CSV export's Symptoms column, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .cough: return "Cough"
        case .runnyNose: return "Runny nose"
        case .vomiting: return "Vomiting"
        case .diarrhea: return "Diarrhea"
        case .rash: return "Rash"
        case .fussy: return "Fussy"
        case .poorFeeding: return "Poor feeding"
        }
    }
}

/// Fever lines from the American Academy of Pediatrics (AAP, HealthyChildren.org): 100.4 °F (38 °C)
/// or higher rectal, ear or forehead; 100 °F (37.8 °C) or higher by mouth; 99 °F (37.2 °C) or
/// higher under the arm.
enum FeverGuide {
    /// The AAP numbers are given in °F, so readings are compared in °F. The small allowance keeps
    /// 38.0 °C (100.4 °F) and 37.2 °C (98.96 °F) on the fever side after converting.
    static func isFever(celsius: Double, method: TemperatureMethod) -> Bool {
        let fahrenheit = celsius * 9 / 5 + 32
        return fahrenheit >= feverLineF(method) - 0.05
    }

    static func feverLineF(_ method: TemperatureMethod) -> Double {
        switch method {
        case .rectal, .ear, .forehead: return 100.4
        case .oral: return 100.0
        case .armpit: return 99.0
        }
    }

    /// The caution shown with a fever reading, from the AAP's guidance: any fever in a baby under 3 months
    /// needs a call to the pediatrician right away. `underThreeMonths` is `nil` without a birthday. The
    /// temperature editor shows it, and Siri says it after logging a fever, in the same words.
    static func caution(underThreeMonths: Bool?) -> (title: String, message: String) {
        switch underThreeMonths {
        case true?:
            return (
                String(localized: "Fever in a baby under 3 months"),
                String(localized: "Call your pediatrician right away, or seek care now.")
            )
        case false?:
            return (
                String(localized: "Fever"),
                String(localized: "Keep an eye on it, and call your pediatrician if you're worried.", comment: "After a fever reading in a baby 3 months or older")
            )
        case nil:
            return (
                String(localized: "Fever"),
                String(localized: "If your baby is under 3 months old, call your pediatrician right away or seek care now. Otherwise keep an eye on it, and call if you're worried.")
            )
        }
    }

    /// Whether the baby was younger than 3 months on `date`, or `nil` without a birthday.
    static func isUnderThreeMonths(birthDate: Date?, on date: Date, calendar: Calendar = .current) -> Bool? {
        guard let birthDate,
              let threeMonths = calendar.date(byAdding: .month, value: 3, to: calendar.startOfDay(for: birthDate))
        else { return nil }
        return date < threeMonths
    }
}
