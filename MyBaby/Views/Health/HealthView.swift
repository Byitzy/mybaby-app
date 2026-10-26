import SwiftUI

struct HealthView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case appointments = "Appointments"
        case vaccines = "Vaccines"
        case medicine = "Medicine"
        case allergies = "Allergies"
        case growth = "Growth"

        var id: String { rawValue }

        /// Short enough that the segments fit on the smallest iPhones.
        var title: String {
            switch self {
            case .appointments: return String(localized: "Visits", comment: "Short Health segment for appointments")
            case .vaccines: return String(localized: "Vaccines")
            case .medicine: return String(localized: "Medicine")
            case .allergies: return String(localized: "Allergies")
            case .growth: return String(localized: "Growth")
            }
        }

        /// The full name, for VoiceOver ("Appointments" for "Visits").
        var spokenTitle: String {
            switch self {
            case .appointments: return String(localized: "Appointments")
            case .vaccines: return String(localized: "Vaccines")
            case .medicine: return String(localized: "Medicine")
            case .allergies: return String(localized: "Allergies")
            case .growth: return String(localized: "Growth")
            }
        }
    }

    /// Whose appointments, vaccines, medicine, allergies and growth to show.
    let baby: Baby
    @State private var segment: Segment = .appointments

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.title)
                            .accessibilityLabel(segment.spokenTitle)
                            .tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, Spacing.s)
                // On a wide iPad window, the picker and the list share a readable column in the middle.
                .readableContentWidth()

                Group {
                    switch segment {
                    case .appointments: AppointmentsList(baby: baby)
                    case .vaccines: VaccinesList(baby: baby)
                    case .medicine: MedicineList(baby: baby)
                    case .allergies: AllergiesList(baby: baby)
                    case .growth: GrowthList(baby: baby)
                    }
                }
                // On the list itself, so it still scrolls from anywhere across the window.
                .readableContentWidth()
            }
            .background(Palette.screenBackground)
            .navigationTitle("Health")
        }
    }
}
