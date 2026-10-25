import CoreData
import SwiftUI

struct OnboardingView: View {
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml

    @State private var name = ""
    @State private var birthDate = Date.now
    @State private var sex: BabySex?
    @State private var backUpToICloud = false
    /// Optional. Saved as parent 1 (this iPhone's owner) and parent 2; see `ParentSettings`.
    @State private var yourName = ""
    @State private var partnerName = ""
    @ScaledMetric(relativeTo: .title) private var heroSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Spacing.m) {
                        Text("👶")
                            .font(.system(size: min(heroSize, 110)))
                            .frame(width: min(heroSize, 110) * 1.5, height: min(heroSize, 110) * 1.5)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        Text("Welcome to MyBaby")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Log feedings, diapers, sleep, baths, medicine, vaccines and appointments in a tap or two, and share clear reports with your pediatrician.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.m)
                    .listRowBackground(Color.clear)
                }

                Section("About your baby") {
                    TextField("Baby's name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                    DateField("Birthday", selection: $birthDate, includesTime: false)
                    BabySexPicker(selection: $sex)
                }

                Section {
                    TextField("Your name", text: $yourName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    TextField("Your partner's name", text: $partnerName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Parents")
                } footer: {
                    Text("Optional. Night shifts and \"Handled by\" use your names, and this iPhone is set up as yours. You can change them in Settings › Parents.")
                }

                Section("Bottle amounts in") {
                    Picker("Units", selection: $unit) {
                        ForEach(VolumeUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Back up to iCloud", isOn: $backUpToICloud)
                        .onChange(of: backUpToICloud) { _, wanted in
                            guard wanted else { return }
                            Task {
                                // Checked now rather than after Get started: when iCloud can't be
                                // used, the reason shows in an alert and the switch goes back off.
                                let available = await PersistenceController.shared.confirmICloudAvailable()
                                if !available {
                                    backUpToICloud = false
                                }
                            }
                        }
                } header: {
                    Text("Where to keep the log")
                } footer: {
                    Text(backUpToICloud
                         ? "Your log is kept on this iPhone and in your iCloud, so it's safe if you lose your phone."
                         : "Your log stays only on this iPhone. You can turn on iCloud later in More › Settings, and inviting your partner turns it on.")
                }

                Section {
                    Button {
                        let baby = PersistenceController.shared.createBaby(name: trimmedName, birthDate: birthDate)
                        ParentSettings.saveFromOnboarding(yourName: yourName, partnerName: partnerName, context: PersistenceController.shared.viewContext)
                        if let sex {
                            baby.sex = sex
                            baby.managedObjectContext?.saveIfChanged()
                        }
                        if backUpToICloud {
                            Task {
                                // Checked again in case iCloud went away since the switch was
                                // turned on. If it can't start, the log stays on this iPhone and
                                // the alert says why; sync can be turned on later in Settings.
                                await PersistenceController.shared.setSyncEnabled(true)
                            }
                        }
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedName.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if trimmedName.isEmpty {
                        Text("Add your baby's name to get started. You can change everything later in Settings.")
                    }
                }

                Section {
                    Label {
                        Text("Your partner already set up the baby? Ask them to tap **Invite partner** in More › Settings and send you the link. Open it on this iPhone and you'll share the same log.")
                    } icon: {
                        Image(systemName: "person.2.fill")
                    }
                    .font(.subheadline)
                } header: {
                    Text("Joining your partner")
                }

                Section {
                    Button {
                        Task { await PersistenceController.shared.restoreFromICloud() }
                    } label: {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                } header: {
                    Text("Used MyBaby with iCloud before?")
                } footer: {
                    Text("On a new iPhone or after reinstalling, bring back the log you kept in iCloud. Use the same Apple ID as before.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    OnboardingView()
}
