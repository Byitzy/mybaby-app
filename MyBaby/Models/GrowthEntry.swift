import CoreData
import Foundation

/// A weight and/or length measurement, e.g. from a checkup or a home scale.
///
/// Always stored in kilograms and centimeters; `GrowthUnits` converts for display.
@objc(GrowthEntry)
final class GrowthEntry: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date
    @NSManaged var weightKgNumber: NSNumber?
    @NSManaged var lengthCmNumber: NSNumber?
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(in context: NSManagedObjectContext) -> GrowthEntry {
        let entry = GrowthEntry(context: context)
        entry.uuid = UUID()
        entry.date = .now
        entry.notes = ""
        Baby.attach(entry, in: context) { entry.baby = $0 }
        return entry
    }

    /// Every measurement, oldest first.
    static func fetchAll() -> NSFetchRequest<GrowthEntry> {
        let request = NSFetchRequest<GrowthEntry>(entityName: "GrowthEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return request
    }

    var weightKg: Double? {
        get { weightKgNumber?.doubleValue }
        set { weightKgNumber = newValue.map { NSNumber(value: $0) } }
    }

    var lengthCm: Double? {
        get { lengthCmNumber?.doubleValue }
        set { lengthCmNumber = newValue.map { NSNumber(value: $0) } }
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var growthEntries: NSSet?
}
