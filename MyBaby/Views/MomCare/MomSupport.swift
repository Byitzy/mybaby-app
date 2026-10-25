import SwiftUI

/// Where to turn for help, kept short and warm. MyBaby never diagnoses anything and doesn't use a
/// screening questionnaire; the check-in is only a mood face, and this is about support.
enum MomSupport {
    /// True when most check-ins in the last 14 days (counting today) were one of the two lowest
    /// faces. Needs at least two check-ins, so one hard day alone doesn't bring up the card.
    static func mostlyLowMood(_ checkIns: [CareEntry], now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let moods = checkIns.filter { $0.date >= start }.compactMap(\.mood)
        guard moods.count >= 2 else { return false }
        return moods.filter(\.isLow).count * 2 > moods.count
    }
}

/// The kind card shown when recent check-ins have mostly been hard days.
struct GentleSupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("You're not alone")
                    .font(.headline)
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Palette.momCare)
            }
            .accessibilityAddTraits(.isHeader)
            Text("You've had a lot of hard days lately. Many new parents feel this way, and help works.")
            Text("It can really help to tell your doctor or midwife how you've been feeling. You don't have to wait for your next checkup.")
                .foregroundStyle(.secondary)
            // A line for the person's region (SupportResourcesSection.swift); none if it has no featured one.
            RegionalSupportCardButton()
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

/// Help lines, always at the bottom of the parent care page: for the person's region, from
/// support-resources.json (see SupportResourcesSection.swift).
struct SupportResourcesSections: View {
    var body: some View {
        SupportResourcesSection()
    }
}
