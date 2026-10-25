import CoreData
import Foundation

/// Something the baby is allergic to, or might be: a food, a medicine, something in the air or
/// something that touches the skin.
///
/// Belongs to the baby like every other entry, so it syncs and is shared with the partner, and
/// view-only family can read it. Parents write it down as they learn it; MyBaby never decides
/// whether something is an allergy.
@objc(Allergy)
final class Allergy: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    /// The `CommonAllergen` id when it was picked from the common list ("peanut"), so solids
    /// tagged with that allergen match it whatever the name says. `nil` for anything typed in.
    @NSManaged var allergenRaw: String?
    @NSManaged var categoryRaw: String
    @NSManaged var statusRaw: String
    @NSManaged var severityRaw: String
    /// The reactions seen, in the parent's own words ("hives around the mouth").
    @NSManaged var reactionsSeen: String
    @NSManaged var diagnosedBy: String
    @NSManaged var diagnosedDate: Date?
    @NSManaged var hasAutoInjector: Bool
    /// Where the epinephrine auto-injector is kept ("diaper bag, front pocket").
    @NSManaged var autoInjectorLocation: String
    @NSManaged var notes: String
    @NSManaged var createdAt: Date
    @NSManaged var reactions: NSSet?
    @NSManaged var baby: Baby?

    /// A new allergy for `baby`, saved in the baby's store so it's shared with the same people.
    @discardableResult
    static func create(for baby: Baby, in context: NSManagedObjectContext) -> Allergy {
        let allergy = Allergy(context: context)
        allergy.uuid = UUID()
        allergy.createdAt = .now
        allergy.name = ""
        allergy.category = .food
        allergy.status = .suspected
        allergy.severity = .mild
        allergy.reactionsSeen = ""
        allergy.diagnosedBy = ""
        allergy.autoInjectorLocation = ""
        allergy.notes = ""
        if let store = baby.objectID.persistentStore {
            context.assign(allergy, to: store)
        }
        allergy.baby = baby
        return allergy
    }

    /// Every allergy, oldest first. Use `sortedForDisplay()` for the order the screens show.
    static func fetchAll() -> NSFetchRequest<Allergy> {
        let request = NSFetchRequest<Allergy>(entityName: "Allergy")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    var category: AllergyCategory {
        get { AllergyCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: AllergyStatus {
        get { AllergyStatus(rawValue: statusRaw) ?? .suspected }
        set { statusRaw = newValue.rawValue }
    }

    var severity: AllergySeverity {
        get { AllergySeverity(rawValue: severityRaw) ?? .mild }
        set { severityRaw = newValue.rawValue }
    }

    /// The common allergen this is, when it was picked from the list.
    var commonAllergen: CommonAllergen? {
        allergenRaw.flatMap(CommonAllergen.with(id:))
    }

    /// The name, or "Allergy" before one is typed.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Allergy" : trimmed
    }

    /// Confirmed or suspected. Outgrown allergies stay on the list but don't warn.
    var isActive: Bool { status != .outgrown }

    /// "Peanut (confirmed, severe)", for the baby's profile.
    var shortSummary: String {
        "\(displayName) (\(status.title.lowercased()), \(severity.title.lowercased()))"
    }

    /// "Confirmed · Severe".
    var statusAndSeverity: String {
        "\(status.title) · \(severity.title)"
    }

    /// Which reactions are linked to it, newest first.
    var reactionList: [AllergyReaction] {
        ((reactions?.allObjects as? [AllergyReaction]) ?? [])
            .filter { !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }

    /// Whether `other` is the same allergen: the same common allergen, or the same name ignoring case.
    func isSameAllergen(as other: Allergy) -> Bool {
        if let mine = allergenRaw, let theirs = other.allergenRaw {
            return mine == theirs
        }
        return AllergyMatch.key(displayName) == AllergyMatch.key(other.displayName)
    }

    /// Fills in what this allergy is missing from `other`, the same allergen entered on another
    /// device, and moves its reactions here. Keeps the more certain status (confirmed over
    /// suspected) and the higher severity. Doesn't delete `other`.
    func absorb(_ other: Allergy) {
        if allergenRaw == nil { allergenRaw = other.allergenRaw }
        if other.status == .confirmed && status == .suspected { status = .confirmed }
        if other.severity > severity { severity = other.severity }
        if reactionsSeen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reactionsSeen = other.reactionsSeen }
        if diagnosedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { diagnosedBy = other.diagnosedBy }
        if diagnosedDate == nil { diagnosedDate = other.diagnosedDate }
        if other.hasAutoInjector { hasAutoInjector = true }
        if autoInjectorLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            autoInjectorLocation = other.autoInjectorLocation
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes = other.notes }
        for case let reaction as AllergyReaction in (other.reactions?.allObjects ?? []) where !reaction.isDeleted {
            reaction.allergy = self
        }
    }
}

