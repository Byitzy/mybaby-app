import AppIntents
import CloudKit
import CoreData
import Foundation
import UserNotifications
import WidgetKit

/// "Delete all MyBaby data" (Settings › Your data, confirmed in `DeleteAllDataView`).
///
/// MyBaby has no account and no server, so this is the whole account: everything MyBaby keeps on this
/// iPhone and in the parent's own iCloud. While it runs, the app's screens are taken down (like turning
/// iCloud on or off, see `PersistenceController.takeDownContent`) and `RootView` shows
/// `DataWipeProgressView`, so no screen uses the stores while they're removed. In order:
/// 1. **Stops everything running:** cry alerts, monitor mode, white noise, the breastfeeding timer,
///    every Live Activity, and all pending and delivered notifications.
/// 2. **iCloud,** when sync is or was on, or iCloud can be reached:
///    - logs other parents shared are left, with Core Data's purge, like leaving a shared log;
///    - sync is turned off, so the container never sees its zones disappear;
///    - Core Data's zones in the private database are deleted, like Delete my iCloud copy, which also
///      deletes the share of the log, so it's removed from the partner's phone too;
///    - this phone's nursery monitor inbox (`MyBabyAlertInbox`) is deleted, other parents' inboxes are
///      left, and every subscription MyBaby saved in the private and shared databases is deleted.
///    If any of it can't be done (offline, signed out), `iCloudDeletionPending` stays set, the same flag
///    Delete my iCloud copy uses: turning sync on finishes it first, Settings offers Finish deleting
///    iCloud copy, and `finishICloudIfPending` tries again by itself when the app opens with no log.
/// 3. **Calendar,** if the parent chose: the events Keep appointments in my calendar added, and the ones
///    added one at a time with Add to Calendar on this iPhone. Removing them needs full calendar access,
///    which is asked for only then, before anything is deleted; without it, the summary names the
///    events that stayed.
/// 4. **This iPhone:** the database files (`PersistenceController.eraseLocalStores`), the widgets'
///    snapshot, Application Support (calendar links, crash reports) and temporary exports.
/// 5. **Settings:** both `UserDefaults` domains. The pending flag is set again afterwards if needed.
///    MyBaby keeps nothing in the Keychain.
/// 6. **Widgets and the Apple Watch** are told there's no baby.
/// 7. **A fresh start:** new, empty stores with sync off, back to the welcome screen as on a first launch.
///
/// Every step carries on when another fails, and can run again safely. What didn't work is collected
/// and shown in plain words at the end (`Outcome`).
@MainActor
final class DataWipe: ObservableObject {
    static let shared = DataWipe()

    /// From the moment the parent confirms until the welcome screen is back.
    @Published private(set) var isRunning = false
    /// 0–1, for the progress bar.
    @Published private(set) var progress: Double = 0
    /// What's being done now, e.g. "Deleting your iCloud copy…".
    @Published private(set) var step = ""
    /// What happened, shown over the welcome screen once it's done.
    @Published var outcome: Outcome?
    /// While the iCloud part is tried again (`finishICloudIfPending`).
    @Published private(set) var isFinishingICloud = false

    private init() {}

    // MARK: What happened

    struct Outcome: Identifiable, Equatable {
        let id = UUID()
        /// The iCloud part is still to do; `PersistenceController.isICloudDeletionPending` is set.
        var iCloudPending = false
        /// Whether sync was on, or an earlier iCloud deletion hadn't finished, so there was a copy.
        var usedICloud = false
        /// Sync was off and iCloud couldn't be used on this iPhone (e.g. signed out), so it wasn't touched.
        var skippedICloud = false
        /// What else didn't work, in plain words.
        var problems: [String] = []
        /// What happens next on other phones, e.g. the partner's.
        var notes: [String] = []

        var title: String {
            iCloudPending || !problems.isEmpty
                ? String(localized: "Deleted from this iPhone")
                : String(localized: "All deleted", comment: "Title after Delete all MyBaby data worked")
        }

