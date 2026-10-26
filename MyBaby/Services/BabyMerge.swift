import CoreData
import Foundation

/// Finding and merging two copies of the same baby.
///
/// They happen when the same Apple ID used MyBaby on two devices before turning on sync, or
/// restored from iCloud on a phone that already had a log: each device set up its own baby, and
/// iCloud brings both together, each with part of the log. The parent is asked before anything is
/// merged (see `DuplicateBabies`), and merging keeps every entry from both.
///
/// Only babies in the same store can be merged. Core Data can't link an entry in one store to a
/// baby in another, so a baby the partner shared (in the shared store) is never a duplicate.
enum BabyMerge {
    /// What finding duplicates looks at, so it works without Core Data.
    struct Candidate: Equatable {
        let id: UUID
        let name: String
        let birthDate: Date?
        let createdAt: Date
        /// Which store the baby is in. Only babies in the same store are compared.
        let store: String
    }

    /// Two copies of one baby: the one to keep (created first) and the one merged into it.
    struct Pair: Hashable {
        let keep: UUID
        let merge: UUID

        /// The same whichever way round, for remembering "Not now".
        var key: String {
            [keep.uuidString, merge.uuidString].sorted().joined(separator: "+")
        }

        func contains(_ id: UUID) -> Bool { keep == id || merge == id }
    }

    /// How names are compared: trimmed and ignoring case, so "Mavie " matches "mavie".
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether two babies are probably the same baby: in the same store, with the same name and
    /// the same birthday (or no birthday on either). Babies without a name are never matched.
    static func isLikelySame(_ a: Candidate, _ b: Candidate, calendar: Calendar = .current) -> Bool {
        guard a.id != b.id, a.store == b.store else { return false }
        let name = normalizedName(a.name)
        guard !name.isEmpty, name == normalizedName(b.name) else { return false }
        switch (a.birthDate, b.birthDate) {
        case (nil, nil):
            return true
        case let (first?, second?):
            return calendar.isDate(first, inSameDayAs: second)
        default:
            return false
        }
    }

    /// Every likely duplicate, each paired with the oldest copy of that baby, which is kept.
    /// Three copies give two pairs, both keeping the oldest.
    ///
    /// Examples (same store unless noted; "1 May" means any time that day):
    /// - "Mavie", 1 May, created Mon + "mavie ", 1 May, created Tue → one pair, keep Monday's.
    /// - "Mavie", no birthday + "Mavie", no birthday → one pair.
    /// - "Mavie", 1 May + "Mavie", no birthday → none.
    /// - "Mavie", 1 May + "Mavie", 2 May → none (twins have different names; a different
    ///   birthday is a different baby).
    /// - "Mavie" in the private store + "Mavie" in the shared store → none.
    /// - "Mavie" created Mon, Tue and Wed, all 1 May → (keep Mon, merge Tue), (keep Mon, merge Wed).
    /// - "" + "" → none.
    static func duplicates(among candidates: [Candidate], calendar: Calendar = .current) -> [Pair] {
        // Oldest first, and the same order every time when two were created at the same moment.
        let oldestFirst = candidates.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        var pairs: [Pair] = []
        for (index, candidate) in oldestFirst.enumerated() {
            // The earliest match is always a first copy itself, since matching is transitive.
            if let original = oldestFirst[..<index].first(where: { isLikelySame($0, candidate, calendar: calendar) }) {
                pairs.append(Pair(keep: original.id, merge: candidate.id))
            }
        }
        return pairs
    }

    // MARK: Merging

    /// Moves everything logged for `duplicate` to `keeper`, and fills in what the keeper's profile
    /// is missing. Both must be in the same store. Doesn't delete the duplicate or save.
    ///
    /// Entries aren't de-duplicated: two devices logging the same hour are two different events.
    /// The exceptions are medicine schedules, one per medicine name, and allergies, one per allergen.
    static func move(_ duplicate: Baby, into keeper: Baby) {
        guard let context = keeper.managedObjectContext, duplicate != keeper else { return }

        // The same medicine set up on both devices: keep the keeper's schedule, filling in what
        // it doesn't have from the other one.
        var schedules = (keeper.medicineSchedules?.allObjects as? [MedicineSchedule]) ?? []
        for schedule in (duplicate.medicineSchedules?.allObjects as? [MedicineSchedule]) ?? [] {
            guard let existing = schedules.matching(schedule.name) else {
                schedules.append(schedule)
                continue
            }
            if existing.minHoursBetweenNumber == nil {
                existing.minHoursBetweenNumber = schedule.minHoursBetweenNumber
            }
            if existing.maxDosesPer24hNumber == nil {
                existing.maxDosesPer24hNumber = schedule.maxDosesPer24hNumber
            }
            if existing.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.notes = schedule.notes
            }
            if schedule.notifiesWhenAllowed {
                existing.notifiesWhenAllowed = true
                schedule.notifiesWhenAllowed = false
            }
            context.delete(schedule)
        }

        // The same allergy listed on both devices: keep the keeper's, filling in what it's missing
        // and moving the other one's reactions to it.
        var allergies = (keeper.allergies?.allObjects as? [Allergy]) ?? []
        for allergy in (duplicate.allergies?.allObjects as? [Allergy]) ?? [] where !allergy.isDeleted {
            guard let existing = allergies.first(where: { $0.isSameAllergen(as: allergy) }) else {
                allergies.append(allergy)
                continue
            }
            existing.absorb(allergy)
            context.delete(allergy)
        }

