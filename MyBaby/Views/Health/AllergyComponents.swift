import CoreData
import SwiftUI

// Pieces of the allergy feature that other screens show: the allergen chips in the solids editor,
// the medicine warning, the emergency banner, the summary on the baby's profile, and the rows of
// the allergy list.

// MARK: - Chips

/// Chips that wrap onto as many lines as they need, so every allergen is visible at once and
/// nothing is cut off at large text sizes.
struct AllergyChipFlow: Layout {
    var spacing: CGFloat = Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            // A chip wider than the row wraps its own text instead of running off the edge.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if !current.items.isEmpty && current.width + spacing + size.width > maxWidth {
                let nextY = current.y + current.height + spacing
                rows.append(current)
                current = Row(y: nextY)
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append((index: index, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// One allergen as a chip that can be ticked. VoiceOver reads the name and whether it's selected.
struct AllergenChip: View {
    let allergen: CommonAllergen
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(allergen.emoji)
                    .accessibilityHidden(true)
                Text(allergen.name)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 7)
            .background(isSelected ? Palette.allergy.opacity(0.25) : Palette.chipBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Palette.allergy : Color.clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        // Its own tap target, rather than the whole row's.
        .buttonStyle(.plain)
        .accessibilityLabel(allergen.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Solids editor

/// In the solids editor: chips for the common allergens the food contained, and a gentle warning
/// when it may contain something on the baby's allergy list ("Mavie has a suspected egg allergy.").
struct SolidsAllergenSection: View {
    @Binding var selection: Set<String>
    /// What baby ate, as typed, also checked for allergens on the list.
    let food: String
    let baby: Baby
    @FetchRequest private var allergies: FetchedResults<Allergy>

    init(selection: Binding<Set<String>>, food: String, baby: Baby) {
        _selection = selection
        self.food = food
        self.baby = baby
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    var body: some View {
        let matches = allergies.sortedForDisplay().filter { allergy in
            allergy.isActive && AllergyMatch.foodMatches(
                allergyName: allergy.displayName, allergenID: allergy.allergenRaw, tags: selection, food: food
            )
        }
        if !matches.isEmpty {
            Section {
                ForEach(matches) { allergy in
                    NoticeLabel(
                        AllergyMatch.foodWarning(babyName: baby.displayName, allergyName: allergy.displayName, status: allergy.status),
                        systemImage: "exclamationmark.triangle.fill",
                        tint: Palette.allergy
                    )
                }
            } footer: {
                Text("From \(baby.displayName)'s allergy list in Health. You can still save.")
            }
        }

        Section {
            AllergyChipFlow {
                ForEach(CommonAllergen.foods) { allergen in
                    AllergenChip(allergen: allergen, isSelected: selection.contains(allergen.id)) {
                        selection.formSymmetricDifference([allergen.id])
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            Text("Contains (optional)")
        } footer: {
            Text("Tagged allergens show up in Health › Allergies › Introducing foods.")
        }
    }
}

// MARK: - Medicine warning

/// In the medicine editor and dose timing: "Mavie's list says she's allergic to amoxicillin. Check
/// with your doctor or pharmacist before giving it." while the name matches a medicine allergy.
/// It never stops the parent from saving.
struct MedicineAllergyWarningSection: View {
    let medicine: String
    let baby: Baby
    @FetchRequest private var allergies: FetchedResults<Allergy>

    init(medicine: String, baby: Baby) {
        self.medicine = medicine
        self.baby = baby
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    var body: some View {
        let matches = AllergyMatch.medicineAllergies(matching: medicine, in: allergies.sortedForDisplay())
        if !matches.isEmpty {
            Section {
                ForEach(matches) { allergy in
                    NoticeLabel(
                        AllergyMatch.medicineWarning(
                            babyName: baby.displayName, sex: baby.sex, allergyName: allergy.displayName, status: allergy.status
                        ),
                        systemImage: "exclamationmark.octagon.fill",
                        tint: Palette.danger
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, Spacing.xxs)
                }
            } footer: {
                Text("From \(baby.displayName)'s allergy list in Health. A warning never stops you from saving.")
            }
        }
    }
}

// MARK: - Emergency banner

/// "Trouble breathing, or swelling of the face, lips or tongue, can be an emergency. Call 911 now.",
/// with a call button for each emergency number of the person's region (the same one as the
/// support lines, from `support-resources.json`). Pinned to the top of the reaction editor, so it
/// stays in view while the rest of the form scrolls. It gives no other advice.
struct AllergyEmergencyBanner: View {
    @AppStorage(SupportDirectory.regionKey) private var regionOverride = ""

    var body: some View {
        let region = SupportDirectory.bundled?.resolvedRegion(override: regionOverride)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(Self.message(numbers: region?.emergencyText))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
            }
            // One button each, so a tap never dials another number.
            ForEach(region?.emergency ?? []) { number in
                if let url = number.phoneURL {
                    Link(destination: url) {
                        Label("Call \(number.text)", systemImage: "phone.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.danger)
                    .accessibilityLabel(spokenCall(number))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardStyle(padding: Spacing.m, cornerRadius: Radius.tile, tint: Palette.danger))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(Palette.danger, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    /// The banner's words, also read out by VoiceOver when it appears.
    static func message(numbers: String?) -> String {
        if let numbers {
            return String(localized: "Trouble breathing, or swelling of the face, lips or tongue, can be an emergency. Call \(numbers) now.")
        }
        return String(localized: "Trouble breathing, or swelling of the face, lips or tongue, can be an emergency. Call your local emergency number now.")
    }

    /// The same, for the person's region right now.
    static var currentMessage: String {
        let override = UserDefaults.standard.string(forKey: SupportDirectory.regionKey) ?? ""
        return message(numbers: SupportDirectory.bundled?.resolvedRegion(override: override).emergencyText)
    }

    /// "Call 9 1 1", so VoiceOver reads the digits one by one.
    private func spokenCall(_ number: EmergencyNumber) -> String {
        let digits = SupportDirectory.spoken(number.number)
        return number.label.map { String(localized: "Call \(digits), \($0)", comment: "The digits, then what the number is for: Call 1 1 2, from a mobile") }
            ?? String(localized: "Call \(digits)")
    }
}

// MARK: - Baby profile

/// At the top of the baby's profile: "Allergies: Peanut (confirmed, severe)", opening the list.
struct AllergyProfileSection: View {
    let baby: Baby
    /// Whether this iPhone can change this baby's log (view-only family can't).
    let canEdit: Bool
    @FetchRequest private var allergies: FetchedResults<Allergy>

    init(baby: Baby, canEdit: Bool) {
        self.baby = baby
        self.canEdit = canEdit
        _allergies = FetchRequest(fetchRequest: baby.entries(Allergy.fetchAll()))
    }

    var body: some View {
        let active = allergies.sortedForDisplay().filter(\.isActive)
        let summary = active.isEmpty ? String(localized: "None listed", comment: "No allergies on the list") : active.map(\.shortSummary).joined(separator: ", ")
        Section {
            NavigationLink {
                AllergiesList(baby: baby)
                    .navigationTitle("Allergies")
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.canEditLog, canEdit)
            } label: {
                Label {
                    (Text("Allergies: ").fontWeight(.semibold) + Text(summary))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "allergens")
                        .foregroundStyle(active.isEmpty ? Color.secondary : Palette.allergy)
                }
            }
        }
    }
}

// MARK: - Rows

/// An allergy in the list: what, how sure and how bad, the reactions seen and the auto-injector.
struct AllergyRow: View {
    @ObservedObject var allergy: Allergy

    var body: some View {
        // A deleted allergy (here, or by the partner) can redraw once more before the list drops it.
        if allergy.isDeleted || allergy.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: Spacing.m) {
                EmojiBadge(
                    emoji: allergy.commonAllergen?.emoji ?? allergy.category.emoji,
                    tint: allergy.isActive ? Palette.allergy : Palette.inactive
                )
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(allergy.displayName)
                        .font(.body.weight(.medium))
                    // Said in words, so the severity never depends on color.
                    HStack(spacing: Spacing.xs) {
                        if allergy.severity == .severe && allergy.isActive {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.danger)
                                .accessibilityHidden(true)
                        }
                        Text("\(allergy.statusAndSeverity) · \(allergy.category.title)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    let seen = allergy.reactionsSeen.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seen.isEmpty {
                        Text(seen)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if allergy.hasAutoInjector {
                        Label(autoInjectorText, systemImage: "cross.vial")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    private var autoInjectorText: String {
        let place = allergy.autoInjectorLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? String(localized: "Has an epinephrine auto-injector") : String(localized: "Auto-injector: \(place)")
    }
}

/// A reaction in the list: what they had, the symptoms, how bad, when, and whether there's a photo.
struct AllergyReactionRow: View {
    @ObservedObject var reaction: AllergyReaction

    var body: some View {
        if reaction.isDeleted || reaction.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: Spacing.m) {
                EmojiBadge(emoji: "⚠️", tint: Palette.allergy)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(reaction.displayTitle)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let allergy = reaction.allergy, !allergy.isDeleted {
                        Text("Linked to \(allergy.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Spacing.s)
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(reaction.date, format: .dateTime.month(.abbreviated).day())
                        .font(.subheadline)
                    Text(reaction.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !reaction.photoIDSet.isEmpty {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has a photo")
                    }
                }
            }
            .padding(.vertical, Spacing.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    private var detail: String {
        let symptoms = reaction.symptomsText
        return symptoms.isEmpty ? reaction.severity.title : "\(reaction.severity.title) · \(symptoms)"
    }
}