extension Sequence where Element == Allergy {
    /// Confirmed first, then suspected, then outgrown; the most severe first within each; then by name.
    func sortedForDisplay() -> [Allergy] {
        filter { !$0.isDeleted }.sorted { a, b in
            if a.status.sortOrder != b.status.sortOrder { return a.status.sortOrder < b.status.sortOrder }
            if a.severity != b.severity { return a.severity > b.severity }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }
}

// MARK: - Reactions

/// A reaction the baby had: when, what they had before it, the symptoms, how bad it was, what
/// the parents did, and optionally a photo of a rash. It can be linked to an allergy.
@objc(AllergyReaction)
final class AllergyReaction: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date
    /// What the baby had before it, in the parent's words.
    @NSManaged var food: String
    /// `ReactionSymptom` raw values, comma separated.
    @NSManaged var symptomsRaw: String?
    @NSManaged var severityRaw: String
    /// `ReactionAction` raw values, comma separated.
    @NSManaged var actionsRaw: String?
    @NSManaged var notes: String
    @NSManaged var createdAt: Date
    @NSManaged var allergy: Allergy?
    @NSManaged var photos: NSSet?
    @NSManaged var baby: Baby?

    /// A new reaction for `baby`, in the baby's store.
    @discardableResult
    static func create(for baby: Baby, in context: NSManagedObjectContext) -> AllergyReaction {
        let reaction = AllergyReaction(context: context)
        reaction.uuid = UUID()
        reaction.createdAt = .now
        reaction.date = .now
        reaction.food = ""
        reaction.severity = .mild
        reaction.notes = ""
        if let store = baby.objectID.persistentStore {
            context.assign(reaction, to: store)
        }
        reaction.baby = baby
        return reaction
    }

    /// Every reaction, newest first.
    static func fetchAll() -> NSFetchRequest<AllergyReaction> {
        let request = NSFetchRequest<AllergyReaction>(entityName: "AllergyReaction")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return request
    }

    var severity: AllergySeverity {
        get { AllergySeverity(rawValue: severityRaw) ?? .mild }
        set { severityRaw = newValue.rawValue }
    }

    /// The symptoms ticked, in the order the editor lists them.
    var symptoms: [ReactionSymptom] {
        get { ReactionSymptom.from(symptomsRaw) }
        set { symptomsRaw = newValue.isEmpty ? nil : newValue.map(\.rawValue).joined(separator: ",") }
    }

    /// What the parents did, in the order the editor lists it.
    var actions: [ReactionAction] {
        get { ReactionAction.from(actionsRaw) }
        set { actionsRaw = newValue.isEmpty ? nil : newValue.map(\.rawValue).joined(separator: ",") }
    }

    /// What they had, or "Reaction" when it wasn't written down.
    var displayTitle: String {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reaction" : trimmed
    }

    /// "Hives or rash, Vomiting".
    var symptomsText: String {
        symptoms.map(\.title).joined(separator: ", ")
    }

    /// Which photos there are, without loading any of them.
    var photoIDSet: Set<NSManagedObjectID> { Set(objectIDs(forRelationshipNamed: "photos")) }

    /// The photos' object IDs, oldest first, fetched as IDs so the image data stays on disk.
    func photoIDs() -> [NSManagedObjectID] {
        guard let context = managedObjectContext else { return [] }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "AllergyReactionPhoto")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "reaction == %@", self)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
}

/// A photo of a reaction, like a rash, as a small JPEG.
///
/// Kept inside the record exactly like `MilestonePhoto`: an external file would sync as a CKAsset,
/// which isn't covered by the end-to-end encryption the rest of the log uses. Downscaled by
/// `MilestoneImages`, without its location, one photo per record.
@objc(AllergyReactionPhoto)
final class AllergyReactionPhoto: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var createdAt: Date
    @NSManaged var reaction: AllergyReaction?

    /// Adds `jpeg` to `reaction`, in the same store as its baby so it's shared along with it.
    @discardableResult
    static func create(jpeg: Data, for reaction: AllergyReaction, createdAt: Date = .now, in context: NSManagedObjectContext) -> AllergyReactionPhoto {
        let photo = AllergyReactionPhoto(context: context)
        photo.uuid = UUID()
        photo.createdAt = createdAt
        photo.imageData = jpeg
        // A new reaction's own ID doesn't know its store until it's saved; its baby's does.
        if let store = reaction.baby?.objectID.persistentStore {
            context.assign(photo, to: store)
        }
        photo.reaction = reaction
        return photo
    }
}

