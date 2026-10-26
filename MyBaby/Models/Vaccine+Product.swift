import CoreData
import Foundation

/// What was in the shot, from the vaccine record or the box: the brand or product, the amount given
/// and the expiry date. All optional: most records only have a name and a lot number, and older
/// vaccines have none of these.
extension Vaccine {
    /// The brand or product, e.g. "Infanrix hexa" or "Prevnar 20".
    @NSManaged var productName: String?
    @NSManaged var doseAmountNumber: NSNumber?
    /// A `VaccineDoseUnit` raw value.
    @NSManaged var doseUnit: String?
    /// The expiry date printed on the vaccine, a day without a time.
    @NSManaged var expiryDate: Date?

    var product: String {
        (productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var doseAmount: Double? {
        get { doseAmountNumber?.doubleValue }
        set { doseAmountNumber = newValue.map { NSNumber(value: $0) } }
    }

    var amountUnit: VaccineDoseUnit {
        doseUnit.flatMap(VaccineDoseUnit.init(rawValue:)) ?? .milliliters
    }

    /// "0.5 mL", or nil without an amount.
    var doseAmountText: String? {
        doseAmount.map { amountUnit.format($0) }
    }
}

/// The units a dose is written in on a vaccine record. Almost always millilitres.
enum VaccineDoseUnit: String, CaseIterable, Identifiable {
    case milliliters = "mL"
    case grams = "g"
    case milligrams = "mg"

    var id: String { rawValue }

    /// The symbol, as printed on records and in the CSV ("mL"). The same in English, French and Spanish.
    var symbol: String { rawValue }

    /// "0.5 mL", with the decimal separator of the iPhone's language.
    func format(_ amount: Double) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...3)))) \(symbol)"
    }
}

extension VaccineGuide {
    /// Brands to suggest for each vaccine in the guide, by entry id. Suggestions only: any product
    /// can be typed. Names as printed on the box, so they're the same in every language.
    static let brands: [String: [String]] = [
        "hepb": ["Engerix-B", "Recombivax HB", "Heplisav-B"],
        "rsv": ["Beyfortus", "Enflonsia", "Synagis"],
        "rotavirus": ["RotaTeq", "Rotarix"],
        "dtap": ["Daptacel", "Infanrix"],
        "hib": ["ActHIB", "PedvaxHIB", "Hiberix"],
        "pcv": ["Prevnar 20", "Prevnar 13", "Vaxneuvance", "Prevenar 13"],
        "ipv": ["IPOL", "Imovax Polio"],
        "flu": ["Fluzone", "Fluarix", "FluLaval", "Afluria", "Flucelvax", "FluMist", "Fluenz"],
        "covid": ["Spikevax", "Comirnaty", "Nuvaxovid", "mNEXSPIKE"],
        "mmr": ["M-M-R II", "Priorix"],
        "varicella": ["Varivax", "Varilrix"],
        "hepa": ["Havrix", "Vaqta", "Avaxim"],
        "6in1": ["Vaxelis", "Infanrix hexa", "Hexyon", "Hexaxim"],
        "5in1": ["Pentacel", "Pediacel", "Pentaxim"],
        "dtap-hepb-ipv": ["Pediarix"],
        "dtap-ipv": ["Kinrix", "Quadracel", "Repevax", "Infanrix-IPV", "Boostrix-IPV"],
        "mmrv": ["ProQuad", "Priorix-Tetra"],
        "menb": ["Bexsero", "Trumenba"],
        "menc": ["NeisVac-C", "Menjugate"],
        "menacwy": ["MenQuadfi", "Menveo", "Nimenrix", "Penbraya", "Penmenvy"],
        "bcg": ["BCG Vaccine"],
    ]
}
