import CoreData
import SwiftUI

/// Health › Allergies › Introducing foods: the nine common food allergens, whether each has been
/// tried, how often, when it was first and last given, and reactions logged around then.
///
/// It only shows what was logged ("Last given 9 days ago"). It never says when or how often to
/// give a food; the footer points to the pediatrician for that.
struct IntroducingFoodsView: View {
    let baby: Baby
    @FetchRequest private var solids: FetchedResults<Activity>
    @FetchRequest private var reactions: FetchedResults<AllergyReaction>
    @FetchRequest private var allergies: FetchedResults<Allergy>

    init(baby: Baby) {
        self.baby = baby
        _solids = FetchRequest(fetchRequest: baby.entries(Activity.fetch(
            NSPredicate(
                format: "kindRaw == %@ AND feedingTypeRaw == %@ AND allergensRaw != nil",
                ActivityKind.feeding.rawValue, FeedingType.solids.rawValue
            ),
            newestFirst: false
        )))
        _reactions = FetchRequest(fetchRequest: baby.entries(AllergyReaction.fetchAll()))
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    var body: some View {
        let entries = AllergenIntroduction.build(
            feeds: solids.map { AllergenIntroduction.Feed(date: $0.startDate, allergenIDs: $0.allergenIDs) },
            reactions: reactions.map { AllergenIntroduction.Reaction(date: $0.date, allergenID: $0.allergy?.allergenRaw) }
        )
        let tried = entries.filter(\.isTried)
        let notTried = entries.filter { !$0.isTried }

        TimelineView(.everyMinute) { timeline in
            List {
                if tried.isEmpty {
                    Section {
                        Text("When you log solids, tag the common allergens the food had (Feed › Solids › Contains). Each one shows here with when it was first and last given.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !tried.isEmpty {
                    Section("Tried") {
                        ForEach(tried) { row($0, now: timeline.date) }
                    }
                }
                if !notTried.isEmpty {
                    Section {
                        ForEach(notTried) { row($0, now: timeline.date) }
                    } header: {
                        Text("Not tried yet")
                    } footer: {
                        Text(Self.footer)
                    }
                }
                if notTried.isEmpty {
                    Section {
                        Text(Self.footer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Introducing foods")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let footer = String(localized: "Your pediatrician can tell you when and how to introduce allergens, especially if your baby has eczema or a known allergy.")

    private func row(_ entry: AllergenIntroduction, now: Date) -> some View {
        let allergy = activeAllergy(for: entry.allergen)
        return HStack(alignment: .top, spacing: Spacing.m) {
            EmojiBadge(emoji: entry.allergen.emoji, tint: entry.isTried ? Palette.allergy : Palette.inactive)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.allergen.name)
                    .font(.body.weight(.medium))
                Text(entry.triedText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let last = entry.lastGivenText(now: now) {
                    Text(last)
                        .font(.subheadline)
                }
                if let allergy {
                    NoticeLabel(
                        "\(allergy.status.title) allergy · \(allergy.severity.title.lowercased())",
                        systemImage: "allergens",
                        tint: Palette.allergy
                    )
                    .font(.caption.weight(.medium))
                }
                ForEach(entry.reactionDates.prefix(3), id: \.self) { date in
                    NoticeLabel(
                        "Reaction on \(date.formatted(.dateTime.month(.abbreviated).day()))",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: Palette.warning
                    )
                    .font(.caption)
                }
                if entry.reactionDates.count > 3 {
                    Text("and \(entry.reactionDates.count - 3) more reactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// A confirmed or suspected allergy on the list for this allergen.
    private func activeAllergy(for allergen: CommonAllergen) -> Allergy? {
        allergies.sortedForDisplay().first { allergy in
            allergy.isActive && AllergyMatch.foodMatches(
                allergyName: allergy.displayName, allergenID: allergy.allergenRaw, tags: [allergen.id], food: ""
            )
        }
    }
}