// MARK: - Choices

/// What kind of thing the baby reacts to.
enum AllergyCategory: String, CaseIterable, Identifiable {
    case food, medicine, environment, skinContact, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Food"
        case .medicine: return "Medicine"
        case .environment: return "Environment"
        case .skinContact: return "Skin contact"
        case .other: return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .food: return "🍽️"
        case .medicine: return "💊"
        case .environment: return "🌿"
        case .skinContact: return "🖐️"
        case .other: return "📝"
        }
    }
}

/// How sure the parents are, in their own words: seen but not tested, confirmed by a doctor, or gone.
enum AllergyStatus: String, CaseIterable, Identifiable {
    case suspected, confirmed, outgrown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suspected: return "Suspected"
        case .confirmed: return "Confirmed"
        case .outgrown: return "Outgrown"
        }
    }

    /// Confirmed first on every list.
    var sortOrder: Int {
        switch self {
        case .confirmed: return 0
        case .suspected: return 1
        case .outgrown: return 2
        }
    }
}

/// How bad an allergy or a reaction is, as the parents describe it.
enum AllergySeverity: String, CaseIterable, Identifiable, Comparable {
    case mild, moderate, severe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    private var rank: Int {
        switch self {
        case .mild: return 0
        case .moderate: return 1
        case .severe: return 2
        }
    }

    static func < (lhs: AllergySeverity, rhs: AllergySeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The symptoms checklist in the reaction editor.
enum ReactionSymptom: String, CaseIterable, Identifiable {
    case hivesRash, swelling, vomiting, diarrhea, coughingWheezing, troubleBreathing
    case sleepiness, fussiness, eczemaFlare, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hivesRash: return "Hives or rash"
        case .swelling: return "Swelling"
        case .vomiting: return "Vomiting"
        case .diarrhea: return "Diarrhea"
        case .coughingWheezing: return "Coughing or wheezing"
        case .troubleBreathing: return "Trouble breathing"
        case .sleepiness: return "Unusual sleepiness"
        case .fussiness: return "Fussiness"
        case .eczemaFlare: return "Eczema flare"
        case .other: return "Other"
        }
    }

    /// Ticking one of these shows the emergency banner at the top of the reaction editor.
    var showsEmergencyBanner: Bool {
        self == .troubleBreathing || self == .swelling
    }

    /// The ones listed in `raw`, in the editor's order. Unknown values are skipped.
    static func from(_ raw: String?) -> [ReactionSymptom] {
        let values = Set((raw ?? "").split(separator: ",").map(String.init))
        return allCases.filter { values.contains($0.rawValue) }
    }
}

/// What the parents did about a reaction.
enum ReactionAction: String, CaseIterable, Identifiable {
    case antihistamine, epinephrine, calledDoctor, wentToER

    var id: String { rawValue }

    var title: String {
        switch self {
        case .antihistamine: return "Gave an antihistamine"
        case .epinephrine: return "Gave epinephrine"
        case .calledDoctor: return "Called the doctor"
        case .wentToER: return "Went to the ER"
        }
    }

    static func from(_ raw: String?) -> [ReactionAction] {
        let values = Set((raw ?? "").split(separator: ",").map(String.init))
        return allCases.filter { values.contains($0.rawValue) }
    }
}

