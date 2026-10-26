import Foundation

/// Keys for values kept in `UserDefaults` / `@AppStorage`.
///
/// Settings that widgets and the Apple Watch app will need too are kept in `UserDefaults.shared`
/// (the App Group), so use `@AppStorage(key, store: .shared)` for them. The rest stay in `.standard`.
enum SettingsKey {
    // In `UserDefaults.shared`:
    static let volumeUnit = "volumeUnit"
    /// `GrowthUnits` for weight and length.
    static let growthUnits = "growthUnits"
    static let feedingReminderEnabled = "feedingReminderEnabled"
    static let feedingReminderHours = "feedingReminderHours"
    /// Whether the log syncs through iCloud. Off means it stays on this iPhone only.
    static let iCloudSync = "iCloudSyncEnabled"
    /// Set while deleting the iCloud copy hasn't finished (see `PersistenceController.deleteICloudCopy`).
    static let iCloudDeletionPending = "iCloudDeletionPending"
    /// JSON-encoded `NightPlan`.
    static let nightPlan = "nightPlan"
    /// The `uuid` of the baby the app shows, when there's more than one.
    static let selectedBaby = "selectedBaby"
    /// `TemperatureUnit` for the fever log.
    static let temperatureUnit = "temperatureUnit"
    /// A notification the morning a bag in the milk stash reaches its use-by date.
    static let milkStashReminder = "milkStashReminder"
    /// `uuid`s of the medicine schedules that notify this iPhone when the next dose is allowed.
    /// Kept per phone, so the parent who's asleep isn't woken for it.
    static let medicineDoseAlerts = "medicineDoseAlerts"
    /// "Haven't logged in a while": a notification when an untracked gap begins (`GapReminder`). Off by default.
    static let gapReminderEnabled = "gapReminderEnabled"

    // In `UserDefaults.standard`:
    /// `ThreeAMMode`.
    static let threeAMMode = "threeAMMode"
    /// When the gap Today's "Nothing logged since…" card was dismissed for began (seconds since 1970),
    /// so it stays hidden until a new gap.
    static let dismissedGapStart = "dismissedGapStart"
}

// `AppGroup` and `UserDefaults.shared` are in Shared/AppGroup.swift, which the widgets build too.

enum VolumeUnit: String, CaseIterable, Identifiable {
    case ml, oz

    var id: String { rawValue }

    static let mlPerOunce = 29.5735

    var title: String {
        switch self {
        case .ml: return String(localized: "Milliliters (ml)")
        case .oz: return String(localized: "Ounces (oz)")
        }
    }

    var step: Double { self == .ml ? 5 : 0.5 }
    var maxValue: Double { self == .ml ? 500 : 16 }
    var presets: [Double] { self == .ml ? [30, 60, 90, 120, 150, 180] : [1, 2, 3, 4, 5, 6] }

    func fromML(_ ml: Double) -> Double {
        self == .ml ? ml : ml / Self.mlPerOunce
    }

    func toML(_ value: Double) -> Double {
        self == .ml ? value : value * Self.mlPerOunce
    }

    func format(value: Double) -> String {
        switch self {
        case .ml:
            return String(localized: "\(Int(value.rounded())) ml", comment: "An amount in milliliters, e.g. “120 ml”")
        case .oz:
            let ounces = value.formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: "\(ounces) oz", comment: "An amount in fluid ounces, e.g. “4.5 oz”")
        }
    }

    func format(ml: Double) -> String {
        format(value: fromML(ml))
    }
}

/// Units for body temperature. Temperatures are always stored in degrees Celsius.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    var id: String { rawValue }

    /// Fahrenheit in the US, Celsius everywhere else.
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// The setting as saved, for code outside a view.
    static var current: TemperatureUnit {
        UserDefaults.shared.string(forKey: SettingsKey.temperatureUnit).flatMap(TemperatureUnit.init(rawValue:))
            ?? localeDefault
    }

    var title: String {
        switch self {
        case .celsius: return String(localized: "Celsius (°C)")
        case .fahrenheit: return String(localized: "Fahrenheit (°F)")
        }
    }

    var symbol: String {
        self == .celsius
            ? String(localized: "°C", comment: "Unit symbol: degrees Celsius")
            : String(localized: "°F", comment: "Unit symbol: degrees Fahrenheit")
    }

    func fromCelsius(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    func toCelsius(_ value: Double) -> Double {
        self == .celsius ? value : (value - 32) * 5 / 9
    }

    /// "38.4 °C" or "101.1 °F".
    func format(celsius: Double) -> String {
        let number = fromCelsius(celsius).formatted(.number.precision(.fractionLength(1)))
        switch self {
        case .celsius: return String(localized: "\(number) °C", comment: "A temperature in degrees Celsius, e.g. “38.4 °C”")
        case .fahrenheit: return String(localized: "\(number) °F", comment: "A temperature in degrees Fahrenheit, e.g. “101.1 °F”")
        }
    }
}

