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
            case .appointments: return "Visits"
            case .vaccines: return "Vaccines"
            case .medicine: return "Medicine"
            case .allergies: return "Allergies"
            case .growth: return "Growth"
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
                            .accessibilityLabel(segment.rawValue)
                            .tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, Spacing.s)

                switch segment {
                case .appointments: AppointmentsList(baby: baby)
                case .vaccines: VaccinesList(baby: baby)
                case .medicine: MedicineList(baby: baby)
                case .allergies: AllergiesList(baby: baby)
                case .growth: GrowthList(baby: baby)
                }
            }
            .background(Palette.screenBackground)
            .navigationTitle("Health")
        }
    }
}