        var message: String {
            guard iCloudPending else {
                if skippedICloud {
                    return String(localized: "All MyBaby data was deleted from this iPhone. iCloud sync was off and iCloud isn't available on this iPhone, so nothing was changed there. To check for a copy from before, look in iPhone Settings › your name › iCloud › Manage Storage.")
                }
                if problems.isEmpty {
                    return String(localized: "All MyBaby data was deleted from this iPhone and your iCloud.")
                }
                return String(localized: "MyBaby data was deleted from this iPhone and your iCloud, but a few things didn't work.")
            }
            if usedICloud {
                return String(localized: "All MyBaby data was deleted from this iPhone. Your iCloud copy couldn't be deleted yet, because iCloud couldn't be reached. MyBaby finishes it by itself the next time it opens while online and signed in to iCloud, or you can tap Finish deleting iCloud copy now.")
            }
            return String(localized: "All MyBaby data was deleted from this iPhone. MyBaby couldn't reach iCloud to check for a copy there, so it checks again by itself the next time it opens while online. You can also tap Finish deleting iCloud copy now.")
        }
    }

    // MARK: What there is

    /// What the confirmation explains: the babies, iCloud, and whether the log is shared.
    struct Situation: Equatable {
        var babyNames: [String] = []
        var syncEnabled = false
        var iCloudDeletionPending = false
        /// This iPhone created the log and invited someone.
        var isSharingOwnLog = false
        /// The people it's shared with, by name when iCloud knows it.
        var sharedWith: [String] = []
        /// This iPhone joined a log someone else shared.
        var hasJoinedLog = false
        /// Who shared it, by name when iCloud knows it.
        var joinedFrom: [String] = []
        /// Keep appointments in my calendar is on, or added events it still remembers, or Add to
        /// Calendar added events on this iPhone.
        var calendarHasEvents = false
        /// Keep appointments in my calendar is on, or added events it still remembers.
        var calendarSyncHasEvents = false
        /// Add to Calendar added events on this iPhone, which are removed with the others.
        var calendarHasEventsAddedOneAtATime = false
        /// MyBaby can find and remove calendar events now, without asking.
        var calendarHasFullAccess = false
        /// Calendar access was turned down, so iOS won't ask again and the events would stay.
        var calendarAccessIsOff = false

        @MainActor
        static func current() -> Situation {
            let persistence = PersistenceController.shared
            var situation = Situation()
            let babies = (try? persistence.viewContext.fetch(Baby.fetchAll())) ?? []
            situation.babyNames = babies.map(\.displayName)
            situation.syncEnabled = PersistenceController.isSyncEnabled
            situation.iCloudDeletionPending = PersistenceController.isICloudDeletionPending
            if situation.syncEnabled {
                if let share = persistence.ownShare {
                    situation.isSharingOwnLog = true
                    situation.sharedWith = share.participants
                        .filter { $0.role != .owner && $0.acceptanceStatus != .removed }
                        .compactMap { DataWipe.name(of: $0.userIdentity) }
                }
                situation.hasJoinedLog = persistence.hasJoinedLog
                if situation.hasJoinedLog {
                    var owners: [String] = []
                    for baby in babies where persistence.isJoined(baby) {
                        if let name = persistence.existingShare(for: baby).flatMap({ DataWipe.name(of: $0.owner.userIdentity) }),
                           !owners.contains(name) {
                            owners.append(name)
                        }
                    }
                    situation.joinedFrom = owners
                }
            }
            let calendar = CalendarSync.shared
            calendar.refreshAccess()
            situation.calendarHasFullAccess = calendar.hasFullAccess
            situation.calendarAccessIsOff = calendar.isAccessOff
            situation.calendarSyncHasEvents = calendar.isEnabled || calendar.hasAddedEvents
            situation.calendarHasEventsAddedOneAtATime = calendar.hasEventsAddedOneAtATime
            situation.calendarHasEvents = situation.calendarSyncHasEvents || situation.calendarHasEventsAddedOneAtATime
            return situation
        }
    }

