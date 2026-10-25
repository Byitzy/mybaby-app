import CoreData
import Foundation

/// The dose timing a parent was given for one medicine: the least time between doses and,
/// optionally, the most doses in 24 hours.
///
/// The parent types these in as directed by their pediatrician. The app never suggests a dose or
/// an interval; it only works out when the next dose is allowed from what was entered. Matched to
/// doses by name, ignoring case (see `key(for:)`).
@objc(MedicineSchedule)
final class MedicineSchedule: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    @NSManaged var minHoursBetweenNumber: NSNumber?
    @NSManaged var maxDosesPer24hNumber: NSNumber?
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(name: String, in context: NSManagedObjectContext) -> MedicineSchedule {
        let schedule = MedicineSchedule(context: context)
        schedule.uuid = UUID()
        schedule.name = name
        schedule.notes = ""
        Baby.attach(schedule, in: context) { schedule.baby = $0 }
        return schedule
    }

    static func fetchAll() -> NSFetchRequest<MedicineSchedule> {
        let request = NSFetchRequest<MedicineSchedule>(entityName: "MedicineSchedule")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return request
    }

    /// How a medicine name is compared: trimmed and lowercased, so "Tylenol " matches "tylenol".
    static func key(for name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var minHoursBetween: Double? {
        get { minHoursBetweenNumber?.doubleValue }
        set { minHoursBetweenNumber = newValue.map { NSNumber(value: $0) } }
    }

    var maxDosesPer24h: Int? {
        get { maxDosesPer24hNumber?.intValue }
        set { maxDosesPer24hNumber = newValue.map { NSNumber(value: $0) } }
    }

    var rule: DoseRule {
        DoseRule(minHoursBetween: minHoursBetween, maxDosesPer24h: maxDosesPer24h)
    }

    /// Whether this iPhone notifies when the next dose is allowed. Kept on the phone, not synced.
    var notifiesWhenAllowed: Bool {
        get {
            guard let id = uuid?.uuidString else { return false }
            return (UserDefaults.shared.stringArray(forKey: SettingsKey.medicineDoseAlerts) ?? []).contains(id)
        }
        set {
            guard let id = uuid?.uuidString else { return }
            var ids = Set(UserDefaults.shared.stringArray(forKey: SettingsKey.medicineDoseAlerts) ?? [])
            if newValue { ids.insert(id) } else { ids.remove(id) }
            UserDefaults.shared.set(Array(ids).sorted(), forKey: SettingsKey.medicineDoseAlerts)
        }
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var medicineSchedules: NSSet?
}

extension Sequence where Element == MedicineSchedule {
    /// The schedule for a medicine name, ignoring case and surrounding spaces.
    func matching(_ name: String?) -> MedicineSchedule? {
        let key = MedicineSchedule.key(for: name)
        guard !key.isEmpty else { return nil }
        return first { MedicineSchedule.key(for: $0.name) == key }
    }
}
