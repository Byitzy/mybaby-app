import CoreData
import SwiftUI

/// One baby's details (name, birthday, sex for the growth charts), opened from Settings › Babies or
/// the ⓘ button in More › Babies. It also lets a parent show this baby in the app, or remove them.
struct BabyProfileView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var baby: Baby
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SettingsKey.selectedBaby, store: .shared) private var selectedBabyID = ""
    @AppStorage(SettingsKey.iCloudSync, store: .shared) private var syncEnabled = false

    /// View only or not, kept up to date by `CloudStatus` rather than asked of the store on every
    /// render (this view renders on every keystroke in the name field).
    @ObservedObject private var cloudStatus = CloudStatus.shared

    @State private var nameDraft = ""
    @State private var confirmingRemove = false
    /// What the remove confirmation says, worked out when Remove is tapped: it asks iCloud's
    /// records whether the log is shared, which is too slow to do on every render.
    @State private var removeConfirmation = ""

    var body: some View {
        let persistence = PersistenceController.shared
        // Per baby: the owner may have shared one baby's log with this iPhone as view only.
        let canEdit = cloudStatus.canEdit(baby)
        let isCurrent = Baby.preferred(from: Array(babies), selectedID: selectedBabyID) == baby

        Form {
            // "Allergies: Peanut (confirmed, severe)", first so it's seen at a glance.
            AllergyProfileSection(baby: baby, canEdit: canEdit)

            Section {
                // Edited through a draft, so clearing the field never leaves the baby without a name.
                TextField("Name", text: $nameDraft)
                    .textContentType(.givenName)
                    .onChange(of: nameDraft) { _, draft in
                        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty && name != baby.name {
                            baby.name = name
                            context.saveIfChanged()
                        }
                    }
                DateField("Birthday", selection: birthDate, includesTime: baby.hasBirthTime)
                Toggle("Time of birth", isOn: hasBirthTime)
                BabySexPicker(selection: baby.sexBinding(saving: context))
            } footer: {
                if !canEdit {
                    Text("Your partner shared \(baby.displayName)'s log with you as view only.")
                }
            }
            .disabled(!canEdit)

            Section {
                Picker("Born at", selection: gestationWeeks) {
                    Text("Not entered").tag(Int?.none)
                    Text("Full term (37 weeks or more)").tag(Int?.some(40))
                    ForEach((22...36).reversed(), id: \.self) { weeks in
                        Text("\(weeks) weeks").tag(Int?.some(weeks))
                    }
                }
                if baby.isPreterm {
                    Picker("And days", selection: gestationExtraDays) {
                        ForEach(0...6, id: \.self) { days in
                            Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                        }
                    }
                }
            } header: {
                Text("Length of pregnancy")
            } footer: {
                if baby.isPreterm, let due = baby.dueDate {
                    Text("Born early, so growth percentiles use corrected age, counted from the due date (\(due.formatted(date: .abbreviated, time: .omitted))), until \(baby.displayName)'s second birthday, as pediatricians usually do.")
                } else {
                    Text("For a baby born before 37 weeks, growth percentiles use corrected age, counted from the due date, until the second birthday.")
                }
            }
            .disabled(!canEdit)

            if babies.count > 1 {
                Section {
                    if isCurrent {
                        Label("Showing \(baby.displayName) in the app", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Baby.select(baby)
                        } label: {
                            Label("Show \(baby.displayName) in the app", systemImage: "arrow.left.arrow.right")
                        }
                    }
                } footer: {
                    Text("The app shows one baby at a time. You can also switch by tapping the name on Today.")
                }
            }

            // Two copies of this baby from another iPhone or iPad.
            DuplicateBabySection(baby: baby)

            removeSection(persistence: persistence)
        }
        .navigationTitle(baby.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameDraft = baby.name }
    }

    // MARK: Removing

    @ViewBuilder
    private func removeSection(persistence: PersistenceController) -> some View {
        if persistence.isJoined(baby) {
            Section {
                Text("\(baby.displayName)'s log was shared with you by your partner. To stop seeing it, open More › Settings › iCloud & sharing › Manage sharing and leave the shared log.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if babies.count > 1 {
            Section {
                Button("Remove \(baby.displayName) from MyBaby", role: .destructive) {
                    removeConfirmation = removeMessage(persistence: persistence)
                    confirmingRemove = true
                }
                .confirmationDialog(
                    "Remove \(baby.displayName) from MyBaby?",
                    isPresented: $confirmingRemove,
                    titleVisibility: .visible
                ) {
                    Button("Remove \(baby.displayName)", role: .destructive) {
                        Task { await persistence.deleteBaby(baby) }
                    }
                } message: {
                    Text(removeConfirmation)
                }
            } footer: {
                Text("Want a copy first? Export \(baby.displayName)'s log from More › Settings › Your data.")
            }
        }
        // With one baby there's nothing to remove: MyBaby always keeps a baby to log for.
    }

    private func removeMessage(persistence: PersistenceController) -> String {
        let name = baby.displayName
        let isShared = persistence.existingShare(for: baby) != nil || persistence.ownShare != nil
        // Whole sentences, so each language can put the places in its own order.
        switch (syncEnabled, isShared) {
        case (true, true):
            return String(localized: "\(name)'s log, including feeds, sleep, growth and milestones, will be removed from this iPhone and from iCloud, and from your partner's iPhone. This can't be undone.")
        case (true, false):
            return String(localized: "\(name)'s log, including feeds, sleep, growth and milestones, will be removed from this iPhone and from iCloud. This can't be undone.")
        case (false, true):
            return String(localized: "\(name)'s log, including feeds, sleep, growth and milestones, will be removed from this iPhone, and from your partner's iPhone. This can't be undone.")
        case (false, false):
            return String(localized: "\(name)'s log, including feeds, sleep, growth and milestones, will be removed from this iPhone. This can't be undone.")
        }
    }

    /// Showing the time of birth keeps the day; hiding it again just stops showing the time.
    private var hasBirthTime: Binding<Bool> {
        Binding(
            get: { baby.hasBirthTime },
            set: {
                baby.hasBirthTime = $0
                context.saveIfChanged()
            }
        )
    }

    /// Weeks of pregnancy at birth: nil when not entered, 40 for full term.
    private var gestationWeeks: Binding<Int?> {
        Binding(
            get: { baby.gestationWeeksNumber?.intValue },
            set: { weeks in
                baby.gestationWeeksNumber = weeks.map { NSNumber(value: $0) }
                if weeks == nil || weeks == 40 { baby.gestationDaysNumber = nil }
                context.saveIfChanged()
            }
        )
    }

    private var gestationExtraDays: Binding<Int> {
        Binding(
            get: { baby.gestationDaysNumber?.intValue ?? 0 },
            set: {
                baby.gestationDaysNumber = NSNumber(value: $0)
                context.saveIfChanged()
            }
        )
    }

    private var birthDate: Binding<Date> {
        Binding(
            get: { baby.birthDate ?? .now },
            set: {
                baby.birthDate = $0
                context.saveIfChanged()
            }
        )
    }
}