/// Units for weight and length. Measurements are always stored in kilograms and centimeters.
enum GrowthUnits: String, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }

    static let kgPerPound = 0.45359237
    static let cmPerInch = 2.54

    /// Pounds and inches in the US, kilograms and centimeters everywhere else.
    static var localeDefault: GrowthUnits {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }

    var title: String {
        switch self {
        case .metric: return String(localized: "Kilograms & centimeters")
        case .imperial: return String(localized: "Pounds & inches")
        }
    }

    /// The unit weight charts are drawn in.
    var weightUnit: String {
        self == .metric
            ? String(localized: "kg", comment: "Unit symbol: kilograms")
            : String(localized: "lb", comment: "Unit symbol: pounds")
    }

    var lengthUnit: String {
        self == .metric
            ? String(localized: "cm", comment: "Unit symbol: centimeters")
            : String(localized: "in", comment: "Unit symbol: inches")
    }

    // MARK: Conversions

    /// Kilograms or (fractional) pounds, e.g. for a chart.
    func fromKg(_ kg: Double) -> Double {
        self == .metric ? kg : kg / Self.kgPerPound
    }

    func toKg(_ value: Double) -> Double {
        self == .metric ? value : value * Self.kgPerPound
    }

    /// Centimeters or inches.
    func fromCm(_ cm: Double) -> Double {
        self == .metric ? cm : cm / Self.cmPerInch
    }

    func toCm(_ value: Double) -> Double {
        self == .metric ? value : value * Self.cmPerInch
    }

    /// Splits a weight into whole pounds and ounces, rounding the ounces to `ounceDigits` decimals
    /// first so 9 lb 15.99 oz becomes 10 lb 0 oz rather than 9 lb 16 oz.
    static func poundsAndOunces(kg: Double, ounceDigits: Int = 0) -> (pounds: Int, ounces: Double) {
        let scale = pow(10, Double(ounceDigits))
        let totalOunces = (kg / kgPerPound * 16 * scale).rounded() / scale
        let pounds = Int(totalOunces / 16)
        return (pounds, totalOunces - Double(pounds) * 16)
    }

    static func kg(pounds: Double, ounces: Double) -> Double {
        (pounds + ounces / 16) * kgPerPound
    }

    // MARK: Formatting

    /// "4.2 kg" or "9 lb 4 oz".
    func formatWeight(kg: Double) -> String {
        switch self {
        case .metric:
            return Self.kilograms(kg.formatted(.number.precision(.fractionLength(0...2))))
        case .imperial:
            let parts = Self.poundsAndOunces(kg: kg)
            return String(localized: "\(parts.pounds) lb \(Int(parts.ounces)) oz", comment: "A weight in pounds and ounces, e.g. “9 lb 4 oz”")
        }
    }

    /// "52.5 cm" or "20.7 in".
    func formatLength(cm: Double) -> String {
        length(fromCm(cm).formatted(.number.precision(.fractionLength(0...1))))
    }

    /// A signed change in weight: "+180 g", "+1.2 kg" or "+0.4 lb".
    func formatWeightChange(kg: Double) -> String {
        switch self {
        case .metric:
            let grams = (kg * 1000).rounded()
            if abs(grams) < 1000 {
                guard let number = Self.signed(grams, digits: 0) else { return Self.noChange }
                return String(localized: "\(number) g", comment: "A change in weight in grams, e.g. “+180 g”")
            }
            guard let number = Self.signed(kg, digits: 2) else { return Self.noChange }
            return Self.kilograms(number)
        case .imperial:
            guard let number = Self.signed(fromKg(kg), digits: 1) else { return Self.noChange }
            return String(localized: "\(number) lb", comment: "A weight in pounds, e.g. “+0.4 lb”")
        }
    }

    /// A signed change in length: "+1.5 cm" or "+0.6 in".
    func formatLengthChange(cm: Double) -> String {
        guard let number = Self.signed(fromCm(cm), digits: 1) else { return Self.noChange }
        return length(number)
    }

    /// "4.2 kg", from a number already formatted.
    private static func kilograms(_ number: String) -> String {
        String(localized: "\(number) kg", comment: "A weight in kilograms, e.g. “4.2 kg” or “+1.2 kg”")
    }

    /// "52.5 cm" or "20.7 in", from a number already formatted.
    private func length(_ number: String) -> String {
        switch self {
        case .metric: return String(localized: "\(number) cm", comment: "A length in centimeters, e.g. “52.5 cm” or “+1.5 cm”")
        case .imperial: return String(localized: "\(number) in", comment: "A length in inches, e.g. “20.7 in” or “+0.6 in”")
        }
    }

    private static var noChange: String {
        String(localized: "No change", comment: "A growth measurement the same as the last one")
    }

    /// "+0.4", "−20", or `nil` when it rounds to zero.
    private static func signed(_ value: Double, digits: Int) -> String? {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(0...digits)))
        let scale = pow(10, Double(digits))
        let rounded = (value * scale).rounded() / scale
        if rounded == 0 { return nil }
        return "\(rounded > 0 ? "+" : "−")\(magnitude)"
    }
}