        // Every kind of entry, read from the model so a new one is never left behind. Milestone
        // photos belong to their milestone (and diary photos to their entry), so they come along with it.
        for (name, relationship) in duplicate.entity.relationshipsByName where relationship.isToMany {
            guard let inverse = relationship.inverseRelationship?.name,
                  let entries = (duplicate.value(forKey: name) as? NSSet)?.allObjects
            else { continue }
            for case let entry as NSManagedObject in entries where !entry.isDeleted {
                entry.setValue(keeper, forKey: inverse)
            }
        }

        if keeper.birthDate == nil {
            keeper.birthDate = duplicate.birthDate
        }
        if keeper.sexRaw == nil {
            keeper.sexRaw = duplicate.sexRaw
        }
        if keeper.nightPlanData?.isEmpty ?? true {
            keeper.nightPlanData = duplicate.nightPlanData
        }
        // Questions for the next checkup from both, each asked once.
        let questions = keeper.pendingQuestionList
        let extra = duplicate.pendingQuestionList.filter { question in
            !questions.contains { $0.text.caseInsensitiveCompare(question.text) == .orderedSame }
        }
        if !extra.isEmpty {
            keeper.pendingQuestionList = questions + extra
        }
        // Settles the moved entries on the keeper's side, so deleting the duplicate next can't take
        // them with it.
        context.processPendingChanges()
    }
}

/// Likely duplicate babies on this iPhone, and the parent's answer to merging them.
///
/// Checked after sync is turned on, after a restore from iCloud, when an iCloud download finishes
/// and when More opens. Settings shows the first pair the parent hasn't said "Not now" to; a baby's
/// profile offers merging whenever that baby has a copy.
@MainActor
final class DuplicateBabies: ObservableObject {
    static let shared = DuplicateBabies()

    /// Two copies of a baby to offer merging.
    struct Suggestion: Equatable {
        let pair: BabyMerge.Pair
        let keep: NSManagedObjectID
        let merge: NSManagedObjectID
        let name: String
    }

    /// The pair Settings asks about, if any.
    @Published private(set) var suggestion: Suggestion?

    /// Pairs the parent said "Not now" to, by `BabyMerge.Pair.key`. Only on this device.
    private static let dismissedKey = "dismissedDuplicateBabies"

    /// What the parent is asked.
    static func question(for name: String) -> String {
        String(localized: "\(name) appears twice, probably from another iPhone or iPad. Merge them into one? Everything logged for both is kept.")
    }

    /// Looks for duplicates again. Cheap: one fetch of the babies.
    func check() {
        let babies = (try? PersistenceController.shared.viewContext.fetch(Baby.fetchAll())) ?? []
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
        let next = Self.pairs(in: babies)
            .first { !dismissed.contains($0.pair.key) }
            .map { Suggestion(pair: $0.pair, keep: $0.keep.objectID, merge: $0.merge.objectID, name: $0.keep.displayName) }
        if next != suggestion {
            suggestion = next
        }
    }

    /// "Not now": this pair isn't asked about again. Merging is still offered in the baby's profile.
    func notNow() {
        guard let suggestion else { return }
        var dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
        if !dismissed.contains(suggestion.pair.key) {
            dismissed.append(suggestion.pair.key)
            UserDefaults.standard.set(dismissed, forKey: Self.dismissedKey)
        }
        check()
    }

    /// Merges the suggested pair.
    func merge() {
        guard let suggestion else { return }
        let context = PersistenceController.shared.viewContext
        guard let keeper = try? context.existingObject(with: suggestion.keep) as? Baby,
              let duplicate = try? context.existingObject(with: suggestion.merge) as? Baby
        else {
            check()
            return
        }
        self.suggestion = nil
        Task { await PersistenceController.shared.mergeBabies(keep: keeper, merge: duplicate) }
    }

    /// The copy of `baby` and which of the two is kept, whether or not "Not now" was tapped.
    static func match(for baby: Baby, among babies: [Baby]) -> (keep: Baby, merge: Baby)? {
        guard let id = baby.uuid,
              let found = pairs(in: babies).first(where: { $0.pair.contains(id) })
        else { return nil }
        return (found.keep, found.merge)
    }

    /// The likely duplicates among `babies`. Babies the partner shared, and any not saved yet or
    /// without an id, are left out.
    static func pairs(in babies: [Baby]) -> [(pair: BabyMerge.Pair, keep: Baby, merge: Baby)] {
        let persistence = PersistenceController.shared
        var byID: [UUID: Baby] = [:]
        var candidates: [BabyMerge.Candidate] = []
        for baby in babies {
            guard let id = baby.uuid, byID[id] == nil,
                  !baby.isDeleted, !baby.objectID.isTemporaryID,
                  !persistence.isJoined(baby),
                  let store = baby.objectID.persistentStore
            else { continue }
            byID[id] = baby
            candidates.append(BabyMerge.Candidate(
                id: id,
                name: baby.name,
                birthDate: baby.birthDate,
                createdAt: baby.createdAt,
                store: store.identifier ?? store.url?.absoluteString ?? ""
            ))
        }
        return BabyMerge.duplicates(among: candidates).compactMap { pair in
            guard let keep = byID[pair.keep], let merge = byID[pair.merge] else { return nil }
            return (pair: pair, keep: keep, merge: merge)
        }
    }
}
