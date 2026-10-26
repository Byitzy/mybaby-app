import Foundation

/// What kind of help a support resource offers. The screen lists them in this order.
enum SupportKind: String, Codable, CaseIterable, Identifiable {
    /// Suicide and emotional crisis lines.
    case crisis
    /// Support in pregnancy and after a baby.
    case perinatal
    /// Nurse and health advice lines, like 811 or NHS 111.
    case healthLine
    /// Anything else: parenting lines, directories, listening lines.
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crisis: return String(localized: "Crisis lines", comment: "Section of help lines: suicide and emotional crisis lines")
        case .perinatal: return String(localized: "Pregnancy and new-parent support", comment: "Section of help lines")
        case .healthLine: return String(localized: "Health lines", comment: "Section of help lines: nurse and health advice lines")
        case .general: return String(localized: "More support", comment: "Section of help lines")
        }
    }
}

/// A help line or website from `support-resources.json`.
struct SupportResource: Decodable, Hashable, Identifiable {
    /// A number to text, with an optional first message (like "SHOUT").
    struct TextLine: Decodable, Hashable {
        let number: String
        let body: String?
    }

    let name: String
    /// One line on what it's for.
    let details: String
    /// As it's written for people, e.g. "1-800-944-4773" or "116 123".
    let phone: String?
    let sms: TextLine?
    let url: URL?
    let hours: String?
    let languages: [String]?
    let kind: SupportKind
    /// The pages the number was checked on.
    let sources: [URL]?
    /// The one line the "You're not alone" card offers for this region (or province), when
    /// there's one that suits someone having a lot of hard days.
    let featured: Bool?

    var id: String { "\(kind.rawValue)|\(name)" }

    private enum CodingKeys: String, CodingKey {
        case name, phone, sms, url, hours, languages, kind, sources, featured
        case details = "description"
    }

    var isFeatured: Bool { featured ?? false }

    var phoneURL: URL? { phone.flatMap { SupportDirectory.telURL($0) } }

    var textURL: URL? { sms.flatMap { SupportDirectory.smsURL($0.number, body: $0.body) } }

