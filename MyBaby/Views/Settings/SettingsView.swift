import CloudKit
import CoreData
import SwiftUI
import UIKit

/// Pushed from the More tab, so it has no navigation stack of its own.
struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var baby: Baby
    @ObservedObject private var cloudStatus = CloudStatus.shared
    @AppStorage(SettingsKey.volumeUnit, store: .shared) private var unit: VolumeUnit = .ml
    @AppStorage(SettingsKey.temperatureUnit, store: .shared) private var temperatureUnit: TemperatureUnit = .localeDefault
    @AppStorage(SettingsKey.threeAMMode) private var threeAMMode: ThreeAMMode = .off
    @AppStorage(SettingsKey.gapReminderEnabled, store: .shared) private var gapReminderEnabled = false

    @FetchRequest private var activities: FetchedResults<Activity>
    @FetchRequest private var vaccines: FetchedResults<Vaccine>
    @FetchRequest private var appointments: FetchedResults<Appointment>
    @FetchRequest private var growthEntries: FetchedResults<GrowthEntry>
    @FetchRequest private var trackingPeriods: FetchedResults<TrackingPeriod>
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>

    @State private var share: SharePayload?
    @State private var showingPermissionAlert = false
    @State private var exportError: String?
    @State private var isShared = false
    @State private var confirmingSyncForInvite = false
    @AppStorage(SettingsKey.iCloudSync, store: .shared) private var syncEnabled = false
    @AppStorage(SettingsKey.iCloudDeletionPending, store: .shared) private var iCloudDeletionPending = false
    @State private var isPreparingShare = false
    @State private var addingBaby = false
    @State private var confirmingDeleteICloudCopy = false
    @State private var deletingAllData = false
    @State private var importingFromApp = false
    /// Changes when the import sheet closes, so Recent imports reads its list again.
    @State private var importsVersion = UUID()
    /// What the iCloud switch was just set to, until turning sync on or off finishes or is refused.
    @State private var syncRequest: Bool?

    init(baby: Baby) {
        self.baby = baby
        // The whole log, but only for the counts in the footer and the CSV export. In batches, so
        // opening Settings reads only which entries there are; the entries themselves are read
        // only when they're exported.
        _activities = FetchRequest(fetchRequest: Self.inBatches(baby.entries(Activity.fetch(newestFirst: false))))
        _vaccines = FetchRequest(fetchRequest: Self.inBatches(baby.entries(Vaccine.fetchAll())))
        _appointments = FetchRequest(fetchRequest: Self.inBatches(baby.entries(Appointment.fetchAll())))
        _growthEntries = FetchRequest(fetchRequest: Self.inBatches(baby.entries(GrowthEntry.fetchAll())))
        _trackingPeriods = FetchRequest(fetchRequest: Self.inBatches(baby.entries(TrackingPeriod.fetchAll())))
    }

    private static func inBatches<Entry: NSFetchRequestResult>(_ request: NSFetchRequest<Entry>) -> NSFetchRequest<Entry> {
        request.fetchBatchSize = 50
        return request
    }

    var body: some View {
        Form {
            babySection

            ParentsSection()

            familySection

            Section("Units") {
                Picker("Bottle amounts", selection: $unit) {
                    ForEach(VolumeUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                Picker("Temperature", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
            }

            Section {
                Picker("3 AM mode", selection: $threeAMMode) {
                    ForEach(ThreeAMMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("3 AM mode turns the whole app dark with a dim red tint for night feeds, so it's easy on sleepy eyes and doesn't light up the room. At night follows the hours of your night shifts, or 9 PM to 7 AM if you don't use them.")
            }

            // The feeding reminder (off, every few hours or smart) and the diaper check.
            CareRemindersSection()

            Section {
                Toggle("Haven't logged in a while", isOn: $gapReminderEnabled)
            } header: {
                Text("Reminders")
            } footer: {
                Text("Appointment reminders are set on each appointment. \"Haven't logged in a while\" nudges you when nothing has been logged for more than 5 hours of the day (8 at night), never while you're off duty on a night shift.")
            }

            // "After vaccines": a heads-up the morning a later reaction can start, per phone.
            VaccineFollowUpReminderSection()

            // "Keep appointments in my calendar", per phone.
            CalendarSyncSection()

            Section {
                Button {
                    exportCSV()
                } label: {
                    Label(babies.count > 1 ? "Export \(baby.displayName)'s data (CSV)" : "Export all data (CSV)", systemImage: "square.and.arrow.up")
                }
                Button {
                    importingFromApp = true
                } label: {
                    Label("Import from another app", systemImage: "square.and.arrow.down")
                }
                .disabled(!cloudStatus.canEdit(baby))
                .accessibilityHint("Brings in a log exported from Huckleberry, Glow Baby, Nara Baby, MyBaby on another iPhone, or any CSV.")
            } header: {
                Text("Your data")
            } footer: {
                Text(dataFooter)
            }
            .sheet(isPresented: $importingFromApp, onDismiss: { importsVersion = UUID() }) {
                ImportView(baby: baby)
            }

            RecentImportsSection()
                .id(importsVersion)

            // Everything MyBaby keeps, on this iPhone and in iCloud. There's no account besides.
            Section {
                Button(role: .destructive) {
                    deletingAllData = true
                } label: {
                    Label("Delete all MyBaby data", systemImage: "trash")
                }
                .accessibilityHint("Explains what's deleted, then asks you to confirm.")
            } footer: {
                Text("Deletes every baby's log, photos and diary, your private care page, and your settings, widgets and reminders from this iPhone, along with your iCloud copy and the summary on your Apple Watch. MyBaby has no account, so this is everything.")
            }
            .sheet(isPresented: $deletingAllData) {
                DeleteAllDataView()
            }

            Section {
                Text("MyBaby has no servers and the developers never receive your baby's data. Your log stays on this iPhone, or in your own iCloud, end-to-end encrypted, if you turn on sync.")
                    .font(.subheadline)
                NavigationLink("How your data is kept", value: MoreRoute.privacy)
                NavigationLink("Terms of Use") {
                    TermsOfUseView()
                }
            } header: {
                Text("Privacy")
            }

            Section("Help & support") {
                Link(destination: AppLinks.support) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                FeedbackRow()
                Link(destination: AppLinks.supportEmailURL) {
                    Label("Email support", systemImage: "envelope")
                }
            }

            Section {
                Text("MyBaby helps you keep track of your baby's care. It isn't medical advice — always contact your pediatrician with questions or concerns, and call emergency services in an emergency.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            // Only in debug builds, for App Store screenshots (see docs/screenshots.md).
            Section {
                Button("Load sample data") { SampleData.load() }
                // Debug builds only; must never run in release builds (see `createCloudKitSchema`).
                Button {
                    isCreatingSchema = true
                    Task {
                        let result = await PersistenceController.shared.createCloudKitSchema()
                        isCreatingSchema = false
                        CloudStatus.shared.lastError = result
                    }
                } label: {
                    HStack {
                        Text(isCreatingSchema ? "Creating iCloud schema… (can take a few minutes)" : "Create iCloud schema")
                        if isCreatingSchema {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isCreatingSchema)
            } header: {
                Text("About · Debug build")
            } footer: {
                Text("Load sample data adds a baby named Ava with two weeks of sample entries and turns on a night plan, then shows her. It doesn't change any other baby's log. Create iCloud schema creates every record type in CloudKit's Development environment, ready to deploy to Production in the CloudKit Console.")
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: gapReminderEnabled) { _, enabled in
            guard enabled else {
                GapReminder.refresh(context: context)
                return
            }
            Task {
                if await NotificationManager.requestAuthorization() {
                    GapReminder.refresh(context: context)
                } else {
                    gapReminderEnabled = false
                    showingPermissionAlert = true
                }
            }
        }
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow notifications for MyBaby in the Settings app to get reminders.")
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $share) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Baby

    /// Every baby on this iPhone, each opening their own profile. Showing only the current baby
    /// here hid the others' details, so twins and siblings are all listed.
    private var babySection: some View {
        Section {
            DuplicateBabyCard()
            ForEach(babies) { other in
                BabyProfileLink(baby: other) {
                    BabyRow(baby: other, isCurrent: babies.count > 1 && other == baby)
                }
            }
            Button {
                addingBaby = true
            } label: {
                Label("Add a baby", systemImage: "plus")
            }
            .disabled(!cloudStatus.canAddBabies)
        } header: {
            Text(babies.count > 1 ? "Babies" : "Baby")
        } footer: {
            if !cloudStatus.canAddBabies {
                Text(AddBabyView.joinedNote)
            } else if babies.count > 1 {
                Text("Tap a baby to edit their details. The check marks the baby the app is showing.")
            }
        }
        .sheet(isPresented: $addingBaby) {
            AddBabyView()
        }
    }

    // MARK: Family sharing

    private var familySection: some View {
        let persistence = PersistenceController.shared
        let joined = persistence.isJoined(baby)
        let sharing = joined || isShared
        // Only for a log nobody else uses: a shared log lives in an iCloud zone the partner uses too.
        let canDeleteICloudCopy = iCloudDeletionPending || (syncEnabled && !sharing && !cloudStatus.hasJoinedLog)

        return Section {
            Toggle("Sync with iCloud", isOn: syncBinding)
                // Sharing needs iCloud; stop sharing (Manage sharing) before turning it off.
                .disabled(sharing)
            if syncEnabled { SyncStatusRow() }
            if joined {
                Label("Your partner shared \(baby.name)'s log with you", systemImage: "person.2.fill")
            }
            Button {
                if syncEnabled {
                    openSharing(turningOnSync: false)
                } else {
                    confirmingSyncForInvite = true
                }
            } label: {
                HStack {
                    Label(
                        sharing ? "Manage sharing" : "Invite partner",
                        systemImage: sharing ? "person.2.badge.gearshape" : "person.badge.plus"
                    )
                    if isPreparingShare {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparingShare)
            if canDeleteICloudCopy {
                Button(role: .destructive) {
                    confirmingDeleteICloudCopy = true
                } label: {
                    Label(
                        iCloudDeletionPending ? "Finish deleting iCloud copy" : "Delete my iCloud copy",
                        systemImage: "icloud.slash"
                    )
                }
                .confirmationDialog(
                    "Delete your iCloud copy?", isPresented: $confirmingDeleteICloudCopy, titleVisibility: .visible
                ) {
                    Button("Delete iCloud copy", role: .destructive) {
                        Task { await PersistenceController.shared.deleteICloudCopy() }
                    }
                } message: {
                    Text("This turns off iCloud sync and deletes your log from your iCloud. The log on this iPhone stays just as it is. Other devices signed in to your Apple ID stop getting updates and may remove their copy. You can turn sync back on anytime to back up this iPhone's log again.")
                }
            }
        } header: {
            Text("iCloud & sharing")
        } footer: {
            Text(familyFooter(sharing: sharing))
        }
        .onAppear { isShared = isSharedNow }
        .onChange(of: cloudStatus.shareChanged) {
            isShared = isSharedNow
        }
        .confirmationDialog("Sharing uses iCloud", isPresented: $confirmingSyncForInvite, titleVisibility: .visible) {
            Button("Turn on iCloud and invite") { openSharing(turningOnSync: true) }
        } message: {
            Text("Your log will sync through your iCloud account so your partner can see it and add to it.")
        }
    }

    /// Whether the log is shared: this parent invited someone, or was invited to this baby's log.
    private var isSharedNow: Bool {
        let persistence = PersistenceController.shared
        return persistence.existingShare(for: baby) != nil || persistence.ownShare != nil
    }

    private func familyFooter(sharing: Bool) -> String {
        if iCloudDeletionPending {
            return String(localized: "Deleting your iCloud copy didn't finish, so iCloud sync is off and your log is only on this iPhone. Tap Finish deleting iCloud copy to try again. Turning sync on finishes it first.")
        }
        // Only the parent who created the log can invite people, and choose what they can do.
        let viewOnlyTip = String(localized: "To add a grandparent or a nanny who can look but not change anything, invite them and set their permission to View only.")
        if sharing {
            let shared = String(localized: "You both see and add to the same log. Changes show up on the other iPhone within a few seconds when it's online.")
            return PersistenceController.shared.isJoined(baby) ? shared : shared + " " + viewOnlyTip
        }
        if syncEnabled {
            return String(localized: "Your log is backed up to your iCloud and kept in sync on your devices signed in to the same Apple ID. Invite your partner to share it with them.") + " " + viewOnlyTip
        }
        return String(localized: "Your log is stored only on this iPhone. Turn on iCloud to back it up, or invite your partner to share it, which turns iCloud on.")
    }

    #if DEBUG
    /// While Create iCloud schema runs, which can take a few minutes.
    @State private var isCreatingSchema = false
    #endif

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { syncRequest ?? syncEnabled },
            set: { enabled in
                syncRequest = enabled
                Task {
                    // When iCloud can't be used, sync stays off, the reason shows in an alert, and
                    // dropping the request flips the switch back.
                    await PersistenceController.shared.setSyncEnabled(enabled)
                    syncRequest = nil
                }
            }
        )
    }

    private func openSharing(turningOnSync: Bool) {
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            let persistence = PersistenceController.shared
            if turningOnSync {
                // Stop if iCloud can't be used; the reason is already showing.
                guard await persistence.setSyncEnabled(true) else { return }
            }
            // Turning on iCloud reopens the stores, so look the baby up again rather than reuse the old object.
            guard let current = Baby.current(in: persistence.viewContext) else { return }
            do {
                let share = try await persistence.share(current)
                // Never anything but the log's share, like the nursery monitor's own (see `isLogShare`).
                guard PersistenceController.isLogShare(share) else {
                    let id = share.recordID
                    // Not localized: the details are for the developer.
                    let details = "\(id.zoneID.zoneName) · \(id.recordName) · \(persistence.lastShareSource) · \(share[CKShare.SystemFieldKey.title] as? String ?? "no title")"
                    CloudStatus.shared.lastError = String(localized: "MyBaby couldn't prepare the invitation for your log. Please send a screenshot of this with Settings › Send feedback.\n\nDetails: \(details)")
                    return
                }
                isShared = true
                CloudSharing.present(share, for: current)
            } catch {
                CloudStatus.shared.lastError = CloudErrors.sharingMessage(for: error)
            }
        }
    }

    // MARK: Data

    private var dataFooter: String {
        let counts = [
            String(localized: "\(activities.count) entries", comment: "Part of a list of counts in Settings › Your data"),
            String(localized: "\(vaccines.count) vaccines", comment: "Part of a list of counts in Settings › Your data"),
            String(localized: "\(appointments.count) appointments", comment: "Part of a list of counts in Settings › Your data"),
        ].formatted(.list(type: .and))
        let whose = babies.count > 1
            ? String(localized: "\(counts) for \(baby.displayName).", comment: "A list of counts, then the baby's name")
            : String(localized: "\(counts).", comment: "A list of counts, as a sentence")
        let stored = syncEnabled
            ? String(localized: "Stored on this iPhone and in iCloud. Only people you invite can see them.")
            : String(localized: "Stored only on this iPhone.")
        return whose + " " + stored
    }

    private func exportCSV() {
        // Named after the baby when there's more than one, so twins' files don't get mixed up.
        let prefix = babies.count > 1 ? "MyBaby-\(baby.fileSafeName)" : "MyBaby"
        do {
            let files = [
                try Exporter.write(Exporter.activitiesCSV(Array(activities)), named: "\(prefix)-log.csv"),
                try Exporter.write(Exporter.vaccinesCSV(Array(vaccines)), named: "\(prefix)-vaccines.csv"),
                try Exporter.write(Exporter.appointmentsCSV(Array(appointments)), named: "\(prefix)-appointments.csv"),
                try Exporter.write(Exporter.growthCSV(GrowthReading.all(entries: Array(growthEntries), appointments: Array(appointments))), named: "\(prefix)-growth.csv"),
                try Exporter.write(Exporter.trackingCSV(Array(trackingPeriods)), named: "\(prefix)-tracking.csv"),
                try Exporter.write(Exporter.diaryCSV((try? context.fetch(baby.entries(DiaryEntry.fetchAll()))) ?? []), named: "\(prefix)-diary.csv"),
                try Exporter.write(Exporter.allergiesCSV(baby.allergyList()), named: "\(prefix)-allergies.csv"),
                try Exporter.write(Exporter.reactionsCSV(baby.allergyReactionList()), named: "\(prefix)-reactions.csv"),
            ]
            share = SharePayload(items: files)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