    /// "Sam", from the name iCloud has for someone, or `nil` when it has none.
    nonisolated static func name(of identity: CKUserIdentity) -> String? {
        guard let components = identity.nameComponents else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Deleting

    /// Deletes everything (see the type's description). `removingCalendarEvents` also removes the
    /// appointments Keep appointments in my calendar added and the ones added with Add to Calendar.
    /// Never throws: what didn't work is in `outcome`.
    func run(removingCalendarEvents: Bool) async {
        guard !isRunning else { return }
        if removingCalendarEvents {
            // Asked here, while the confirmation is still on screen, so it's clear why MyBaby asks.
            await requestCalendarAccessIfNeeded()
            guard !isRunning else { return }
        }
        isRunning = true
        outcome = nil
        let persistence = PersistenceController.shared
        let syncWasOn = PersistenceController.isSyncEnabled
        let situation = Situation.current()
        var result = Outcome()
        result.usedICloud = syncWasOn || PersistenceController.isICloudDeletionPending
        // Read while the stores are still open with iCloud: the logs other parents shared with this iPhone.
        let joinedZones = syncWasOn ? joinedLogZones() : []

        show(String(localized: "Getting ready…"), 0.02)
        await persistence.takeDownContent(showing: String(localized: "Deleting your data…"))

        // 1. Nothing may keep running, buzzing or writing.
        show(String(localized: "Stopping alerts, sounds and timers…"), 0.08)
        await stopEverything()

        // 2. iCloud.
        show(String(localized: "Deleting your iCloud copy…"), 0.15)
        let iCloudReachable = await persistence.iCloudAvailability() == nil
        if result.usedICloud || iCloudReachable {
            // Set first, so an interruption (the app closed, the phone switched off) finishes it later.
            UserDefaults.shared.set(true, forKey: SettingsKey.iCloudDeletionPending)
            if syncWasOn {
                await leaveJoinedLogs(joinedZones)
                show(String(localized: "Deleting your iCloud copy…"), 0.25)
                // The container must never see its zones disappear while it's syncing (see
                // `deleteICloudCopy`), so iCloud is turned off before they're deleted.
                persistence.reopenStores(sync: false)
            }
            show(String(localized: "Deleting your iCloud copy…"), 0.3)
            let failures = await deleteICloudData()
            if failures.isEmpty {
                UserDefaults.shared.set(false, forKey: SettingsKey.iCloudDeletionPending)
            } else {
                result.iCloudPending = true
                for failure in failures {
                    print("MyBaby: couldn't delete part of the iCloud copy: \(failure)")
                }
            }
        } else {
            result.skippedICloud = true
        }
        if situation.isSharingOwnLog {
            result.notes.append(Self.sharedLogNote(sharedWith: situation.sharedWith, iCloudPending: result.iCloudPending))
        }
        if situation.hasJoinedLog {
            if situation.joinedFrom.isEmpty {
                result.notes.append(String(localized: "This iPhone left your partner's shared log. Their own log wasn't deleted."))
            } else {
                let who = Self.list(situation.joinedFrom, otherwise: "")
                result.notes.append(String(localized: "This iPhone left the log \(who) shared with you. \(who)'s own log wasn't deleted.", comment: "Both arguments are the same name, or names, of the people who shared the log"))
            }
        }

        // 3. The calendar.
        show(String(localized: "Removing calendar events…"), 0.5)
        clearCalendar(removingEvents: removingCalendarEvents, into: &result)

        // 4. This iPhone. Nothing above may run while the stores are gone, so this is one synchronous step.
        show(String(localized: "Deleting the log on this iPhone…"), 0.6)
        MilestoneImages.removeCachedImages()
        let storeErrors = persistence.eraseLocalStores()
        for error in storeErrors {
            print("MyBaby: couldn't remove a database file: \(error)")
        }
        if Self.hasAnyData() {
            result.problems.append(String(localized: "Some of the log couldn't be deleted from this iPhone. Please try again, or delete the MyBaby app from your iPhone to remove it."))
        } else if !storeErrors.isEmpty {
            result.problems.append(String(localized: "A few of the log's old files couldn't be removed from this iPhone. MyBaby doesn't use them any more, and deleting the app from your iPhone removes them."))
        }
        show(String(localized: "Deleting files on this iPhone…"), 0.7)
        result.problems += deleteFiles()

        // 5. Settings, with the iCloud flag kept if the iCloud part is still to do.
        show(String(localized: "Clearing settings…"), 0.8)
        clearSettings()
        if result.iCloudPending {
            UserDefaults.shared.set(true, forKey: SettingsKey.iCloudDeletionPending)
        }

        // 6. Widgets, the Apple Watch and Siri.
        show(String(localized: "Clearing widgets and Apple Watch…"), 0.9)
        WidgetSnapshot.save(nil)
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.sendEmpty()
        // Siri forgets the babies' names.
        MyBabyShortcuts.updateAppShortcutParameters()

        // 7. A fresh start, as on a first launch.
        show(String(localized: "Starting fresh…"), 1)
        SyncStatus.shared.restart()
        AlertInboxes.shared.forgetEverything()
        DuplicateBabies.shared.check()
        NavigationMemory.shared.reset()
        FeedingTimer.shared.reload()
        CryAlertTaps.shared.openToday = false
        let cloudStatus = CloudStatus.shared
        cloudStatus.lastError = nil
        cloudStatus.shareChanged = UUID()
        cloudStatus.reloadingMessage = nil
        // Now that nothing is being reopened: the widgets and the watch get the empty state for certain.
        WidgetSnapshotWriter.shared.refreshNow(force: true)
        isRunning = false
        outcome = result
    }

    private func show(_ text: String, _ value: Double) {
        step = text
        progress = value
    }

    /// "Sam", "Sam and Alex", or `otherwise` when no name is known.
    private static func list(_ names: [String], otherwise: String) -> String {
        names.isEmpty ? otherwise : names.formatted(.list(type: .and))
    }

    /// What happens to the log this iPhone shared, on the phones it was shared with: "Sam's iPhone",
    /// "your partner's iPhone" without a name, or "their iPhones" for several people.
    private static func sharedLogNote(sharedWith names: [String], iCloudPending: Bool) -> String {
        if iCloudPending {
            switch names.count {
            case 0: return String(localized: "The shared log stays on your partner's iPhone until your iCloud copy is deleted.")
            case 1: return String(localized: "The shared log stays on \(names[0])'s iPhone until your iCloud copy is deleted.")
            default: return String(localized: "The shared log stays on their iPhones until your iCloud copy is deleted.", comment: "The phones of the people the log was shared with")
            }
        }
        switch names.count {
        case 0: return String(localized: "The shared log is removed from your partner's iPhone the next time it's online.")
        case 1: return String(localized: "The shared log is removed from \(names[0])'s iPhone the next time it's online.")
        default: return String(localized: "The shared log is removed from their iPhones the next time it's online.", comment: "The phones of the people the log was shared with")
        }
    }

    // MARK: 1. Stopping

    private func stopEverything() async {
        if NurseryMonitor.shared.isActive {
            NurseryMonitor.shared.stop()
        }
        if CryMonitor.shared.isListening {
            CryMonitor.shared.stop()
        }
        CryMonitor.shared.forgetEpisodes()
        WhiteNoise.shared.setColor(.off)
        FeedingTimer.shared.discard()
        await LiveActivities.endAll()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        try? await center.setBadgeCount(0)
    }

    // MARK: 2. iCloud

    /// The zones of the logs other parents shared with this iPhone, from the shared store.
    private func joinedLogZones() -> [CKRecordZone.ID] {
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.sharedStore else { return [] }
        let shares = (try? persistence.container.fetchShares(in: sharedStore)) ?? []
        var zones: [CKRecordZone.ID] = []
        for share in shares where !zones.contains(share.recordID.zoneID) {
            zones.append(share.recordID.zoneID)
        }
        return zones
    }

    /// Leaves each log another parent shared, the way leaving it in Manage sharing does: Core Data
    /// removes this iPhone from the share and purges the log here. Only while sync is still on. If it
    /// doesn't work (offline), `leaveSharedZones` tries again from the shared database.
    private func leaveJoinedLogs(_ zoneIDs: [CKRecordZone.ID]) async {
        let persistence = PersistenceController.shared
        guard !zoneIDs.isEmpty, let sharedStore = persistence.sharedStore else { return }
        await persistence.waitForCloudKitSetup(of: sharedStore, timeout: .seconds(10))
        let container = persistence.container
        for zoneID in zoneIDs {
            // Offline, the purge may not call back for a long time, so it isn't waited for forever.
            let error = await Self.waitForCallback(timeout: 30) { done in
                container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore) { _, error in
                    done(error)
                }
            }
            if let error {
                print("MyBaby: couldn't leave a shared log: \(error)")
            }
        }
        // The purge doesn't reach objects already loaded.
        persistence.viewContext.reset()
    }

