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

    @State private var nameDraft = ""
    @State private var confirmingRemove = false

    var body: some View {
        let persistence = PersistenceController.shared
        // Per baby: the owner may have shared one baby's log with this iPhone as view only.
        let canEdit = persistence.canEdit(baby)
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
                DateField("Birthday", selection: birthDate, includesTime: false)
                BabySexPicker(selection: baby.sexBinding(saving: context))
            } footer: {
                if !canEdit {
                    Text("Your partner shared \(baby.displayName)'s log with you as view only.")
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
                    Text(removeMessage(persistence: persistence))
                }
            } footer: {
                Text("Want a copy first? Export \(baby.displayName)'s log from More › Settings › Your data.")
            }
        }
        // With one baby there's nothing to remove: MyBaby always keeps a baby to log for.
    }

    private func removeMessage(persistence: PersistenceController) -> String {
        var message = "\(baby.displayName)'s log, including feeds, sleep, growth and milestones, will be removed from this iPhone"
        message += syncEnabled ? " and from iCloud" : ""
        if persistence.existingShare(for: baby) != nil || persistence.ownShare != nil {
            message += ", and from your partner's iPhone"
        }
        return message + ". This can't be undone."
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