    /// "24/7 · English, French", when either is known.
    var hoursAndLanguages: String? {
        let parts = [hours, languages.map { $0.joined(separator: ", ") }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// An emergency number, like 911, or 10177 "ambulance".
struct EmergencyNumber: Decodable, Hashable, Identifiable {
    let number: String
    /// What it's for or who answers, when a region has more than one, e.g. "SAMU".
    let label: String?

    var id: String { number }

    /// "15 (SAMU)".
    var text: String { label.map { "\(number) (\($0))" } ?? number }

    var phoneURL: URL? { SupportDirectory.telURL(number) }
}

/// A province or state with lines of its own, like Quebec's 811.
struct SupportSubregion: Decodable, Hashable, Identifiable {
    let code: String
    let name: String
    let resources: [SupportResource]

    var id: String { code }
}

/// One country's emergency number and help lines.
struct SupportRegion: Decodable, Hashable, Identifiable {
    /// ISO 3166-1 code, as in `Locale.Region` ("CA", "GB"), or "other".
    let code: String
    let name: String
    /// yyyy-MM-dd.
    let lastVerified: String
    /// Empty for "Other / not listed".
    let emergency: [EmergencyNumber]
    let resources: [SupportResource]
    let subregions: [SupportSubregion]?
    let sources: [URL]

    var id: String { code }

    /// "911", "15 (SAMU) or 112", "10177 (ambulance), 10111 (police) or 112 (from a mobile)".
    var emergencyText: String? {
        let numbers = emergency.map(\.text)
        guard let last = numbers.last else { return nil }
        guard numbers.count > 1 else { return last }
        let others = numbers.dropLast().joined(separator: ", ")
        return String(
            localized: "\(others) or \(last)",
            comment: "Emergency numbers to call: the first ones (separated by commas), then the last one, like “15 (SAMU) or 112”"
        )
    }

    func subregion(code: String) -> SupportSubregion? {
        subregions?.first { $0.code == code }
    }

    /// The region's resources of `kind`, with the chosen province's first.
    func lines(_ kind: SupportKind, subregion: SupportSubregion?) -> [SupportResource] {
        ((subregion?.resources ?? []) + self.resources).filter { $0.kind == kind }
    }

    /// The line the "You're not alone" card offers: the chosen province's, else the region's.
    /// Nil when none is marked `featured`, or it has no phone number.
    func featuredLine(subregion: SupportSubregion?) -> SupportResource? {
        ((subregion?.resources ?? []) + self.resources).first { $0.isFeatured && $0.phoneURL != nil }
    }
}

/// The help lines bundled in `support-resources.json`, by region.
///
/// The region comes from the iPhone's Region setting (Settings → General → Language & Region),
/// never from location services: it's private, needs no permission, and says where the person
/// lives rather than where the phone is right now. They can pick another region in the app; that
/// choice is kept in `UserDefaults.standard` under `supportRegion`.
struct SupportDirectory: Decodable {
    /// The `UserDefaults.standard` key for a region picked by hand: a region code, "other", or
    /// empty (or missing) to follow the iPhone's Region.
    static let regionKey = "supportRegion"
    /// The `UserDefaults.standard` key for the province or state picked within the region, e.g. "QC".
    static let subregionKey = "supportSubregion"
    /// The stored value for "Other / not listed".
    static let otherCode = "other"

    /// yyyy-MM-dd: when every number was last checked.
    let lastVerified: String
    /// yyyy-MM-dd: when to check them all again.
    let reverifyBy: String
    let regions: [SupportRegion]
    /// "Other / not listed": no emergency number of its own, and an international directory.
    let other: SupportRegion

    /// Loaded once from the app bundle. Nil only if the file is missing or broken, which the
    /// screen handles by showing the "Other / not listed" text.
    static let bundled: SupportDirectory? = load()

    static func load(bundle: Bundle = .main) -> SupportDirectory? {
        guard let url = bundle.url(forResource: "support-resources", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("support-resources.json is missing from the bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(SupportDirectory.self, from: data)
        } catch {
            assertionFailure("support-resources.json didn't decode: \(error)")
            return nil
        }
    }

    /// The iPhone's Region setting, e.g. "CA". No location permission involved.
    static var deviceRegionCode: String? {
        Locale.current.region?.identifier
    }

    /// The listed region with this code, if there is one.
    func region(code: String?) -> SupportRegion? {
        guard let code, !code.isEmpty else { return nil }
        return regions.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// The region to show: the one picked by hand, otherwise the iPhone's Region, otherwise "Other".
    func resolvedRegion(override: String, deviceRegion: String? = SupportDirectory.deviceRegionCode) -> SupportRegion {
        if override == Self.otherCode { return other }
        return region(code: override) ?? region(code: deviceRegion) ?? other
    }

    /// Regions sorted by name for the picker.
    var sortedRegions: [SupportRegion] {
        regions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Links

    /// `tel:` with only the digits (and a leading +), so "1-800-944-4773" dials 18009444773.
    static func telURL(_ number: String) -> URL? {
        let digits = dialable(number)
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    /// `sms:` to the number, with the first message filled in when there is one.
    static func smsURL(_ number: String, body: String?) -> URL? {
        let digits = dialable(number)
        guard !digits.isEmpty else { return nil }
        guard let body, !body.isEmpty,
              let encoded = body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return URL(string: "sms:\(digits)")
        }
        return URL(string: "sms:\(digits)&body=\(encoded)")
    }

    static func dialable(_ number: String) -> String {
        String(number.filter { $0.isASCII && ($0.isNumber || $0 == "+") })
    }

    /// The number one digit at a time, for VoiceOver ("1 1 6 1 2 3" rather than "one hundred
    /// sixteen…").
    static func spoken(_ number: String) -> String {
        dialable(number).map { String($0) }.joined(separator: " ")
    }

    // MARK: - Dates

    /// "October 25, 2026" (in the person's own date style) from "2026-10-25".
    static func displayDate(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return date.formatted(date: .long, time: .omitted)
    }
}
