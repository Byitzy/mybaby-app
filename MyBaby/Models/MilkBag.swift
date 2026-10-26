import CoreData
import Foundation

/// A bag (or bottle) of pumped breast milk in the stash.
///
/// Belongs to a baby like every other entry, so a shared log shares the stash too. A bag stays in
/// the database after it's used or discarded; the stash only shows the ones still there.
@objc(MilkBag)
final class MilkBag: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var amountMLNumber: NSNumber?
    @NSManaged var pumpedDate: Date
    /// `MilkStorage`.
    @NSManaged var storageRaw: String
    /// When it went into the freezer.
    @NSManaged var frozenDate: Date?
    /// When frozen milk was moved to the fridge to thaw. Thawed milk is never refrozen.
    @NSManaged var thawedDate: Date?
    @NSManaged var usedDate: Date?
    @NSManaged var discarded: Bool
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    /// A new bag for the current baby, saved in the baby's store.
    @discardableResult
    static func create(
        amountML: Double?, pumpedDate: Date = .now, storage: MilkStorage = .fridge, in context: NSManagedObjectContext
    ) -> MilkBag {
        let bag = MilkBag(context: context)
        bag.uuid = UUID()
        bag.amountML = amountML
        bag.pumpedDate = pumpedDate
        bag.notes = ""
        bag.storage = storage
        if storage == .freezer { bag.frozenDate = .now }
        Baby.attach(bag, in: context) { bag.baby = $0 }
        return bag
    }

    /// Bags still in the stash (not used or thrown away), oldest first.
    static func inStash() -> NSFetchRequest<MilkBag> {
        let request = NSFetchRequest<MilkBag>(entityName: "MilkBag")
        request.predicate = NSPredicate(format: "usedDate == nil AND discarded == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "pumpedDate", ascending: true)]
        return request
    }

    var amountML: Double? {
        get { amountMLNumber?.doubleValue }
        set { amountMLNumber = newValue.map { NSNumber(value: $0) } }
    }

    var storage: MilkStorage {
        get { MilkStorage(rawValue: storageRaw) ?? .fridge }
        set { storageRaw = newValue.rawValue }
    }

    var isThawed: Bool { thawedDate != nil }

    /// Where the bag can go from where it is. Frozen milk can only thaw in the fridge, and thawed
    /// milk stays put: it's never refrozen.
    var possibleMoves: [MilkStorage] {
        if isThawed { return [] }
        switch storage {
        case .room: return [.fridge, .freezer]
        case .fridge: return [.freezer]
        case .freezer: return [.fridge]
        }
    }

    /// Moves the bag, noting when it was frozen, or when it was thawed if it leaves the freezer.
    func move(to newStorage: MilkStorage, at date: Date = .now) {
        guard newStorage != storage, possibleMoves.contains(newStorage) else { return }
        if storage == .freezer { thawedDate = date }
        if newStorage == .freezer { frozenDate = date }
        storage = newStorage
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var milkBags: NSSet?
}

enum MilkStorage: String, CaseIterable, Identifiable, Codable, Sendable {
    case room, fridge, freezer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: return String(localized: "Room temperature", comment: "Where a bag of breast milk is kept")
        case .fridge: return String(localized: "Fridge", comment: "Where a bag of breast milk is kept")
        case .freezer: return String(localized: "Freezer", comment: "Where a bag of breast milk is kept")
        }
    }

    var shortTitle: String {
        switch self {
        case .room: return String(localized: "Room", comment: "Short for room temperature, where a bag of breast milk is kept")
        case .fridge: return String(localized: "Fridge", comment: "Where a bag of breast milk is kept")
        case .freezer: return String(localized: "Freezer", comment: "Where a bag of breast milk is kept")
        }
    }

    var systemImage: String {
        switch self {
        case .room: return "house"
        case .fridge: return "refrigerator"
        case .freezer: return "snowflake"
        }
    }
}

