import CoreData
import Foundation

/// Something a parent logs for themselves in Parent care: a daily check-in, a medicine they took, or
/// a recovery note after giving birth.
///
/// **Private to that parent.** Unlike every other entry, a care entry has no baby: it's created in
/// this iPhone's private store and isn't linked to anything that's shared, so it never reaches the
/// partner's phone, the baby's exports or the PDF report. With iCloud sync on it's backed up to
/// their own iCloud, end-to-end encrypted, like the rest of the log.
@objc(CareEntry)
final class CareEntry: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var kindRaw: String
    @NSManaged var date: Date
    /// 1 (very low) to 5 (great), on check-ins.
    @NSManaged var moodScore: NSNumber?
    @NSManaged var sleepHoursNumber: NSNumber?
    @NSManaged var medicationName: String?
    @NSManaged var dosage: String?
    /// 0 (none) to 10 (worst).
    @NSManaged var painLevelNumber: NSNumber?
    @NSManaged var bleedingRaw: String?
    @NSManaged var notes: String

    /// A new entry in this iPhone's private store, linked to no baby, so it's never shared.
    @discardableResult
    static func create(_ kind: CareKind, date: Date = .now, in context: NSManagedObjectContext) -> CareEntry {
        let entry = CareEntry(context: context)
        entry.uuid = UUID()
        entry.kind = kind
        entry.date = date
        entry.notes = ""
        if let store = PersistenceController.shared.privateStore {
            context.assign(entry, to: store)
        }
        return entry
    }

    /// Every entry, or every entry of `kind`, newest first.
    static func fetchAll(_ kind: CareKind? = nil) -> NSFetchRequest<CareEntry> {
        let request = NSFetchRequest<CareEntry>(entityName: "CareEntry")
        if let kind {
            request.predicate = NSPredicate(format: "kindRaw == %@", kind.rawValue)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return request
    }

    var kind: CareKind {
        get { CareKind(rawValue: kindRaw) ?? .mood }
        set { kindRaw = newValue.rawValue }
    }

    var mood: Mood? {
        get { moodScore.flatMap { Mood(rawValue: $0.intValue) } }
        set { moodScore = newValue.map { NSNumber(value: $0.rawValue) } }
    }

    var sleepHours: Double? {
        get { sleepHoursNumber?.doubleValue }
        set { sleepHoursNumber = newValue.map { NSNumber(value: $0) } }
    }

    var painLevel: Int? {
        get { painLevelNumber?.intValue }
        set { painLevelNumber = newValue.map { NSNumber(value: $0) } }
    }

    var bleeding: Bleeding? {
        get { bleedingRaw.flatMap(Bleeding.init(rawValue:)) }
        set { bleedingRaw = newValue?.rawValue }
    }

    /// The medicine's name, or "Check-in" / "Recovery note".
    var title: String {
        guard kind == .medication else { return kind.title }
        let name = (medicationName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? kind.title : name
    }

    /// "😐 Okay · Slept 5h · Pain 3/10 · Light bleeding", leaving out anything not filled in.
    var detail: String {
        var parts: [String] = []
        if let mood { parts.append("\(mood.emoji) \(mood.title)") }
        if let sleepHours { parts.append("Slept \(Format.hours(sleepHours * 3600))") }
        if let dosage, !dosage.isEmpty { parts.append(dosage) }
        if let painLevel { parts.append("Pain \(painLevel)/10") }
        if let bleeding { parts.append(bleeding.title) }
        return parts.joined(separator: " · ")
    }
}

enum CareKind: String, CaseIterable, Identifiable {
    case mood, medication, recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return "Check-in"
        case .medication: return "Medicine"
        case .recovery: return "Recovery note"
        }
    }

    var emoji: String {
        switch self {
        case .mood: return "💛"
        case .medication: return "💊"
        case .recovery: return "🩹"
        }
    }
}

/// The five faces of the daily check-in. Just how you feel today, not a screening score.
enum Mood: Int, CaseIterable, Identifiable {
    case veryLow = 1, low, okay, good, great

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryLow: return "😢"
        case .low: return "😟"
        case .okay: return "😐"
        case .good: return "🙂"
        case .great: return "😄"
        }
    }

    var title: String {
        switch self {
        case .veryLow: return "Very low"
        case .low: return "Low"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        }
    }

    /// A hard day: the two lowest faces.
    var isLow: Bool { rawValue <= 2 }
}

enum Bleeding: String, CaseIterable, Identifiable {
    case none, light, moderate, heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No bleeding"
        case .light: return "Light bleeding"
        case .moderate: return "Moderate bleeding"
        case .heavy: return "Heavy bleeding"
        }
    }

    /// For the picker, where the row already says "Bleeding".
    var shortTitle: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }
}
