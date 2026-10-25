import CoreData
import Foundation

@objc(Appointment)
final class Appointment: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var title: String
    @NSManaged var date: Date
    @NSManaged var provider: String
    @NSManaged var location: String
    @NSManaged var notes: String
    /// "Questions to ask", one per line; asked ones start with "[x] " (see `VisitQuestions`).
    @NSManaged var questions: String
    @NSManaged var reminderMinutesNumber: NSNumber?
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(in context: NSManagedObjectContext) -> Appointment {
        let appointment = Appointment(context: context)
        appointment.uuid = UUID()
        appointment.date = .now
        appointment.reminderMinutes = 60
        Baby.attach(appointment, in: context) { appointment.baby = $0 }
        return appointment
    }

    static func fetchAll() -> NSFetchRequest<Appointment> {
        let request = NSFetchRequest<Appointment>(entityName: "Appointment")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return request
    }

    /// How long before the appointment to send a reminder. `nil` means no reminder.
    var reminderMinutes: Int? {
        get { reminderMinutesNumber?.intValue }
        set { reminderMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }

    var notificationID: String {
        "appointment-\(uuid?.uuidString ?? objectID.uriRepresentation().absoluteString)"
    }
}

extension Appointment {
    static let commonTitles = [
        "Newborn checkup",
        "2-week checkup",
        "1-month checkup",
        "2-month checkup",
        "4-month checkup",
        "6-month checkup",
        "9-month checkup",
        "12-month checkup",
        "Lactation consultant",
    ]

    static let reminderOptions: [ReminderOption] = [
        ReminderOption(title: "None", minutes: nil),
        ReminderOption(title: "At time of appointment", minutes: 0),
        ReminderOption(title: "15 minutes before", minutes: 15),
        ReminderOption(title: "1 hour before", minutes: 60),
        ReminderOption(title: "2 hours before", minutes: 120),
        ReminderOption(title: "1 day before", minutes: 1440),
    ]
}

struct ReminderOption: Identifiable {
    let title: String
    let minutes: Int?
    var id: String { title }
}