/// An allergen that's one tap away when adding an allergy, and a chip in the solids editor (foods only).
///
/// The `id` is stored (in `Allergy.allergenRaw` and `Activity.allergensRaw`), so it never changes.
struct CommonAllergen: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let category: AllergyCategory
    /// Words that mean it in a food's description, lowercased and singular ("tahini" for sesame).
    /// Plain "milk" isn't one, since solids are often mixed with breast milk.
    let keywords: [String]

    /// The nine common food allergens, in the order the chips show them.
    static let foods: [CommonAllergen] = [
        CommonAllergen(id: "milk", name: "Milk", emoji: "🥛", category: .food,
                       keywords: ["cow's milk", "cows milk", "dairy", "cheese", "yogurt", "yoghurt"]),
        CommonAllergen(id: "egg", name: "Egg", emoji: "🥚", category: .food, keywords: ["egg"]),
        CommonAllergen(id: "peanut", name: "Peanut", emoji: "🥜", category: .food, keywords: ["peanut"]),
        CommonAllergen(id: "treeNuts", name: "Tree nuts", emoji: "🌰", category: .food,
                       keywords: ["tree nut", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia"]),
        CommonAllergen(id: "soy", name: "Soy", emoji: "🫘", category: .food, keywords: ["soy", "soya", "tofu", "edamame"]),
        CommonAllergen(id: "wheat", name: "Wheat", emoji: "🌾", category: .food, keywords: ["wheat"]),
        CommonAllergen(id: "fish", name: "Fish", emoji: "🐟", category: .food,
                       keywords: ["fish", "salmon", "tuna", "cod", "trout"]),
        CommonAllergen(id: "shellfish", name: "Shellfish", emoji: "🦐", category: .food,
                       keywords: ["shellfish", "shrimp", "prawn", "crab", "lobster"]),
        CommonAllergen(id: "sesame", name: "Sesame", emoji: "🌱", category: .food, keywords: ["sesame", "tahini"]),
    ]

    /// Medicines parents commonly list.
    static let medicines: [CommonAllergen] = [
        CommonAllergen(id: "amoxicillin", name: "Amoxicillin", emoji: "💊", category: .medicine, keywords: ["amoxicillin"]),
        CommonAllergen(id: "penicillin", name: "Penicillin", emoji: "💊", category: .medicine, keywords: ["penicillin"]),
    ]

    /// A few from the environment and skin contact.
    static let others: [CommonAllergen] = [
        CommonAllergen(id: "pollen", name: "Pollen", emoji: "🌼", category: .environment, keywords: ["pollen"]),
        CommonAllergen(id: "dustMites", name: "Dust mites", emoji: "🏠", category: .environment, keywords: ["dust mite"]),
        CommonAllergen(id: "petDander", name: "Pet dander", emoji: "🐾", category: .environment, keywords: ["pet dander"]),
        CommonAllergen(id: "latex", name: "Latex", emoji: "🧤", category: .skinContact, keywords: ["latex"]),
    ]

    static let all: [CommonAllergen] = foods + medicines + others

    static func with(id: String) -> CommonAllergen? {
        all.first { $0.id == id }
    }

    /// The common allergen with exactly this name, ignoring case ("peanut" → Peanut).
    static func named(_ name: String) -> CommonAllergen? {
        let key = AllergyMatch.key(name)
        guard !key.isEmpty else { return nil }
        return all.first { AllergyMatch.key($0.name) == key }
    }
}

// MARK: - Solids

// Allergens a solids log contained are tags on the `Activity` itself, so they sync with it and
// need no entity of their own.
extension Activity {
    /// `CommonAllergen` ids, comma separated, e.g. "egg,peanut". `nil` when none were tagged.
    @NSManaged var allergensRaw: String?

    /// The allergens tagged on a solids log, by id.
    var allergenIDs: Set<String> {
        get {
            Set((allergensRaw ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
        set {
            // Known ones in the chips' order, then any this version doesn't know, so none are lost.
            let known = CommonAllergen.all.map(\.id)
            let ordered = known.filter { newValue.contains($0) } + newValue.subtracting(known).sorted()
            allergensRaw = ordered.isEmpty ? nil : ordered.joined(separator: ",")
        }
    }

    /// The tagged allergens this version knows, in the chips' order.
    var allergens: [CommonAllergen] {
        let ids = allergenIDs
        return CommonAllergen.all.filter { ids.contains($0.id) }
    }
}

// MARK: - Baby

// Declared here rather than in Baby.swift, next to the entities they point to.
extension Baby {
    @NSManaged var allergies: NSSet?
    @NSManaged var allergyReactions: NSSet?

    /// Every allergy, in display order (see `sortedForDisplay()`), fetched now.
    func allergyList() -> [Allergy] {
        guard let context = managedObjectContext else { return [] }
        return ((try? context.fetch(entries(Allergy.fetchAll()))) ?? []).sortedForDisplay()
    }

    /// Reactions from `start` on (every one without it), newest first, fetched now.
    func allergyReactionList(since start: Date? = nil) -> [AllergyReaction] {
        guard let context = managedObjectContext else { return [] }
        let request = AllergyReaction.fetchAll()
        if let start {
            request.predicate = NSPredicate(format: "date >= %@", start as NSDate)
        }
        return (try? context.fetch(entries(request))) ?? []
    }

    /// Confirmed and suspected medicine allergies whose name matches `medicine` (see
    /// `AllergyMatch.medicineMatches`), fetched now.
    func medicineAllergies(matching medicine: String?) -> [Allergy] {
        AllergyMatch.medicineAllergies(matching: medicine ?? "", in: allergyList())
    }
}
