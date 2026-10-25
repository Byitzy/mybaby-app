import SwiftUI

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case feeding, diaper, sleep, bath, medication
    case pumping, temperature

    var id: String { rawValue }

    var title: String {
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

    var pluralTitle: String {
        switch self {
        case .feeding: return "Feedings"
        case .diaper: return "Diapers"
        case .sleep: return "Sleep"
        case .bath: return "Baths"
        case .medication: return "Medicine"
        case .pumping: return "Pumping"
        case .temperature: return "Temperatures"
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
        case .breast: return "Breastfeeding"
        case .breastMilkBottle: return "Bottle (breast milk)"
        case .formula: return "Bottle (formula)"
        case .solids: return "Solids"
        }
    }

    var shortTitle: String {
        switch self {
        case .breast: return "Breast"
        case .breastMilkBottle: return "Breast milk"
        case .formula: return "Formula"
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
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .mixed: return "Wet + dirty"
        case .dry: return "Dry"
        }
    }

    /// Words a tired parent would tap on.
    var quickTitle: String {
        switch self {
        case .wet: return "Pee"
        case .dirty: return "Poop"
        case .mixed: return "Pee + poop"
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

    var title: String { rawValue.capitalized }

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

    var title: String { rawValue.capitalized }
}