/// How long breast milk keeps, from the CDC's guidelines for storing breast milk for healthy,
/// full-term babies: room temperature up to 4 hours, fridge up to 4 days, freezer best within
/// 6 months and acceptable up to 12 months; thawed milk within 24 hours in the fridge, never refrozen.
enum MilkStorageGuide {
    static let roomHours = 4
    static let fridgeDays = 4
    static let freezerBestMonths = 6
    static let freezerMaxMonths = 12
    static let thawedHours = 24

    /// The footer shown with the stash and the pumping editor.
    static let summary = String(localized: "Storage times from the CDC: room temperature up to 4 hours, fridge up to 4 days, freezer best within 6 months and acceptable up to 12 months. Thawed milk: use within 24 hours in the fridge, and never refreeze it. Ask your pediatrician if your baby was born early or is in the hospital.")
}

/// How close a bag is to its use-by date. Every case has its own words, not just a color.
enum MilkFreshness {
    case fresh
    /// Close to its use-by date.
    case useSoon
    /// Frozen longer than the best-by 6 months, but within the acceptable 12.
    case pastBest
    case expired
}

extension MilkBag {
    /// When the CDC guidance says to use it by. For frozen milk this is the 6-month "best" date.
    /// Times count from when it was pumped, except thawed milk, which counts from thawing.
    var useBy: Date {
        let calendar = Calendar.current
        if let thawedDate {
            return thawedDate.addingTimeInterval(Double(MilkStorageGuide.thawedHours) * 3600)
        }
        switch storage {
        case .room:
            return pumpedDate.addingTimeInterval(Double(MilkStorageGuide.roomHours) * 3600)
        case .fridge:
            return calendar.date(byAdding: .day, value: MilkStorageGuide.fridgeDays, to: pumpedDate) ?? pumpedDate
        case .freezer:
            return calendar.date(byAdding: .month, value: MilkStorageGuide.freezerBestMonths, to: pumpedDate) ?? pumpedDate
        }
    }

    /// The last acceptable date: 12 months for frozen milk, otherwise the use-by date.
    var acceptableUntil: Date {
        guard storage == .freezer, thawedDate == nil else { return useBy }
        return Calendar.current.date(byAdding: .month, value: MilkStorageGuide.freezerMaxMonths, to: pumpedDate) ?? useBy
    }

    /// How long before the use-by date to start saying "use soon".
    private var warningWindow: TimeInterval {
        if isThawed { return 6 * 3600 }
        switch storage {
        case .room: return 3600
        case .fridge: return 24 * 3600
        case .freezer: return 30 * 24 * 3600
        }
    }

    func freshness(now: Date = .now) -> MilkFreshness {
        if now >= acceptableUntil { return .expired }
        if now >= useBy { return .pastBest }
        if now >= useBy.addingTimeInterval(-warningWindow) { return .useSoon }
        return .fresh
    }

    /// "Use by Oct 28, 9:14 AM", "Use soon · by 1:30 PM", "Past use-by date".
    func useByText(now: Date = .now) -> String {
        let date = Self.formatted(useBy, storage: storage, thawed: isThawed)
        switch freshness(now: now) {
        case .fresh: return String(localized: "Use by \(date)", comment: "A bag of breast milk's use-by date or time, e.g. “Use by Oct 28, 9:14 AM” or “Use by 1:30 PM”")
        case .useSoon: return String(localized: "Use soon · by \(date)", comment: "A bag of breast milk close to its use-by date or time")
        case .pastBest:
            let until = acceptableUntil.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "Past the 6-month best date · OK until \(until)", comment: "Frozen breast milk past its best date but still acceptable until a date")
        case .expired: return String(localized: "Past its use-by date", comment: "A bag of breast milk")
        }
    }

    /// Frozen milk shows a date; everything else shows the time too, since it only keeps hours or days.
    private static func formatted(_ date: Date, storage: MilkStorage, thawed: Bool) -> String {
        if storage == .freezer && !thawed { return date.formatted(date: .abbreviated, time: .omitted) }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
