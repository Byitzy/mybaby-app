import CoreData
import CoreLocation

/// The clinic or provider picked from the place search in the vaccine editor, stored like an
/// appointment's place. The name stays in `provider`, as before, so vaccines from before places
/// (and clinics typed without picking a suggestion) keep working: they just have no address or map.
extension Vaccine {
    /// The clinic's address on one line.
    @NSManaged var providerAddress: String?
    @NSManaged var providerLatitude: NSNumber?
    @NSManaged var providerLongitude: NSNumber?
    /// The phone number Apple Maps has for the clinic, for Call.
    @NSManaged var providerPhone: String?

    /// The picked clinic, with `provider` as its name. `nil` for one that was typed in.
    var place: AppointmentPlace? {
        guard let latitude = providerLatitude?.doubleValue, let longitude = providerLongitude?.doubleValue,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        else { return nil }
        return AppointmentPlace(
            name: provider,
            address: providerAddress ?? "",
            latitude: latitude,
            longitude: longitude,
            phone: providerPhone ?? ""
        )
    }

    /// Stores a picked clinic's address, coordinates and phone, or clears them for a typed-in one.
    /// The name goes in `provider`, set separately like before.
    func setPlace(_ place: AppointmentPlace?) {
        let address = place?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = place?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        providerAddress = address.isEmpty ? nil : address
        providerLatitude = place.map { NSNumber(value: $0.latitude) }
        providerLongitude = place.map { NSNumber(value: $0.longitude) }
        providerPhone = phone.isEmpty ? nil : phone
    }

    /// The address, trimmed; empty when there's none.
    var providerPlaceAddress: String {
        (providerAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AppointmentPlace {
    /// Places already picked for this family's vaccines and appointments, newest first, one per
    /// name. Most babies get every shot at the same clinic, so it's usually the first one, and
    /// picking it again needs no search at all.
    static func recent(in context: NSManagedObjectContext, limit: Int = 5) -> [AppointmentPlace] {
        let vaccines = NSFetchRequest<Vaccine>(entityName: "Vaccine")
        vaccines.predicate = NSPredicate(format: "providerLatitude != nil AND providerLongitude != nil")
        vaccines.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        vaccines.fetchLimit = 20
        let appointments = NSFetchRequest<Appointment>(entityName: "Appointment")
        appointments.predicate = NSPredicate(format: "locationLatitude != nil AND locationLongitude != nil")
        appointments.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        appointments.fetchLimit = 20

        let dated = ((try? context.fetch(vaccines)) ?? []).compactMap { v in v.place.map { (v.date, $0) } }
            + ((try? context.fetch(appointments)) ?? []).compactMap { a in a.place.map { (a.date, $0) } }
        var seen = Set<String>()
        var places: [AppointmentPlace] = []
        for (_, place) in dated.sorted(by: { $0.0 > $1.0 }) {
            let key = place.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            places.append(place)
            if places.count == limit { break }
        }
        return places
    }
}
