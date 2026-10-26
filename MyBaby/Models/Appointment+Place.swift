import Contacts
import CoreData
import CoreLocation
import MapKit

/// A place picked from the location search in the appointment editor: the name and address shown in
/// the suggestions, where it is, and the phone number Apple Maps has for it, if any.
///
/// The name is kept in the appointment's `location` text, as before, so appointments from before
/// places (and places typed without picking a suggestion) keep working: they just have no address,
/// map or Directions.
struct AppointmentPlace: Equatable {
    var name: String
    /// One line, e.g. "12 Main Street, Springfield, IL 62701". The country is left out when it's the
    /// iPhone's own. Can be empty.
    var address: String
    var latitude: Double
    var longitude: Double
    /// As Apple Maps gives it, e.g. "+1 (555) 010-0199". Empty when it has none.
    var phone: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "Maple Street Pediatrics, 12 Main Street, Springfield".
    var line: String { Appointment.placeLine(name: name, address: address) }

    /// The address under the name, or `nil` when it would only repeat it (a street address picked
    /// as the place).
    var addressBelowName: String? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.caseInsensitiveCompare(name) != .orderedSame else { return nil }
        return address
    }

    /// For Directions and opening the map: the coordinates, with the name and phone so Maps shows them.
    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.name = trimmed.isEmpty ? nil : trimmed
        if !phone.isEmpty { item.phoneNumber = phone }
        return item
    }

    /// Shows the place in Apple Maps.
    func openInMaps() {
        mapItem.openInMaps(launchOptions: nil)
    }

    /// Opens Apple Maps with driving directions to the place, from wherever the iPhone is. Maps works
    /// that out itself; MyBaby never learns where the phone is.
    func openDirections() {
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// `tel:` for Call, or `nil` without a phone number.
    var phoneURL: URL? {
        phone.isEmpty ? nil : SupportDirectory.telURL(phone)
    }
}

extension AppointmentPlace {
    /// From the search's map item. `fallbackName` and `fallbackAddress` are the suggestion's title and
    /// subtitle, for a map item that's missing them.
    init(mapItem: MKMapItem, fallbackName: String, fallbackAddress: String) {
        let placemark = mapItem.placemark
        let itemName = (mapItem.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        name = itemName.isEmpty ? fallbackName : itemName
        address = Self.singleLineAddress(placemark) ?? fallbackAddress
        latitude = placemark.coordinate.latitude
        longitude = placemark.coordinate.longitude
        phone = (mapItem.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The postal address on one line, without the country when it's the iPhone's Region. `nil` when
    /// the map item has none; the suggestion's subtitle is used instead.
    private static func singleLineAddress(_ placemark: MKPlacemark) -> String? {
        if let postal = placemark.postalAddress?.mutableCopy() as? CNMutablePostalAddress {
            if let region = Locale.current.region?.identifier,
               postal.isoCountryCode.caseInsensitiveCompare(region) == .orderedSame {
                postal.country = ""
            }
            let lines = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return lines.joined(separator: ", ") }
        }
        return nil
    }
}

/// Where the appointment is, when it was picked from the search. All optional: older appointments,
/// and places typed without picking a suggestion, have none of these.
extension Appointment {
    /// The place's address on one line.
    @NSManaged var locationAddress: String?
    @NSManaged var locationLatitude: NSNumber?
    @NSManaged var locationLongitude: NSNumber?
    /// The phone number Apple Maps has for the place, for Call.
    @NSManaged var locationPhone: String?

    /// The picked place, with `location` as its name. `nil` for a place that was typed in.
    var place: AppointmentPlace? {
        guard let latitude = locationLatitude?.doubleValue, let longitude = locationLongitude?.doubleValue,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        else { return nil }
        return AppointmentPlace(
            name: location,
            address: locationAddress ?? "",
            latitude: latitude,
            longitude: longitude,
            phone: locationPhone ?? ""
        )
    }

    /// Stores a picked place's address, coordinates and phone, or clears them for a typed-in place.
    /// The name goes in `location`, set separately like before.
    func setPlace(_ place: AppointmentPlace?) {
        let address = place?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = place?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        locationAddress = address.isEmpty ? nil : address
        locationLatitude = place.map { NSNumber(value: $0.latitude) }
        locationLongitude = place.map { NSNumber(value: $0.longitude) }
        locationPhone = phone.isEmpty ? nil : phone
    }

    /// The address, trimmed; empty when there's none.
    var placeAddress: String {
        (locationAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address for under the place's name in the list, or `nil` when there's none or it would
    /// only repeat the name.
    var addressBelowLocation: String? {
        let address = placeAddress
        guard !address.isEmpty, address.caseInsensitiveCompare(location.trimmingCharacters(in: .whitespaces)) != .orderedSame
        else { return nil }
        return address
    }

    /// "Maple Street Pediatrics, 12 Main Street, Springfield", for the visit summary and its PDF.
    var placeLine: String { Self.placeLine(name: location, address: placeAddress) }

    /// The name and address on one line, without saying the same thing twice.
    static func placeLine(name: String, address: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return name }
        if name.isEmpty || address.localizedCaseInsensitiveContains(name) { return address }
        return "\(name), \(address)"
    }
}
