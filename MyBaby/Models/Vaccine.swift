import CoreData
import Foundation

/// A vaccine that was given, or one that is coming up.
@objc(Vaccine)
final class Vaccine: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    /// The date it was given, or the date it is due when `isGiven` is false.
    @NSManaged var date: Date
    @NSManaged var isGiven: Bool
    @NSManaged var doseLabel: String
    @NSManaged var provider: String
    @NSManaged var lotNumber: String
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(in context: NSManagedObjectContext) -> Vaccine {
        let vaccine = Vaccine(context: context)
        vaccine.uuid = UUID()
        vaccine.date = .now
        vaccine.isGiven = true
        Baby.attach(vaccine, in: context) { vaccine.baby = $0 }
        return vaccine
    }

    static func fetchAll() -> NSFetchRequest<Vaccine> {
        let request = NSFetchRequest<Vaccine>(entityName: "Vaccine")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return request
    }
}

extension Vaccine {
    /// Names to pick from when adding a shot, from the vaccine guide. Your pediatrician's schedule is
    /// the source of truth.
    static var commonNames: [String] { VaccineGuide.commonNames }
}
