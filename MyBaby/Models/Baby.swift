import CoreData
import Foundation

/// The baby whose care is being logged. Every entry belongs to a baby, so sharing the baby
/// through iCloud shares the whole log with the other parent.
///
/// There can be more than one (twins, siblings). The app shows one at a time, picked with the
/// switcher on Today or in More › Babies.
@objc(Baby)
final class Baby: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    /// The day of birth, with the time when `hasBirthTime` (otherwise the time part means nothing).
    @NSManaged var birthDate: Date?
    /// Whether the parent entered the time of birth too.
    @NSManaged var hasBirthTime: Bool
    /// Length of pregnancy at birth, e.g. 34 weeks + 2 days. `nil` when not entered; 40 for full term.
    @NSManaged var gestationWeeksNumber: NSNumber?
    @NSManaged var gestationDaysNumber: NSNumber?
    @NSManaged var createdAt: Date
    /// The shared parts of the night plan, so both parents follow the same schedule.
    @NSManaged var nightPlanData: Data?
    /// "female" or "male", only used to pick the WHO growth chart. `nil` until a parent sets it.
    @NSManaged var sexRaw: String?
    /// Questions saved for the next checkup while none is scheduled, one per line (see `VisitQuestions`).
    /// They move into the next appointment that's added.
    @NSManaged var pendingQuestions: String
    @NSManaged var activities: NSSet?
    @NSManaged var vaccines: NSSet?
    @NSManaged var appointments: NSSet?

    static func fetchAll() -> NSFetchRequest<Baby> {
        let request = NSFetchRequest<Baby>(entityName: "Baby")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    /// The baby the app shows. See `preferred(from:selectedID:)`.
    static func current(in context: NSManagedObjectContext) -> Baby? {
        preferred(from: (try? context.fetch(fetchAll())) ?? [])
    }

    /// The baby picked in the switcher, while it's still here. Otherwise the one the partner shared
    /// (this parent may have set up their own before joining), and otherwise the oldest.
    static func preferred(
        from babies: [Baby],
        selectedID: String? = UserDefaults.shared.string(forKey: SettingsKey.selectedBaby)
    ) -> Baby? {
        if let selectedID, let selected = babies.first(where: { $0.uuid?.uuidString == selectedID }) {
            return selected
        }
        let persistence = PersistenceController.shared
        let shared = babies.filter { persistence.isJoined($0) }
        return (shared.isEmpty ? babies : shared).min { $0.createdAt < $1.createdAt }
    }

    /// Shows `baby` everywhere in the app.
    static func select(_ baby: Baby) {
        if baby.uuid == nil {
            baby.uuid = UUID()
            baby.managedObjectContext?.saveIfChanged()
        }
        UserDefaults.shared.set(baby.uuid?.uuidString, forKey: SettingsKey.selectedBaby)
    }

    /// Links a newly inserted entry to the current baby and saves it in the baby's store.
    /// Entries must live in the same store as the baby: the private store for the parent who
    /// created the baby, the shared store for the parent who was invited.
    static func attach(_ object: NSManagedObject, in context: NSManagedObjectContext, link: (Baby) -> Void) {
        guard let baby = current(in: context) else { return }
        if let store = baby.objectID.persistentStore {
            context.assign(object, to: store)
        }
        link(baby)
    }

    /// `request` narrowed to this baby's entries, on top of its own conditions.
    /// Every fetch that shows entries goes through this, so each baby has their own log.
    func entries<Entry: NSFetchRequestResult>(_ request: NSFetchRequest<Entry>) -> NSFetchRequest<Entry> {
        let mine = NSPredicate(format: "baby == %@", self)
        if let existing = request.predicate {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [existing, mine])
        } else {
            request.predicate = mine
        }
        return request
    }

    var hasEntries: Bool {
        (activities?.count ?? 0) + (vaccines?.count ?? 0) + (appointments?.count ?? 0)
            + (growthEntries?.count ?? 0) + (milkBags?.count ?? 0) + (medicineSchedules?.count ?? 0)
            + (milestones?.count ?? 0) + (trackingPeriods?.count ?? 0) + (diaryEntries?.count ?? 0)
            + (allergies?.count ?? 0) + (allergyReactions?.count ?? 0) > 0
    }

    /// Which WHO growth standard applies. `nil` means not set, and percentiles aren't shown.
    var sex: BabySex? {
        get { sexRaw.flatMap(BabySex.init(rawValue:)) }
        set { sexRaw = newValue?.rawValue }
    }

    /// The name, or "Baby" before one is set.
    var displayName: String {
        name.isEmpty ? String(localized: "Baby", comment: "A baby's name before one is set") : name
    }

    /// The name with only letters and digits, for file names.
    var fileSafeName: String {
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return safe.isEmpty ? String(localized: "Baby", comment: "A baby's name before one is set") : safe
    }
}
