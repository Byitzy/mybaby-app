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
    /// A cancelled appointment stays in the list, struck through, so it can be restored; it has
    /// no reminders, follow-up or calendar event, and the reports leave it out.
    @NSManaged var isCancelled: Bool
    /// When it was cancelled; `nil` while it isn't.
    @NSManaged var cancelledAt: Date?
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
    /// The checkups, in order, in the iPhone's language. The picked one is saved as the title.
    static let checkupTitles = [
        String(localized: "Newborn checkup"),
        String(localized: "2-week checkup"),
        String(localized: "1-month checkup"),
        String(localized: "2-month checkup"),
        String(localized: "4-month checkup"),
        String(localized: "6-month checkup"),
        String(localized: "9-month checkup"),
        String(localized: "12-month checkup"),
    ]

    /// Not localized: the same checkups in English, the order `checkupTitles` has, so a title saved
    /// in English (before the app was translated, or on an English iPhone) still has a next checkup.
    static let englishCheckupTitles = [
        "Newborn checkup",
        "2-week checkup",
        "1-month checkup",
        "2-month checkup",
        "4-month checkup",
        "6-month checkup",
        "9-month checkup",
        "12-month checkup",
    ]

    static let commonTitles = checkupTitles + [
        String(localized: "Lactation consultant", comment: "Suggested appointment title"),
    ]

    static let reminderOptions: [ReminderOption] = [
        ReminderOption(title: String(localized: "None"), minutes: nil),
        ReminderOption(title: String(localized: "At time of appointment"), minutes: 0),
        ReminderOption(title: String(localized: "15 minutes before"), minutes: 15),
        ReminderOption(title: String(localized: "1 hour before"), minutes: 60),
        ReminderOption(title: String(localized: "2 hours before"), minutes: 120),
        ReminderOption(title: String(localized: "1 day before"), minutes: 1440),
    ]
}

struct ReminderOption: Identifiable {
    let title: String
    let minutes: Int?
    var id: String { title }
}
