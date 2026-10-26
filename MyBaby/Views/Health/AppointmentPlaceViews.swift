import MapKit
import SwiftUI

/// One place suggestion under the location field: the name, with the address below it.
struct PlaceSuggestionRow: View {
    let suggestion: PlaceSearch.Suggestion
    /// What picking it does, for VoiceOver.
    var hint = String(localized: "Uses this place for the appointment")
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Palette.appointment)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(suggestion.title)
                        .foregroundStyle(.primary)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // "Maple Street Pediatrics, 12 Main Street, Springfield, button".
        .accessibilityLabel(suggestion.spokenLabel)
        .accessibilityHint(hint)
    }
}

/// The clock button by a place field: places already picked for other vaccines and appointments,
/// newest first, each with its address. Picking one uses it as it was saved, with nothing searched.
struct RecentPlacesMenu: View {
    let places: [AppointmentPlace]
    let accessibilityLabel: String
    let onPick: (AppointmentPlace) -> Void

    var body: some View {
        Menu {
            ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                Button {
                    onPick(place)
                } label: {
                    Text(place.name)
                    if let address = place.addressBelowName {
                        Text(address)
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The picked place in the appointment editor: its address, a small map (tap to open it in Maps),
/// Directions and, when Apple Maps has a number, Call.
///
/// The map is only drawn here, not in every list row, so the list stays light. Like any map, it's
/// loaded from Apple Maps.
struct AppointmentPlaceCard: View {
    let place: AppointmentPlace

    @Environment(\.openURL) private var openURL
    @Environment(\.isThreeAMMode) private var isThreeAMMode

    private var displayName: String {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "Appointment") : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let address = place.addressBelowName {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Address: \(address)")
            }

            Button {
                place.openInMaps()
            } label: {
                Map(initialPosition: .region(previewRegion), interactionModes: []) {
                    Marker(displayName, coordinate: place.coordinate)
                        .tint(Palette.appointment)
                }
                // A new place starts the map again at its spot.
                .id("\(place.latitude),\(place.longitude)")
                .allowsHitTesting(false)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
                // A dimmer map at night, under 3 AM mode's red.
                .opacity(isThreeAMMode ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map of \(displayName)")
            .accessibilityHint("Opens it in Maps")

            AdaptiveStack(spacing: Spacing.s) {
                Button {
                    place.openDirections()
                } label: {
                    Label("Directions", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityHint("Opens driving directions in Maps")

                if let url = place.phoneURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Call \(displayName)")
                    .accessibilityHint(place.phone)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, Spacing.xs)
    }

    /// About a kilometer around the place: enough to see the streets nearby.
    private var previewRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1_000, longitudinalMeters: 1_000)
    }
}
