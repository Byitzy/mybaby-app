import CoreLocation
import Foundation
import MapKit

/// Place suggestions for the appointment editor's location field, from Apple Maps, as the parent types.
///
/// What it sends, and when:
/// - Only what's typed in the location field goes to Apple Maps, the same as typing in Maps. Nothing
///   else from the log is sent.
/// - Nothing is sent until the parent types: the editor calls `update(query:)` from the field's edits
///   only, never when it fills the field in itself (opening an appointment, picking a suggestion).
/// - Queries wait for a 250 ms pause in typing, so a word is one request rather than one per letter.
/// - Picking a suggestion makes one more request, for that place's address, coordinates and phone.
/// - The search is nudged toward an area (`bias(toward:)`): the last place picked, or else the iPhone's
///   Region setting. MyBaby never asks for or uses the phone's location.
@MainActor
final class PlaceSearch: NSObject, ObservableObject {
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        /// Usually the address.
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion

        /// "Maple Street Pediatrics, 12 Main Street, Springfield", for VoiceOver.
        var spokenLabel: String {
            subtitle.isEmpty ? title : "\(title), \(subtitle)"
        }
    }

    @Published private(set) var suggestions: [Suggestion] = []
    /// While a picked suggestion's details are being looked up.
    @Published private(set) var isLookingUp = false
    /// Set when the details of a picked suggestion couldn't be found; the typed name is kept.
    @Published private(set) var lookupFailed = false

    static let debounce: Duration = .milliseconds(250)
    /// Enough to find the right one without pushing the rest of the form far down.
    static let maxSuggestions = 5
    /// One letter matches too much to be useful.
    static let minimumQueryLength = 2

    /// The one line under the field.
    static var privacyNote: String {
        String(
            localized: "Suggestions come from Apple Maps. Only what you type here is sent, as when you search in Maps; nothing else from the log. MyBaby doesn't ask for or use your iPhone's location.",
            comment: "Under the location field of an appointment or vaccine"
        )
    }

    private let completer = MKLocalSearchCompleter()
    private var pending: Task<Void, Never>?
    private var lookup: MKLocalSearch?
    /// The query last handed to the completer, so late results for an older one are ignored.
    private var activeQuery: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        // Sends nothing; it's only a hint for the first query.
        if let region = Self.regionFromSettings() {
            completer.region = region
        }
    }

    // MARK: Searching

    /// Called for each edit the parent makes in the field. Waits for a pause in typing, then asks
    /// Apple Maps for suggestions.
    func update(query: String) {
        pending?.cancel()
        lookupFailed = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            clear()
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: PlaceSearch.debounce)
            guard !Task.isCancelled, let self else { return }
            self.activeQuery = trimmed
            self.completer.queryFragment = trimmed
        }
    }

    /// Hides the suggestions and stops any search that's waiting or running.
    func clear() {
        pending?.cancel()
        pending = nil
        activeQuery = nil
        if completer.isSearching { completer.cancel() }
        if !suggestions.isEmpty { suggestions = [] }
    }

    /// When the editor closes.
    func cancel() {
        clear()
        lookup?.cancel()
        lookup = nil
    }

    /// Looks up the picked suggestion's name, address, coordinates and phone number. `nil` if Apple
    /// Maps couldn't find it (or there's no connection); `lookupFailed` says so.
    func place(for suggestion: Suggestion) async -> AppointmentPlace? {
        clear()
        lookup?.cancel()
        lookupFailed = false
        isLookingUp = true
        defer { isLookingUp = false }

        let request = MKLocalSearch.Request(completion: suggestion.completion)
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        lookup = search
        let item: MKMapItem?
        do {
            item = try await search.start().mapItems.first
        } catch {
            item = nil
        }
        guard lookup === search else { return nil }
        lookup = nil
        guard let item else {
            lookupFailed = true
            return nil
        }
        return AppointmentPlace(mapItem: item, fallbackName: suggestion.title, fallbackAddress: suggestion.subtitle)
    }

    fileprivate func show(_ results: [MKLocalSearchCompletion], for query: String) {
        guard let activeQuery, query == activeQuery else { return }
        suggestions = results.prefix(Self.maxSuggestions).map {
            Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
    }

    // MARK: Where to look

    /// Nudges suggestions toward this area, e.g. the last place picked: about 50 km around it.
    /// `nil` keeps the area from the iPhone's Region setting.
    func bias(toward coordinate: CLLocationCoordinate2D?) {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
        completer.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
    }

    /// The country picked for the support lines in Parent care, or else the iPhone's Region setting
    /// (Settings → General → Language & Region). Neither needs any permission.
    private static func regionFromSettings() -> MKCoordinateRegion? {
        let picked = UserDefaults.standard.string(forKey: SupportDirectory.regionKey) ?? ""
        let code = (picked.isEmpty || picked == SupportDirectory.otherCode) ? SupportDirectory.deviceRegionCode : picked
        guard let code, let area = countryAreas[code.uppercased()] else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude),
            span: MKCoordinateSpan(latitudeDelta: area.latitudeSpan, longitudeDelta: area.longitudeSpan)
        )
    }

    /// Roughly where each country is (its middle, and how many degrees it spans), only to nudge the
    /// suggestions. A country not listed gets Apple Maps' own default.
    private static let countryAreas: [String: (latitude: Double, longitude: Double, latitudeSpan: Double, longitudeSpan: Double)] = [
        "US": (39.5, -98.4, 24, 58),
        "CA": (52.0, -95.0, 20, 60),
        "MX": (23.6, -102.5, 16, 24),
        "GB": (54.0, -2.5, 10, 9),
        "IE": (53.4, -8.0, 4, 5),
        "FR": (46.6, 2.4, 9, 11),
        "DE": (51.2, 10.4, 8, 10),
        "ES": (40.2, -3.7, 9, 12),
        "PT": (39.6, -8.0, 6, 4),
        "IT": (42.8, 12.5, 11, 12),
        "NL": (52.2, 5.3, 3, 4),
        "BE": (50.6, 4.6, 2, 3),
        "LU": (49.8, 6.1, 1, 1),
        "CH": (46.8, 8.2, 2.5, 4.5),
        "AT": (47.6, 14.1, 3, 7),
        "DK": (56.0, 10.0, 3.5, 6),
        "SE": (62.0, 15.0, 14, 13),
        "NO": (64.5, 12.0, 16, 22),
        "FI": (64.0, 26.0, 11, 12),
        "IS": (64.9, -18.6, 3, 9),
        "PL": (52.0, 19.4, 6, 10),
        "CZ": (49.8, 15.5, 2.5, 6.5),
        "GR": (39.0, 22.0, 6, 8),
        "IL": (31.4, 35.0, 4.5, 2.5),
        "TR": (39.0, 35.2, 6, 19),
        "AE": (24.3, 54.3, 4, 5),
        "SA": (24.0, 45.0, 16, 20),
        "IN": (22.0, 79.0, 28, 30),
        "JP": (36.2, 138.3, 18, 20),
        "KR": (36.4, 127.8, 5, 5),
        "CN": (35.0, 104.0, 35, 55),
        "HK": (22.35, 114.15, 0.5, 0.6),
        "SG": (1.35, 103.82, 0.4, 0.5),
        "TW": (23.7, 121.0, 4, 3),
        "PH": (12.9, 121.8, 15, 10),
        "AU": (-27.0, 134.0, 35, 40),
        "NZ": (-41.0, 173.0, 13, 14),
        "ZA": (-29.0, 24.7, 13, 17),
        "NG": (9.1, 8.7, 10, 12),
        "KE": (0.2, 37.9, 10, 9),
        "BR": (-14.2, -51.9, 35, 38),
        "AR": (-38.4, -63.6, 33, 22),
        "CL": (-35.7, -71.5, 38, 10),
        "CO": (4.6, -74.1, 15, 13),
        "PE": (-9.2, -75.0, 18, 13),
    ]
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    // The completer reports back on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.show(completer.results, for: completer.queryFragment)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            // No connection, or nothing found: the field still takes whatever is typed.
            self.show([], for: completer.queryFragment)
        }
    }
}