    /// Deletes what MyBaby keeps in this Apple ID's iCloud, while sync is off. Each part is tried even
    /// if another fails, and anything already gone counts as deleted. Returns what failed.
    private func deleteICloudData() async -> [Error] {
        // If the app ends in here, the next launches skip it for a day instead of crashing again.
        CrashGuard.begin(.iCloudDeletion)
        defer { CrashGuard.end(.iCloudDeletion) }
        let persistence = PersistenceController.shared
        let container = persistence.cloudKitContainer
        var failures: [Error] = []
        // The log, and its share with the partner: Core Data's zones in the private database.
        do {
            try await persistence.deleteCloudKitZones()
        } catch {
            failures.append(error)
        }
        // This phone's nursery monitor inbox, with its share and its alerts.
        do {
            try await Self.deleteZones([AlertInboxes.ownZoneID], in: container.privateCloudDatabase)
        } catch {
            failures.append(error)
        }
        // Logs and inboxes other parents shared, if leaving them above didn't work.
        do {
            try await Self.leaveSharedZones(in: container)
        } catch {
            failures.append(error)
        }
        // Every subscription MyBaby saved: the inbox's alerts, and Core Data's own. Not once sync has
        // been turned on again meanwhile (`finishICloudIfPending` runs while the app is in use), since
        // Core Data has its own new ones by then.
        guard !PersistenceController.isSyncEnabled else {
            failures.append(CKError(.operationCancelled))
            return failures
        }
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            do {
                try await Self.deleteAllSubscriptions(in: database)
            } catch {
                failures.append(error)
            }
        }
        return failures
    }

    /// Before sync turns on while an iCloud deletion is pending (`setSyncEnabled`): leaves the logs and
    /// alert inboxes other parents shared that Delete all MyBaby data couldn't leave, so they don't
    /// download again. Says why in `lastError` and returns false if it couldn't. When nothing was joined,
    /// there's nothing to do.
    func leaveSharedLogs() async -> Bool {
        // Never at the same time as `finishICloudIfPending`: a zone it deletes late must not be the one
        // iCloud sync is about to set up again.
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while isFinishingICloud, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        // Paused after the app ended in here: skipped, so turning sync on can't crash again.
        guard !CrashGuard.isPaused(.iCloudDeletion) else { return true }
        CrashGuard.begin(.iCloudDeletion)
        defer { CrashGuard.end(.iCloudDeletion) }
        do {
            try await Self.leaveSharedZones(in: PersistenceController.shared.cloudKitContainer)
            return true
        } catch {
            CloudStatus.shared.lastError = String(localized: "Couldn't finish deleting your iCloud copy, so iCloud sync is off for now. Check that you're online and signed in to iCloud, then try again. (\(error.localizedDescription))", comment: "The parentheses hold the system's reason")
            return false
        }
    }

    /// Leaves every MyBaby zone in the shared database: logs (Core Data's zones) and nursery monitor
    /// inboxes other parents shared. Deleting a zone there removes this Apple ID from its share; the
    /// owner's data stays in their iCloud.
    private static func leaveSharedZones(in container: CKContainer) async throws {
        let database = container.sharedCloudDatabase
        let zoneIDs = try await database.allRecordZones()
            .map(\.zoneID)
            .filter { $0.zoneName == AlertInboxes.zoneName || $0.zoneName.hasPrefix("com.apple.coredata.cloudkit.") }
        try await deleteZones(zoneIDs, in: database)
    }

    private static func deleteZones(_ zoneIDs: [CKRecordZone.ID], in database: CKDatabase) async throws {
        guard !zoneIDs.isEmpty else { return }
        do {
            let (_, results) = try await database.modifyRecordZones(saving: [], deleting: zoneIDs)
            for result in results.values {
                do {
                    try result.get()
                } catch where isAlreadyGone(error) {
                    continue
                }
            }
        } catch where isAlreadyGone(error) {
            return
        }
    }

    private static func deleteAllSubscriptions(in database: CKDatabase) async throws {
        let ids = try await database.allSubscriptions().map(\.subscriptionID)
        guard !ids.isEmpty else { return }
        do {
            let (_, results) = try await database.modifySubscriptions(saving: [], deleting: ids)
            for result in results.values {
                do {
                    try result.get()
                } catch where isAlreadyGone(error) {
                    continue
                }
            }
        } catch where isAlreadyGone(error) {
            return
        }
    }

    /// A zone, record or subscription that isn't there any more, so there's nothing left to delete.
    private static func isAlreadyGone(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .zoneNotFound, .userDeletedZone, .unknownItem:
            return true
        case .partialFailure:
            let partial = error.partialErrorsByItemID?.values.map { $0 } ?? []
            return !partial.isEmpty && partial.allSatisfy(isAlreadyGone)
        default:
            return false
        }
    }

    /// Waits for `operation` to call back, or `timeout` seconds, whichever is first. Returns the
    /// error it called back with, or a timeout error.
    private static func waitForCallback(
        timeout: TimeInterval,
        _ operation: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async -> Error? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            let once = ResumeOnce(continuation)
            operation { error in once.resume(error) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.resume(CKError(.networkUnavailable))
            }
        }
    }

    // MARK: Trying the iCloud part again

    /// When Delete all MyBaby data couldn't reach iCloud, deletes what's left there: from the result
    /// screen's Finish button, and by itself when the app opens (see `RootView`). Only while sync is off
    /// and there's no log on this iPhone, as right after deleting; with a log, Settings › Finish deleting
    /// iCloud copy does it, and also starts the log's database over. Quiet when it can't finish yet,
    /// unless the parent tapped the button.
    func finishICloudIfPending(userInitiated: Bool = false) async {
        guard PersistenceController.isICloudDeletionPending, !PersistenceController.isSyncEnabled,
              !isRunning, !isFinishingICloud, CloudStatus.shared.reloadingMessage == nil,
              !Self.hasAnyData()
        else { return }
        guard userInitiated || !LastCrash.isSafeLaunch else { return }
        if userInitiated { CrashGuard.resume(.iCloudDeletion) }
        guard !CrashGuard.isPaused(.iCloudDeletion) else { return }
        isFinishingICloud = true
        defer { isFinishingICloud = false }

        let failures = await deleteICloudData()
        // Sync may have been turned on meanwhile, which finishes it in its own way.
        guard !PersistenceController.isSyncEnabled else { return }
        if failures.isEmpty {
            UserDefaults.shared.set(false, forKey: SettingsKey.iCloudDeletionPending)
            if var shown = outcome {
                shown.iCloudPending = false
                outcome = shown
            }
        } else if userInitiated {
            let message = String(localized: "iCloud still couldn't be reached. Check that you're online and signed in to iCloud, then try again.")
            if var shown = outcome {
                if !shown.problems.contains(message) { shown.problems.append(message) }
                outcome = shown
            } else {
                CloudStatus.shared.lastError = message
            }
        }
    }

    /// Whether either store holds anything of the app's own (a baby, Parent care entries…).
    private static func hasAnyData() -> Bool {
        let context = PersistenceController.shared.viewContext
        let entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
        for entity in entities where entity.superentity == nil {
            guard let name = entity.name, !name.hasPrefix("NSCK") else { continue }
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            request.fetchLimit = 1
            // Counted as data if it can't be read, so nothing is deleted from iCloud by mistake.
            if ((try? context.count(for: request)) ?? 1) > 0 { return true }
        }
        return false
    }

    // MARK: 3. The calendar

    /// Removing events needs full calendar access. Add to Calendar works without any, so this is often
    /// the first time MyBaby asks. If the parent says no (or said no before, when iOS doesn't ask
    /// again), the events stay and `clearCalendar` says which.
    private func requestCalendarAccessIfNeeded() async {
        let calendar = CalendarSync.shared
        calendar.refreshAccess()
        guard calendar.hasAddedEvents || calendar.hasEventsAddedOneAtATime, !calendar.hasFullAccess else { return }
        _ = await calendar.requestFullAccess()
    }

    private func clearCalendar(removingEvents: Bool, into result: inout Outcome) {
        let calendar = CalendarSync.shared
        calendar.refreshAccess()
        if removingEvents, calendar.hasAddedEvents, !calendar.hasFullAccess {
            result.problems.append(String(localized: "MyBaby wasn't allowed to open your calendar, so the appointments Keep appointments in my calendar added are still there. You can delete them in the Calendar app."))
        }
        if removingEvents {
            // Before sync is turned off below, which removes any of these it adopted.
            let removal = calendar.removeEventsAddedOneAtATime()
            let stayed = removal.stayed
            if !stayed.isEmpty {
                let events = Self.eventList(stayed)
                // One whole sentence for each case, so each language can word it its own way.
                switch (calendar.hasFullAccess, stayed.count == 1) {
                case (true, true):
                    result.problems.append(String(localized: "Your calendar didn't let MyBaby remove this event you added with Add to Calendar: \(events). You can delete it in the Calendar app."))
                case (true, false):
                    result.problems.append(String(localized: "Your calendar didn't let MyBaby remove these events you added with Add to Calendar: \(events). You can delete them in the Calendar app."))
                case (false, true):
                    result.problems.append(String(localized: "MyBaby wasn't allowed to open your calendar, so it couldn't remove this event you added with Add to Calendar: \(events). You can delete it in the Calendar app."))
                case (false, false):
                    result.problems.append(String(localized: "MyBaby wasn't allowed to open your calendar, so it couldn't remove these events you added with Add to Calendar: \(events). You can delete them in the Calendar app."))
                }
            }
            let missing = removal.notFound
            if !missing.isEmpty {
                let events = Self.eventList(missing)
                result.notes.append(missing.count == 1
                    ? String(localized: "An event you added with Add to Calendar wasn't in your calendar any more, so it was probably deleted or changed there already: \(events). If you still see it, you can delete it in the Calendar app.")
                    : String(localized: "Some events you added with Add to Calendar weren't in your calendar any more, so they were probably deleted or changed there already: \(events). If you still see them, you can delete them in the Calendar app."))
            }
        }
        // Stops keeping appointments in the calendar, removes the events if asked, and deletes
        // CalendarEvents.json, the list of which event is which appointment.
        calendar.disable(removingEvents: removingEvents)
        calendar.calendarID = nil
    }

    /// "Mavie: 2-month checkup, Oct 2, 2026 at 9:30 AM; Mavie: 4-month checkup, …", oldest first: the
    /// first few, then how many more.
    private static func eventList(_ events: [CalendarSync.AddedEvent]) -> String {
        let shown = 5
        var names = events.sorted { $0.start < $1.start }.prefix(shown).map(\.spokenName)
        if events.count > shown {
            names.append(String(localized: "and \(events.count - shown) more", comment: "The last item of a list of calendar events: how many more there are"))
        }
        return names.joined(separator: "; ")
    }

    // MARK: 4. Files

    /// The widgets' snapshot in the App Group, everything in Application Support (calendar links,
    /// crash reports, the database from builds before the App Group) and temporary exports.
    private func deleteFiles() -> [String] {
        let fileManager = FileManager.default
        var failed = false

        if let group = AppGroup.containerURL {
            for name in ["WidgetSnapshot.json", "WatchContext.json"] {
                let url = group.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) {
                    do { try fileManager.removeItem(at: url) } catch { failed = true }
                }
            }
        }

        // Without the App Group the new, empty database is in Application Support too, so it stays.
        let support = URL.applicationSupportDirectory
        let holdsStores = support.resolvingSymlinksInPath().standardizedFileURL.path
            == PersistenceController.storeFolder.resolvingSymlinksInPath().standardizedFileURL.path
        for name in (try? fileManager.contentsOfDirectory(atPath: support.path)) ?? [] {
            if holdsStores && PersistenceController.isStoreItem(name) { continue }
            do { try fileManager.removeItem(at: support.appendingPathComponent(name)) } catch { failed = true }
        }

        // CSV files and PDFs (reports, keepsakes, allergy cards) left from exports.
        let temporary = fileManager.temporaryDirectory
        for url in (try? fileManager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            let isExport = ["csv", "pdf"].contains(url.pathExtension.lowercased())
            guard isExport || url.lastPathComponent.hasPrefix("SchemaSetup-") else { continue }
            do { try fileManager.removeItem(at: url) } catch { failed = true }
        }

        return failed
            ? [String(localized: "A few small files couldn't be removed from this iPhone. They hold nothing MyBaby shows, and deleting the app from your iPhone removes them.")]
            : []
    }

    // MARK: 5. Settings

    /// Clears the app's settings and the ones shared with widgets and the watch. Each key is removed
    /// on its own first, so screens watching a setting see it change. The language picked for MyBaby
    /// in the iPhone's Settings app is kept: it's the iPhone's setting, not MyBaby's data.
    private func clearSettings() {
        let standard = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier {
            let saved = standard.persistentDomain(forName: domain) ?? [:]
            for key in saved.keys where key != "AppleLanguages" {
                standard.removeObject(forKey: key)
            }
            standard.removePersistentDomain(forName: domain)
            if let languages = saved["AppleLanguages"] {
                standard.set(languages, forKey: "AppleLanguages")
            }
        }
        let group = UserDefaults.shared
        if group !== standard {
            for key in (group.persistentDomain(forName: AppGroup.identifier) ?? [:]).keys {
                group.removeObject(forKey: key)
            }
            group.removePersistentDomain(forName: AppGroup.identifier)
        }
    }
}

/// Resumes a continuation once, from whichever of two callbacks comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Error?, Never>?

    init(_ continuation: CheckedContinuation<Error?, Never>) {
        self.continuation = continuation
    }

    func resume(_ error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: error)
    }
}
