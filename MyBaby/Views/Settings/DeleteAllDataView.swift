import CoreData
import SwiftUI

/// "Delete all MyBaby data", from Settings › Your data.
///
/// Says exactly what goes, suggests saving a copy first, explains what happens to a shared log, and
/// offers to remove the appointments MyBaby added to the calendar. The parent types DELETE (any case),
/// then confirms with Face ID, Touch ID or the passcode when the iPhone has one. The deleting itself
/// is `DataWipe`; this sheet is closed by it as the app's screens are taken down.
struct DeleteAllDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var situation = DataWipe.Situation()
    @State private var babies: [Baby] = []
    @State private var security = DeviceSecurity.current()
    @State private var typed = ""
    @State private var removeCalendarEvents = true
    @State private var share: SharePayload?
    @State private var keepsakeBaby: Baby?
    @State private var exportError: String?
    @State private var confirmError: String?
    @State private var isConfirming = false

    /// What the parent types to turn on the button: DELETE, or the word in the app's language.
    static let confirmationWord = String(localized: "DELETE", comment: "The word typed to confirm deleting all data. Keep it in capitals, and use the same word in \"Type DELETE to confirm\".")

    var body: some View {
        NavigationStack {
            Form {
                introSection
                deletedSection
                exportSection
                if situation.isSharingOwnLog || situation.hasJoinedLog {
                    sharingSection
                }
                if situation.calendarHasEvents {
                    calendarSection
                }
                confirmSection
            }
            .navigationTitle("Delete all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .sheet(item: $share) { payload in
                ShareSheet(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
        .threeAMSheet()
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label {
                    Text("This can't be undone")
                        .font(.headline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.danger)
                }
                Text("MyBaby has no account to close. Your data is what MyBaby keeps on this iPhone and in your own iCloud, so deleting it all is the same as deleting your account. MyBaby then starts fresh, as if it was just installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    private var deletedSection: some View {
        Section("What will be deleted") {
            item(
                babies.count > 1 ? String(localized: "Every baby's log") : String(localized: "Your baby's log"),
                systemImage: "list.bullet.rectangle",
                logDetail
            )
            item(String(localized: "Your iCloud copy"), systemImage: "icloud", iCloudDetail)
            item(
                String(localized: "The private care page"),
                systemImage: "heart.text.square",
                String(localized: "Your Parent care check-ins, medicines and notes.")
            )
            item(
                String(localized: "Settings, widgets and reminders"),
                systemImage: "gearshape",
                String(localized: "Night shifts, units, reminders and cry alert settings. Widgets and Live Activities go back to empty, and scheduled reminders are cancelled.")
            )
            item(
                "Apple Watch",
                systemImage: "applewatch",
                String(localized: "The summary on your watch is cleared the next time it's in reach of this iPhone.")
            )
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                exportCSV()
            } label: {
                Label(babies.count > 1 ? "Export every baby's data (CSV)" : "Export all data (CSV)", systemImage: "square.and.arrow.up")
            }
            if babies.count > 1 {
                Menu {
                    ForEach(babies) { baby in
                        Button(baby.displayName) { keepsakeBaby = baby }
                    }
                } label: {
                    Label("Make a keepsake PDF", systemImage: "doc.richtext")
                }
            } else if let baby = babies.first {
                Button {
                    keepsakeBaby = baby
                } label: {
                    Label("Make a keepsake PDF", systemImage: "doc.richtext")
                }
            }
        } header: {
            Text("Save a copy first")
        } footer: {
            Text("Once it's deleted, MyBaby can't bring it back. Export your log as spreadsheet files, or keep the diary and its photos as a PDF, and save them in Files or send them to yourself.")
        }
        .sheet(item: $keepsakeBaby) { baby in
            KeepsakeView(baby: baby)
        }
    }

    private var sharingSection: some View {
        Section {
            if situation.isSharingOwnLog {
                Label {
                    Text(ownerSharingText)
                } icon: {
                    Image(systemName: "person.2.slash")
                        .foregroundStyle(Palette.warning)
                }
            }
            if situation.hasJoinedLog {
                Label {
                    Text(joinedText)
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.tint)
                }
            }
        } header: {
            Text("Sharing")
        }
    }

    private var calendarSection: some View {
        Section {
            Toggle("Also remove appointments from Calendar", isOn: $removeCalendarEvents)
        } footer: {
            Text(calendarFooter)
        }
    }

    /// What's removed from the calendar, and what happens about calendar access.
    private var calendarFooter: String {
        let what: String
        switch (situation.calendarSyncHasEvents, situation.calendarHasEventsAddedOneAtATime) {
        case (true, true):
            what = String(localized: "Removes the events Keep appointments in my calendar added, and the appointments you added with Add to Calendar on this iPhone.")
        case (true, false):
            what = String(localized: "Removes the events Keep appointments in my calendar added.")
        default:
            what = String(localized: "Removes the appointments you added with Add to Calendar on this iPhone.")
        }
        guard !situation.calendarHasFullAccess else {
            return what + " " + String(localized: "Events added from other phones stay.")
        }
        if situation.calendarAccessIsOff {
            return what + " " + String(localized: "Calendar access is off for MyBaby, so they would stay in your calendar. To remove them, first allow full calendar access for MyBaby in the Settings app.")
        }
        return what + " " + String(localized: "To find them, MyBaby asks for access to your calendar first. If you don't allow it, they stay in your calendar, and MyBaby tells you which ones.")
    }

    private var confirmSection: some View {
        Group {
            Section {
                TextField("DELETE", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Type DELETE to confirm")
            } header: {
                Text("Type DELETE to confirm")
            } footer: {
                Text(confirmFooter)
            }

            Section {
                Button(role: .destructive) {
                    Task { await confirm() }
                } label: {
                    HStack {
                        Label("Delete all MyBaby data", systemImage: "trash")
                        if isConfirming {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!isTypedCorrectly || isConfirming)
                .accessibilityHint(isTypedCorrectly ? "Deletes everything after you confirm it's you." : "Type DELETE above first.")
                if let confirmError {
                    NoticeLabel(confirmError)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: Words

    private var logDetail: String {
        let what = String(localized: "Feeds, diapers, sleep, photos, the diary, milestones, allergies, growth, vaccines, appointments and reports, on this iPhone.")
        guard !situation.babyNames.isEmpty else { return what }
        let names = situation.babyNames.formatted(.list(type: .and))
        return String(localized: "\(names): \(what)", comment: "A name or a list of names, then what they're about")
    }

    private var iCloudDetail: String {
        if situation.syncEnabled || situation.iCloudDeletionPending {
            return String(localized: "Everything MyBaby keeps in your iCloud, including the private inbox a nursery monitor sends alerts to. Your other devices signed in to the same Apple ID stop syncing and may remove their copy.")
        }
        return String(localized: "iCloud sync is off, so MyBaby checks your iCloud for a copy left from before and deletes it too.")
    }

    /// "Sam" or "Sam and Alex", or the fallback when iCloud doesn't know their names.
    private func names(_ names: [String], otherwise: String) -> String {
        names.isEmpty ? otherwise : names.formatted(.list(type: .and))
    }

    private var ownerSharingText: String {
        guard !situation.sharedWith.isEmpty else {
            return String(localized: "You share this log. Deleting it removes the shared log from your partner's iPhone too (and from anyone else you invited), because the share is deleted with your iCloud copy. If they'd like to keep a copy, ask them to export it first.")
        }
        let who = names(situation.sharedWith, otherwise: "")
        if situation.sharedWith.count > 1 {
            return String(localized: "You share this log with \(who). Deleting it removes the shared log from their iPhones too, because the share is deleted with your iCloud copy. If \(who) would like to keep a copy, ask them to export it first.", comment: "A list of several people's names")
        }
        return String(localized: "You share this log with \(who). Deleting it removes the shared log from \(who)'s iPhone too, because the share is deleted with your iCloud copy. If \(who) would like to keep a copy, ask them to export it first.", comment: "One person's name")
    }

    private var joinedText: String {
        guard !situation.joinedFrom.isEmpty else {
            return String(localized: "This iPhone leaves the log your partner shared with you, and it's removed from here. Your partner's own log isn't deleted, and they can invite you again later.")
        }
        let who = names(situation.joinedFrom, otherwise: "")
        return String(localized: "This iPhone leaves the log \(who) shared with you, and it's removed from here. \(who)'s own log isn't deleted, and they can invite you again later.")
    }

    private var confirmFooter: String {
        guard security.hasPasscode else {
            return String(localized: "Type DELETE (in any case). This iPhone has no passcode, so typing it is the last step.")
        }
        if security.method == .passcode {
            return String(localized: "Type DELETE (in any case). Then MyBaby asks for your passcode, to make sure it's you.")
        }
        return String(localized: "Type DELETE (in any case). Then MyBaby asks for \(security.method.name) or your passcode, to make sure it's you.", comment: "Face ID or Touch ID")
    }

    /// The word in the app's language, or DELETE, which always works.
    private var isTypedCorrectly: Bool {
        let word = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return [Self.confirmationWord, "DELETE"].contains { word.caseInsensitiveCompare($0) == .orderedSame }
    }

    private func item(_ title: String, systemImage: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.danger)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func load() {
        situation = DataWipe.Situation.current()
        babies = (try? context.fetch(Baby.fetchAll())) ?? []
        security = DeviceSecurity.current()
    }

    private func exportCSV() {
        do {
            share = SharePayload(items: try Exporter.everyBabyCSV(context: context))
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Face ID, Touch ID or the passcode, then the deleting. An iPhone without a passcode has nothing
    /// to ask for, so typing DELETE was the confirmation.
    @MainActor
    private func confirm() async {
        guard isTypedCorrectly, !isConfirming else { return }
        confirmError = nil
        isConfirming = true
        let result = await DeviceAuthentication.authenticate(
            reason: String(localized: "Confirm deleting all MyBaby data from this iPhone and your iCloud.")
        )
        isConfirming = false
        switch result {
        case .success, .noPasscode:
            let removingEvents = situation.calendarHasEvents && removeCalendarEvents
            // Not tied to this sheet, which closes as soon as the deleting starts.
            Task { @MainActor in
                await DataWipe.shared.run(removingCalendarEvents: removingEvents)
            }
        case .cancelled:
            break
        case .failed:
            confirmError = String(localized: "Couldn't confirm it's you, so nothing was deleted. Please try again.")
        }
    }
}

// MARK: - While deleting

/// Full screen while `DataWipe` runs, in place of the app's screens (see `RootView`).
struct DataWipeProgressView: View {
    @ObservedObject var wipe: DataWipe
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: min(iconSize, 96)))
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text("Deleting your data…")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: wipe.progress)
                .frame(maxWidth: 320)
                .accessibilityLabel("Deleting your data")
                .accessibilityValue("\(Int((wipe.progress * 100).rounded())) percent. \(wipe.step)")
            Text(wipe.step)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
            Text("Please keep MyBaby open until it's done.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.screenBackground)
    }
}

// MARK: - When it's done

/// Shown over the welcome screen once everything was deleted, with anything that didn't work.
struct DataWipeResultView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var wipe: DataWipe
    /// The outcome the sheet opened with; `wipe.outcome` has the latest, after Finish deleting iCloud copy.
    let outcome: DataWipe.Outcome
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private var current: DataWipe.Outcome { wipe.outcome ?? outcome }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Spacing.m) {
                        Image(systemName: current.iCloudPending ? "icloud.slash" : "checkmark.circle.fill")
                            .font(.system(size: min(iconSize, 110)))
                            .foregroundStyle(current.iCloudPending ? Palette.warning : Palette.ok)
                            .accessibilityHidden(true)
                        Text(current.title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(current.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.m)
                    .listRowBackground(Color.clear)
                }

                if !current.notes.isEmpty {
                    Section("Sharing") {
                        ForEach(current.notes, id: \.self) { note in
                            Label(note, systemImage: "person.2")
                        }
                    }
                }

                if !current.problems.isEmpty {
                    Section("What didn't work") {
                        ForEach(current.problems, id: \.self) { problem in
                            NoticeLabel(problem)
                        }
                    }
                }

                if current.iCloudPending {
                    Section {
                        Button {
                            Task { await wipe.finishICloudIfPending(userInitiated: true) }
                        } label: {
                            HStack {
                                Label("Finish deleting iCloud copy", systemImage: "icloud.slash")
                                if wipe.isFinishingICloud {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(wipe.isFinishingICloud)
                    } footer: {
                        Text("Until then, iCloud sync stays off. Turning it on, or restoring from iCloud, finishes deleting first.")
                    }
                }
            }
            .navigationTitle("Delete all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .threeAMSheet()
    }
}

// MARK: - Exporting before deleting

extension Exporter {
    /// The same CSV files as Settings › Export, for every baby, named after each baby when there's more
    /// than one, so nothing is left out before Delete all MyBaby data.
    @MainActor
    static func everyBabyCSV(context: NSManagedObjectContext) throws -> [URL] {
        let babies = (try? context.fetch(Baby.fetchAll())) ?? []
        var files: [URL] = []
        for baby in babies {
            let prefix = babies.count > 1 ? "MyBaby-\(baby.fileSafeName)" : "MyBaby"
            let activities = (try? context.fetch(baby.entries(Activity.fetch(newestFirst: false)))) ?? []
            let vaccines = (try? context.fetch(baby.entries(Vaccine.fetchAll()))) ?? []
            let appointments = (try? context.fetch(baby.entries(Appointment.fetchAll()))) ?? []
            let growth = (try? context.fetch(baby.entries(GrowthEntry.fetchAll()))) ?? []
            let periods = (try? context.fetch(baby.entries(TrackingPeriod.fetchAll()))) ?? []
            let diary = (try? context.fetch(baby.entries(DiaryEntry.fetchAll()))) ?? []
            files += [
                try write(activitiesCSV(activities), named: "\(prefix)-log.csv"),
                try write(vaccinesCSV(vaccines), named: "\(prefix)-vaccines.csv"),
                try write(appointmentsCSV(appointments), named: "\(prefix)-appointments.csv"),
                try write(growthCSV(GrowthReading.all(entries: growth, appointments: appointments)), named: "\(prefix)-growth.csv"),
                try write(trackingCSV(periods), named: "\(prefix)-tracking.csv"),
                try write(diaryCSV(diary), named: "\(prefix)-diary.csv"),
                try write(allergiesCSV(baby.allergyList()), named: "\(prefix)-allergies.csv"),
                try write(reactionsCSV(baby.allergyReactionList()), named: "\(prefix)-reactions.csv"),
            ]
        }
        return files
    }
}
