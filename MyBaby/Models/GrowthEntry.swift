import CoreData
import Foundation

/// A weight, length and/or head circumference measurement, e.g. from a checkup or a home scale.
///
/// Always stored in kilograms and centimeters; `GrowthUnits` converts for display.
@objc(GrowthEntry)
final class GrowthEntry: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date
    @NSManaged var weightKgNumber: NSNumber?
    @NSManaged var lengthCmNumber: NSNumber?
    /// Added after weight and length. "How did it go?" recaps saved before then kept it on the
    /// appointment instead (`Appointment.headCircumferenceCm`); `GrowthReading` brings the two together.
    @NSManaged var headCircumferenceCmNumber: NSNumber?
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

    /// Only this entry's own value; `headCmIncludingRecap` also reads an older recap's.
    var headCircumferenceCm: Double? {
        get { headCircumferenceCmNumber?.doubleValue }
        set { headCircumferenceCmNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// The appointment whose "How did it go?" recap saved this entry: the recap dates its
    /// measurements at the appointment's exact time (see `Appointment.measurementAtVisit`).
    var recapAppointment: Appointment? {
        let appointments = (baby?.appointments as? Set<Appointment>) ?? []
        return appointments.first { $0.hasRecap && abs($0.date.timeIntervalSince(date)) < 60 }
    }

    /// The head circumference, or, for a recap saved before entries had one, the one kept on its
    /// appointment.
    var headCmIncludingRecap: Double? {
        headCircumferenceCm ?? recapAppointment?.headCircumferenceCm
    }

    /// Sets the head circumference here and on the recap's appointment, if there is one, so the
    /// older copy never shows through a changed or cleared value, and a partner's phone still
    /// running an earlier version of MyBaby sees the same number in the recap.
    func setHeadCircumference(_ cm: Double?) {
        headCircumferenceCm = cm
        if let appointment = recapAppointment, appointment.headCircumferenceCm != cm {
            appointment.headCircumferenceCm = cm
        }
    }

    /// Deletes the entry, and the copy of its head circumference an older recap kept on the
    /// appointment, so it doesn't come back on its own.
    func deleteIncludingRecapHead(in context: NSManagedObjectContext) {
        if let appointment = recapAppointment, appointment.headCircumferenceCm != nil {
            appointment.headCircumferenceCm = nil
        }
        context.delete(self)
    }
}

/// One measurement as Growth, the reports and the export show it: a `GrowthEntry`, with the head
/// circumference older recaps kept on the appointment merged in. A recap with only a head
/// circumference, saved before entries had one, has no entry, so it's a reading of its own.
struct GrowthReading: Identifiable {
    let id: NSManagedObjectID
    let date: Date
    let weightKg: Double?
    let lengthCm: Double?
    let headCm: Double?
    let notes: String
    /// `nil` for a head circumference only an older recap has.
    let entry: GrowthEntry?
    /// The recap a reading without an entry comes from.
    let recap: Appointment?

    /// The value of one measure: kilograms or centimeters.
    func value(_ measure: GrowthMeasure) -> Double? {
        switch measure {
        case .weight: return weightKg
        case .length: return lengthCm
        case .headCircumference: return headCm
        }
    }

    /// Every reading, oldest first. `appointments` are the baby's, for the older recaps.
    static func all(entries: [GrowthEntry], appointments: [Appointment]) -> [GrowthReading] {
        let recaps = appointments.filter { $0.hasRecap && $0.headCircumferenceCm != nil }
        func recap(at date: Date) -> Appointment? {
            recaps.first { abs($0.date.timeIntervalSince(date)) < 60 }
        }
        var readings = entries.map { entry in
            GrowthReading(
                id: entry.objectID,
                date: entry.date,
                weightKg: entry.weightKg,
                lengthCm: entry.lengthCm,
                headCm: entry.headCircumferenceCm ?? recap(at: entry.date)?.headCircumferenceCm,
                notes: entry.notes,
                entry: entry,
                recap: nil
            )
        }
        for appointment in recaps where !entries.contains(where: { abs($0.date.timeIntervalSince(appointment.date)) < 60 }) {
            readings.append(GrowthReading(
                id: appointment.objectID,
                date: appointment.date,
                weightKg: nil,
                lengthCm: nil,
                headCm: appointment.headCircumferenceCm,
                notes: appointment.title.isEmpty
                    ? String(localized: "Measured at the appointment", comment: "Note on a head circumference from a visit recap")
                    : String(localized: "Measured at \(appointment.title)", comment: "Note on a head circumference from a visit recap, with the appointment's title, e.g. “Measured at 2-month checkup”"),
                entry: nil,
                recap: appointment
            ))
        }
        return readings.sorted { $0.date < $1.date }
    }

    /// The baby's readings, fetched from `context`.
    static func all(for baby: Baby, in context: NSManagedObjectContext) -> [GrowthReading] {
        let entries = (try? context.fetch(baby.entries(GrowthEntry.fetchAll()))) ?? []
        let appointments = (try? context.fetch(baby.entries(Appointment.fetchAll()))) ?? []
        return all(entries: entries, appointments: appointments)
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var growthEntries: NSSet?
}
