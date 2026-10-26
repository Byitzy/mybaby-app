import CoreData
import SwiftUI

/// Every baby on this iPhone (twins, siblings): pick the one the app shows, or add another.
struct BabiesView: View {
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SettingsKey.selectedBaby, store: .shared) private var selectedBabyID = ""
    @State private var addingBaby = false
    /// The baby whose profile is open, from the ⓘ button.
    @State private var profileBaby: Baby?
    /// Whether babies can be added here, kept up to date without asking the store on every render.
    @ObservedObject private var cloudStatus = CloudStatus.shared

    var body: some View {
        let current = Baby.preferred(from: Array(babies), selectedID: selectedBabyID)

        List {
            Section {
                ForEach(babies) { baby in
                    HStack(spacing: Spacing.m) {
                        Button {
                            Baby.select(baby)
                        } label: {
                            BabyRow(baby: baby, isCurrent: baby == current)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(baby == current ? .isSelected : [])
                        .accessibilityHint("Shows \(baby.displayName) in the app")

                        Button {
                            profileBaby = baby
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(baby.displayName)'s details")
                    }
                }
            } footer: {
                Text("Tap a baby to show them in the app, or ⓘ to edit their details. You can also switch by tapping the name on Today.")
            }

            Section {
                Button {
                    addingBaby = true
                } label: {
                    Label("Add a baby", systemImage: "plus")
                }
                .disabled(!cloudStatus.canAddBabies)
            } footer: {
                if !cloudStatus.canAddBabies {
                    Text(AddBabyView.joinedNote)
                }
            }
        }
        .navigationTitle("Babies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingBaby = true } label: {
                    Label("Add a baby", systemImage: "plus")
                }
                .disabled(!cloudStatus.canAddBabies)
            }
        }
        .sheet(isPresented: $addingBaby) {
            AddBabyView()
        }
        .navigationDestination(item: $profileBaby) { baby in
            BabyProfileView(baby: baby)
        }
    }
}

/// A baby's name, age and whether the app is showing them. Used in More › Babies and Settings.
struct BabyRow: View {
    @ObservedObject var baby: Baby
    var isCurrent = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            EmojiBadge(emoji: "👶", tint: .accentColor)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(baby.displayName)
                    .font(.body.weight(.medium))
                if let birthDate = baby.birthDate {
                    Text(Format.age(birthDate: birthDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if PersistenceController.shared.isJoined(baby) {
                    Text("Shared by your partner")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "Showing in the app" : "")
    }
}

/// A small form for another baby, saved on this iPhone and shown right away.
struct AddBabyView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var birthDate = Date.now
    @State private var sex: BabySex?
    @State private var isSaving = false
    @State private var isShared = false
    @ObservedObject private var cloudStatus = CloudStatus.shared

    /// Why a parent who joined their partner's log can't add a baby on their own iPhone.
    static let joinedNote = String(localized: "Your partner set up this log, so new babies are added on their iPhone. Once they add one, it shows up here too.")

    var body: some View {
        let canAdd = cloudStatus.canAddBabies

        NavigationStack {
            Form {
                if canAdd {
                    Section {
                        TextField("Baby's name", text: $name)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                        DateField("Birthday", selection: $birthDate, includesTime: false)
                        BabySexPicker(selection: $sex)
                    } footer: {
                        Text(isShared
                             ? "Each baby has their own log. You share this iPhone's log with your partner, so they'll see the new baby too."
                             : "Each baby has their own log. Switch between them by tapping the name on Today.")
                    }
                } else {
                    Section {
                        Text(Self.joinedNote)
                    }
                }
            }
            .navigationTitle("Add a baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(!canAdd || trimmedName.isEmpty || isSaving)
                }
            }
            .onAppear {
                isShared = PersistenceController.shared.ownShare != nil
            }
        }
        .threeAMSheet()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        isSaving = true
        Task {
            let baby = await PersistenceController.shared.addBaby(name: trimmedName, birthDate: birthDate)
            if let sex {
                baby.sex = sex
                baby.managedObjectContext?.saveIfChanged()
            }
            dismiss()
        }
    }
}
