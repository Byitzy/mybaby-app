import CoreData
import SwiftUI

extension SettingsKey {
    // In `UserDefaults.standard`, for this iPhone only:
    /// Set once someone picks who this iPhone belongs to (Settings › Parents, Night shifts, or
    /// Today's "Who's using this iPhone?" card, including dismissing it), so Today stops asking.
    static let deviceOwnerChosen = "deviceOwnerChosen"
}

/// Saves the parents' names and who this iPhone belongs to from outside Night shifts, the same way
/// Night shifts saves its plan: on this iPhone, then the schedule (which includes the names) on the
/// shared baby for the partner's iPhone, then this iPhone's night-shift reminders, which depend on both.
@MainActor
enum ParentSettings {
    /// Offered under an empty name field. There can be two moms or two dads, so both fields get all of them.
    static let suggestions = ["Mom", "Dad", "Mama", "Papa", "Mommy", "Daddy"]

    static func save(_ plan: NightPlan, context: NSManagedObjectContext) {
        plan.save()
        // Only the schedule goes to the partner's iPhone; who this iPhone belongs to stays here.
        SharedPlanSync.push(plan, context: context)
        Task { await NotificationManager.refreshNightShiftReminders() }
    }

    /// Who this iPhone belongs to. Night-shift wake-ups and cry alerts only buzz them.
    static func setOwner(_ owner: AlarmOwner, context: NSManagedObjectContext) {
        markOwnerChosen()
        var plan = NightPlan.load()
        guard plan.alarmOwner != owner else { return }
        plan.alarmOwner = owner
        save(plan, context: context)
    }

    /// Stops Today from asking "Who's using this iPhone?".
    static func markOwnerChosen() {
        UserDefaults.standard.set(true, forKey: SettingsKey.deviceOwnerChosen)
    }

    /// Onboarding's optional names. The person setting up the app is parent 1, and this is their iPhone.
    /// A name left blank stays as it was.
    static func saveFromOnboarding(yourName: String, partnerName: String, context: NSManagedObjectContext) {
        var plan = NightPlan.load()
        let yours = yourName.trimmingCharacters(in: .whitespacesAndNewlines)
        let partners = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !yours.isEmpty { plan.parent1Name = yours }
        if !partners.isEmpty { plan.parent2Name = partners }
        plan.alarmOwner = .parent1
        save(plan, context: context)
    }
}

/// Settings › Parents: the two parents' names, and who this iPhone belongs to.
///
/// The names are part of the night schedule, so they're shared with the partner's iPhone and used
/// wherever a parent is named (night shifts, "Handled by", cry alerts). Who this iPhone belongs to
/// (`NightPlan.alarmOwner`) stays on this one. Night shifts shows the same choice and reads the same
/// saved plan, so the two screens always agree.
struct ParentsSection: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEditLog) private var canEditLog
    /// Watched so the fields catch up when the plan is saved elsewhere: Night shifts, Today's
    /// "Who's using this iPhone?" card, or the partner's iPhone.
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @State private var plan = NightPlan.load()
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 10

    var body: some View {
        Section {
            ForEach(Parent.allCases) { parent in
                nameRow(parent)
            }
            Picker("This iPhone belongs to", selection: $plan.alarmOwner) {
                Text(plan.name(of: .parent1)).tag(AlarmOwner.parent1)
                Text(plan.name(of: .parent2)).tag(AlarmOwner.parent2)
                Text("Shared iPhone (both of us)").tag(AlarmOwner.both)
            }
        } header: {
            Text("Parents")
        } footer: {
            Text(footer)
        }
        .onAppear { reload() }
        .onChange(of: nightPlanData) { reload() }
        .onChange(of: plan) { _, newPlan in
            let stored = NightPlan.load()
            // Just reloaded from what's saved: nothing to save.
            guard newPlan != stored else { return }
            if newPlan.alarmOwner != stored.alarmOwner {
                ParentSettings.markOwnerChosen()
            }
            ParentSettings.save(newPlan, context: context)
        }
    }

    // MARK: Pieces

    private func nameRow(_ parent: Parent) -> some View {
        let placeholder = parent == .parent1 ? "Parent 1" : "Parent 2"
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                Circle()
                    .fill(parent.color)
                    .frame(width: dot, height: dot)
                    .accessibilityHidden(true)
                TextField(placeholder, text: nameBinding(parent))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("\(placeholder)'s name")
            }
            if canEditLog && plan.givenName(of: parent).isEmpty {
                suggestionChips(for: parent)
            }
        }
        .padding(.vertical, Spacing.xxs)
        // The names belong to the shared schedule, which view-only family can't change.
        .disabled(!canEditLog)
    }

    /// Mom, Dad, Mama… under an empty field, leaving out the one the other parent already uses.
    private func suggestionChips(for parent: Parent) -> some View {
        let taken = plan.givenName(of: parent.other).lowercased()
        let placeholder = parent == .parent1 ? "Parent 1" : "Parent 2"
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ParentSettings.suggestions.filter { $0.lowercased() != taken }, id: \.self) { suggestion in
                    Button {
                        if parent == .parent1 {
                            plan.parent1Name = suggestion
                        } else {
                            plan.parent2Name = suggestion
                        }
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, 7)
                            .background(Palette.chipBackground, in: Capsule())
                            .foregroundStyle(Color.primary)
                    }
                    // Each chip is its own tap target inside the list row.
                    .buttonStyle(.plain)
                    .accessibilityHint("Uses \(suggestion) as \(placeholder)'s name")
                }
            }
        }
    }

    // MARK: Helpers

    private var footer: String {
        let text = "Night-shift wake-ups and cry alerts only buzz the person this iPhone belongs to. Names are shared with your partner's iPhone; this choice isn't."
        return canEditLog ? text : text + " Only the parents can change the names."
    }

    private func nameBinding(_ parent: Parent) -> Binding<String> {
        parent == .parent1 ? $plan.parent1Name : $plan.parent2Name
    }

    /// Picks up the plan as it's saved now.
    private func reload() {
        let stored = NightPlan.load()
        if stored != plan { plan = stored }
    }
}

#Preview {
    NavigationStack {
        Form {
            ParentsSection()
        }
    }
}
