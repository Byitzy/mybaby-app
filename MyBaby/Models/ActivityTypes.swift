import SwiftUI

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case feeding, diaper, sleep, bath, medication
    case pumping, temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feeding: return String(localized: "Feeding", comment: "Kind of log entry")
        case .diaper: return String(localized: "Diaper", comment: "Kind of log entry")
        case .sleep: return String(localized: "Sleep", comment: "Kind of log entry")
        case .bath: return String(localized: "Bath", comment: "Kind of log entry")
        case .medication: return String(localized: "Medicine", comment: "Kind of log entry, or of allergy")
        case .pumping: return String(localized: "Pumping", comment: "Kind of log entry: pumping breast milk")
        case .temperature: return String(localized: "Temperature", comment: "Kind of log entry")
        }
    }

    var pluralTitle: String {
        switch self {
        case .feeding: return String(localized: "Feedings", comment: "Plural kind of log entry, e.g. a filter or a report section")
        case .diaper: return String(localized: "Diapers", comment: "Plural kind of log entry")
        case .sleep: return String(localized: "Sleep", comment: "Kind of log entry")
        case .bath: return String(localized: "Baths", comment: "Plural kind of log entry")
        case .medication: return String(localized: "Medicine", comment: "Kind of log entry, or of allergy")
        case .pumping: return String(localized: "Pumping", comment: "Kind of log entry: pumping breast milk")
        case .temperature: return String(localized: "Temperatures", comment: "Plural kind of log entry")
        }
    }

    /// The CSV export's Category column, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .feeding: return "Feeding"
        case .diaper: return "Diaper"
        case .sleep: return "Sleep"
        case .bath: return "Bath"
        case .medication: return "Medicine"
        case .pumping: return "Pumping"
        case .temperature: return "Temperature"
        }
    }

    var emoji: String {
        switch self {
        case .feeding: return "🍼"
        case .diaper: return "🧷"
        case .sleep: return "😴"
        case .bath: return "🛁"
        case .medication: return "💊"
        case .pumping: return "🫙"
        case .temperature: return "🌡️"
        }
    }

    var color: Color {
        switch self {
        case .feeding: return .pink
        case .diaper: return .teal
        case .sleep: return .indigo
        case .bath: return .cyan
        case .medication: return .orange
        case .pumping: return .mint
        case .temperature: return .red
        }
    }
}

enum FeedingType: String, CaseIterable, Identifiable, Codable {
    case breast, breastMilkBottle, formula, solids

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breast: return String(localized: "Breastfeeding")
        case .breastMilkBottle: return String(localized: "Bottle (breast milk)")
        case .formula: return String(localized: "Bottle (formula)")
        case .solids: return String(localized: "Solids", comment: "Solid food, as a kind of feed")
        }
    }

    var shortTitle: String {
        switch self {
        case .breast: return String(localized: "Breast", comment: "Short for breastfeeding")
        case .breastMilkBottle: return String(localized: "Breast milk")
        case .formula: return String(localized: "Formula", comment: "Infant formula")
        case .solids: return String(localized: "Solids", comment: "Solid food, as a kind of feed")
        }
    }

    /// The CSV export's Type column for a feed, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .breast: return "Breastfeeding"
        case .breastMilkBottle: return "Bottle (breast milk)"
        case .formula: return "Bottle (formula)"
        case .solids: return "Solids"
        }
    }

    var emoji: String {
        switch self {
        case .breast: return "🤱"
        case .breastMilkBottle, .formula: return "🍼"
        case .solids: return "🥣"
        }
    }

    var isBottle: Bool {
        self == .breastMilkBottle || self == .formula
    }
}

enum DiaperType: String, CaseIterable, Identifiable, Codable {
    case wet, dirty, mixed, dry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wet: return String(localized: "Wet", comment: "A wet diaper")
        case .dirty: return String(localized: "Dirty", comment: "A dirty (poopy) diaper")
        case .mixed: return String(localized: "Wet + dirty", comment: "A diaper that's wet and dirty")
        case .dry: return String(localized: "Dry", comment: "A dry diaper")
        }
    }

    /// "Wet diaper", the title of a diaper change in the timeline. Whole phrases, since the word
    /// order differs between languages.
    var entryTitle: String {
        switch self {
        case .wet: return String(localized: "Wet diaper")
        case .dirty: return String(localized: "Dirty diaper")
        case .mixed: return String(localized: "Wet + dirty diaper")
        case .dry: return String(localized: "Dry diaper")
        }
    }

    /// Words a tired parent would tap on.
    var quickTitle: String {
        switch self {
        case .wet: return String(localized: "Pee", comment: "Quick log button for a wet diaper")
        case .dirty: return String(localized: "Poop", comment: "Quick log button for a dirty diaper")
        case .mixed: return String(localized: "Pee + poop", comment: "Quick log button for a wet and dirty diaper")
        case .dry: return String(localized: "Dry", comment: "A dry diaper")
        }
    }

    /// The CSV export's Type column for a diaper, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .mixed: return "Wet + dirty"
        case .dry: return "Dry"
        }
    }

    var emoji: String {
        switch self {
        case .wet: return "💧"
        case .dirty: return "💩"
        case .mixed: return "💩"
        case .dry: return "✨"
        }
    }
}

enum PoopColor: String, CaseIterable, Identifiable, Codable {
    case yellow, green, brown, black, red, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: return String(localized: "Yellow", comment: "Poop color")
        case .green: return String(localized: "Green", comment: "Poop color")
        case .brown: return String(localized: "Brown", comment: "Poop color, or brown noise")
        case .black: return String(localized: "Black", comment: "Poop color")
        case .red: return String(localized: "Red", comment: "Poop color")
        case .white: return String(localized: "White", comment: "Poop color, or white noise")
        }
    }

    /// The CSV export's Poop color column, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .yellow: return "🟡"
        case .green: return "🟢"
        case .brown: return "🟤"
        case .black: return "⚫️"
        case .red: return "🔴"
        case .white: return "⚪️"
        }
    }

    /// Colors pediatricians commonly ask parents to call about.
    var needsAttention: Bool {
        self == .black || self == .red || self == .white
    }
}

enum PoopConsistency: String, CaseIterable, Identifiable, Codable {
    case runny, seedy, soft, formed, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runny: return String(localized: "Runny", comment: "Poop consistency")
        case .seedy: return String(localized: "Seedy", comment: "Poop consistency")
        case .soft: return String(localized: "Soft", comment: "Poop consistency")
        case .formed: return String(localized: "Formed", comment: "Poop consistency")
        case .hard: return String(localized: "Hard", comment: "Poop consistency")
        }
    }

    /// The CSV export's Poop consistency column, which the importer reads back.
    // Not localized: CSV value, read back by the importer
    var exportName: String { rawValue.capitalized }
}
