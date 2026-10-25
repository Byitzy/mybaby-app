import CloudKit
import CoreData
import UIKit

/// Core Data stores that sync through iCloud, and sharing the baby's log with the other parent.
///
/// There are two stores, the way Apple's CloudKit sharing is designed:
/// - the **private** store holds what you created, in your own iCloud account;
/// - the **shared** store holds what someone else shared with you, in their account.
/// One parent creates the baby and invites the other; from then on both read and write the
/// same log, and changes appear on the other phone within seconds.
///
/// iCloud is opt-in. Until a parent turns on sync (or invites someone, which turns it on), both
/// stores are plain local databases and nothing leaves the phone. Switching only changes whether
/// the stores are mirrored to CloudKit, so no data is copied or converted.
final class PersistenceController {
    static let shared = PersistenceController()

    /// Replaced by a new one each time sync is switched on or off (see `reopenStores`), so don't
    /// keep it, or its `viewContext`, around: look it up through `PersistenceController.shared`.
    private(set) var container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// From Info.plist, which derives it from the bundle identifier: `iCloud.<bundle id>`.
    static let cloudKitContainerIdentifier: String =
        Bundle.main.object(forInfoDictionaryKey: "MyBabyCloudKitContainer") as? String ?? "iCloud.com.mybaby.ios"

    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerIdentifier) }

    /// Whether the log syncs through iCloud. Off until the parent turns it on or shares the log.
    static var isSyncEnabled: Bool {
        UserDefaults.shared.bool(forKey: SettingsKey.iCloudSync)
    }

    /// In the App Group's shared folder, so widgets and the Apple Watch app can open the log too.
    /// Without the App Group (e.g. it isn't set up in Signing & Capabilities), the app's own folder.
    private static let folder: URL = {
        guard let group = AppGroup.containerURL else { return NSPersistentContainer.defaultDirectoryURL() }
        let folder = group.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    private static let privateURL = folder.appendingPathComponent("MyBaby-private.sqlite")
    private static let sharedURL = folder.appendingPathComponent("MyBaby-shared.sqlite")

    private init() {
        container = Self.makeContainer()
        Self.moveStoresIntoAppGroup()
        loadStores(sync: Self.isSyncEnabled)
    }

    /// Loaded once and shared by every container, so each entity has a single description
    /// (two copies of the model make Core Data unsure which one `Baby` and the others belong to).
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "MyBaby", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else { fatalError("The MyBaby data model is missing from the app bundle.") }
        return model
    }()

    private static func makeContainer() -> NSPersistentCloudKitContainer {
        NSPersistentCloudKitContainer(name: "MyBaby", managedObjectModel: model)
    }

    /// Opens both database files, with or without iCloud. If iCloud sync can't start, turns it
    /// off and opens them without it, so the log is still there.
    private func loadStores(sync: Bool) {
        if let error = addStores(sync: sync) {
            guard sync else {
                // Even without iCloud the database files couldn't be opened, so they're damaged
                // (or the disk is full). Without its store the app can't work at all.
                fatalError("Couldn't open the MyBaby database; its files on this iPhone are damaged: \(error)")
            }
            // iCloud couldn't start (e.g. the stores don't match what iCloud expects). Open the same
            // files without it, in a new container, since a mirroring delegate that failed can't be reused.
            removeAllStores()
            UserDefaults.shared.set(false, forKey: SettingsKey.iCloudSync)
            container = Self.makeContainer()
            if let localError = addStores(sync: false) {
                // The files can't be opened even without iCloud, so they're damaged. Nothing else to try.
                fatalError("Couldn't open the MyBaby database, even without iCloud; its files on this iPhone are damaged: \(localError) (with iCloud: \(error))")
            }
            let message = "iCloud sync couldn't start, so MyBaby turned it off. Your log is safe on this iPhone. (\(error.localizedDescription))"
            Task { @MainActor in CloudStatus.shared.lastError = message }
        }
        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: Self.privateURL)
        sharedStore = coordinator.persistentStore(for: Self.sharedURL)
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Adds both stores to the container. Returns the first error, if either couldn't be opened.
    private func addStores(sync: Bool) -> Error? {
        container.persistentStoreDescriptions = [
            Self.description(url: Self.privateURL, scope: .private, sync: sync),
            Self.description(url: Self.sharedURL, scope: .shared, sync: sync),
        ]
        let failure = LoadFailure()
        // Stores are added one after the other before this returns (they aren't added asynchronously).
        container.loadPersistentStores { _, error in
            if let error, failure.error == nil {
                failure.error = error
            }
        }
        return failure.error
    }

    private final class LoadFailure {
        var error: Error?
    }

    private func removeAllStores() {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    /// Builds before the App Group kept the database in the app's own folder. Moves it over once,
    /// before it's opened, unless there's already a database in the App Group.
    private static func moveStoresIntoAppGroup() {
        let oldFolder = NSPersistentContainer.defaultDirectoryURL()
        guard oldFolder.standardizedFileURL != folder.standardizedFileURL else { return }
        let fileManager = FileManager.default
        for name in ["MyBaby-private", "MyBaby-shared"] {
            let oldStore = oldFolder.appendingPathComponent("\(name).sqlite")
            let newStore = folder.appendingPathComponent("\(name).sqlite")
            guard fileManager.fileExists(atPath: oldStore.path), !fileManager.fileExists(atPath: newStore.path) else { continue }
            // The database file goes last, so if a move fails the rest is tried again on the next launch.
            for file in [".\(name)_SUPPORT", "\(name).sqlite-shm", "\(name).sqlite-wal", "\(name).sqlite"] {
                let source = oldFolder.appendingPathComponent(file)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                do {
                    try fileManager.moveItem(at: source, to: folder.appendingPathComponent(file))
                } catch {
                    print("MyBaby: couldn't move \(file) into the App Group: \(error)")
                }
            }
        }
    }

    /// Turns iCloud sync on or off by reopening the same database files with or without CloudKit.
    ///
    /// The app shows a progress screen meanwhile (see `takeDownContent`), so no view is holding
    /// objects from the stores while they're swapped. Turning sync on uploads the existing log.
    ///
    /// Every way of turning sync on (the Settings switch, Invite partner, onboarding, Restore from
    /// iCloud, joining a partner's log) comes through here, so the iCloud account is checked here
    /// first. Returns whether sync ended up as asked; when it didn't, the reason is in `lastError`.
    @MainActor
    @discardableResult
    func setSyncEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != Self.isSyncEnabled else { return true }
        if enabled {
            // Signed out, restricted or unreachable: say so and leave sync off.
            guard await confirmICloudAvailable() else { return false }
        }
        await takeDownContent(showing: enabled ? "Turning on iCloud…" : "Turning off iCloud…")
        if enabled && Self.isICloudDeletionPending {
            // Deleting the iCloud copy didn't finish. Syncing now could bring the old copy back,
            // or make iCloud clear this iPhone, so finish deleting first.
            guard await finishICloudDeletion() else {
                CloudStatus.shared.reloadingMessage = nil
                return false
            }
        }
        reopenStores(sync: enabled)
        SyncStatus.shared.restart()
        CloudStatus.shared.reloadingMessage = nil
        // If iCloud couldn't start, `loadStores` opened the stores without it and said why.
        return Self.isSyncEnabled == enabled
    }

    /// Closes the stores and opens the same files again with or without CloudKit, in a new
    /// container. Only while nothing is on screen (see `takeDownContent`).
    ///
    /// A new container each time, because NSPersistentCloudKitContainer's mirroring delegate is
    /// tied to the store it was set up with and can't be reused. Reloading stores into the same
    /// container is a likely cause of sharing failing with Cocoa error 134410 right after sync was
    /// turned on. `storeGeneration` then rebuilds the screens with the new `viewContext`.
    @MainActor
    private func reopenStores(sync: Bool) {
        viewContext.saveIfChanged()
        viewContext.reset()
        removeAllStores()
        UserDefaults.shared.set(sync, forKey: SettingsKey.iCloudSync)
        privateStore = nil
        sharedStore = nil
        // The old container goes once the screens holding its context are rebuilt.
        container = Self.makeContainer()
        loadStores(sync: sync)
        CloudStatus.shared.storeGeneration += 1
        // Another device's copy of the same baby may be here already (see `DuplicateBabies`).
        if sync { DuplicateBabies.shared.check() }
    }

    /// Replaces the app's screens with a progress screen showing `message`, and waits until they're
    /// gone so nothing on screen still uses objects from the stores. Sheets presented from UIKit
    /// (like the sharing sheet) are closed too. Checks every 50 ms, and gives up after 2 seconds.
    @MainActor
    private func takeDownContent(showing message: String) async {
        let status = CloudStatus.shared
        status.reloadingMessage = message
        let roots = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
        for root in roots where root.presentedViewController != nil {
            root.dismiss(animated: false)
        }
        for _ in 0..<40 {
            guard status.contentOnScreen > 0 else { break }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                break
            }
        }
    }

    /// The options a store opened without iCloud has (see `description`).
    private static let localStoreOptions: [AnyHashable: Any] = [
        NSPersistentHistoryTrackingKey: true as NSNumber,
        NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber,
    ]

    private static func description(url: URL, scope: CKDatabase.Scope, sync: Bool) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        if sync {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
        } else {
            // A plain local store. History tracking stays on so sync can be turned on later.
            description.cloudKitContainerOptions = nil
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    // MARK: Babies

    @discardableResult
    func createBaby(name: String, birthDate: Date?) -> Baby {
        let baby = Baby(context: viewContext)
        baby.uuid = UUID()
        baby.name = name
        baby.birthDate = birthDate
        baby.createdAt = .now
        if let privateStore {
            viewContext.assign(baby, to: privateStore)
        }
        viewContext.saveIfChanged()
        return baby
    }

    /// Whether another baby can be added on this iPhone. A parent who joined their partner's log
    /// can't: a new baby there would have to go into the partner's iCloud, in the same share,
    /// which Core Data only does for entries linked to a baby that's already shared. So new
    /// babies are added on the phone of the parent who created the log.
    var canAddBabies: Bool { !hasJoinedLog }

    /// Adds another baby (twins, a sibling) in this iPhone's own store, and shows it. When the
    /// log is shared, the new baby goes into the same share so the partner gets it too.
    @MainActor
    @discardableResult
    func addBaby(name: String, birthDate: Date?) async -> Baby {
        let baby = createBaby(name: name, birthDate: birthDate)
        Baby.select(baby)
        if Self.isSyncEnabled, let share = ownShare {
            do {
                _ = try await container.share([baby], to: share)
            } catch {
                CloudStatus.shared.lastError = "\(baby.displayName) was added on this iPhone, but couldn't be shared with your partner. Open Manage sharing to try again. (\(error.localizedDescription))"
            }
        }
        return baby
    }

    /// Deletes a baby and everything logged for them. The screens are taken down first, so none
    /// of them shows the baby while it's being deleted.
    @MainActor
    func deleteBaby(_ baby: Baby) async {
        let objectID = baby.objectID
        await takeDownContent(showing: "Removing \(baby.displayName)…")
        viewContext.delete(viewContext.object(with: objectID))
        viewContext.saveIfChanged()
        // Show whichever baby is left.
        UserDefaults.shared.removeObject(forKey: SettingsKey.selectedBaby)
        NotificationManager.refreshFeedingReminder(context: viewContext)
        NotificationManager.refreshAppointmentReminders(context: viewContext)
        CareReminders.refresh(context: viewContext)
        CloudStatus.shared.reloadingMessage = nil
    }

    /// Merges two copies of the same baby, from two devices on the same Apple ID (see `BabyMerge`).
    /// The oldest is kept and gets everything logged for the other, which is then deleted. Both
    /// must be in this iPhone's own store. The screens are taken down first, like `deleteBaby`.
    @MainActor
    func mergeBabies(keep first: Baby, merge second: Baby) async {
        let ids = first.createdAt <= second.createdAt
            ? (keep: first.objectID, merge: second.objectID)
            : (keep: second.objectID, merge: first.objectID)
        await takeDownContent(showing: "Merging \(first.displayName)…")
        guard ids.keep != ids.merge,
              let keeper = try? viewContext.existingObject(with: ids.keep) as? Baby,
              let duplicate = try? viewContext.existingObject(with: ids.merge) as? Baby,
              let store = keeper.objectID.persistentStore,
              duplicate.objectID.persistentStore == store, store != sharedStore
        else {
            CloudStatus.shared.reloadingMessage = nil
            return
        }
        // If only the copy being merged was shared with the partner, the kept one joins that share,
        // so the partner keeps seeing everything.
        let duplicateShare = existingShare(for: duplicate)
        let keeperIsShared = existingShare(for: keeper) != nil
        if UserDefaults.shared.string(forKey: SettingsKey.selectedBaby) == duplicate.uuid?.uuidString {
            Baby.select(keeper)
        }
        BabyMerge.move(duplicate, into: keeper)
        viewContext.delete(duplicate)
        viewContext.saveIfChanged()
        NotificationManager.refreshFeedingReminder(context: viewContext)
        NotificationManager.refreshAppointmentReminders(context: viewContext)
        CareReminders.refresh(context: viewContext)
        CloudStatus.shared.reloadingMessage = nil
        DuplicateBabies.shared.check()

        if Self.isSyncEnabled, let duplicateShare, !keeperIsShared {
            do {
                _ = try await container.share([keeper], to: duplicateShare)
            } catch {
                CloudStatus.shared.lastError = "\(keeper.displayName)'s log was merged on this iPhone, but couldn't be shared with your partner. Open Manage sharing to try again. (\(error.localizedDescription))"
            }
        }
    }

    /// The babies this iPhone created, in its own store.
    @MainActor
    private func ownBabies() -> [Baby] {
        guard let privateStore else { return [] }
        let request = Baby.fetchAll()
        request.affectedStores = [privateStore]
        return (try? viewContext.fetch(request)) ?? []
    }

    // MARK: Sharing

    /// True when this phone sees the baby because the other parent shared it.
    func isJoined(_ baby: Baby) -> Bool {
        guard let sharedStore else { return false }
        return baby.objectID.persistentStore == sharedStore
    }

    /// True when this phone has a log the other parent shared.
    var hasJoinedLog: Bool {
        guard let sharedStore else { return false }
        let request = Baby.fetchAll()
        request.affectedStores = [sharedStore]
        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }

    /// Whether this iPhone can change `baby`'s log. False for someone the owner invited as view
    /// only, like a grandparent or a nanny. Entries live with their baby, so this covers them all.
    func canEdit(_ baby: Baby) -> Bool {
        // Only a log someone else shared can be view only; your own is always yours to change.
        guard isJoined(baby) else { return true }
        return container.canUpdateRecord(forManagedObjectWith: baby.objectID)
    }

    func existingShare(for baby: Baby) -> CKShare? {
        (try? container.fetchShares(matching: [baby.objectID]))?[baby.objectID]
    }

    /// The share this parent created to invite their partner, if they have.
    var ownShare: CKShare? {
        guard let privateStore else { return nil }
        return (try? container.fetchShares(in: privateStore))?.first
    }

    /// The share for the baby's log, creating it the first time someone invites a partner.
    /// Twins and siblings are one log, so every baby this iPhone created goes in the same share.
    @MainActor
    func share(_ baby: Baby) async throws -> CKShare {
        guard Self.isSyncEnabled else { throw SharingError.syncOff }
        if isJoined(baby), let existing = existingShare(for: baby) { return existing }
        // Right after sync is turned on, iCloud may still be setting up the store.
        await waitForCloudKitSetup(of: privateStore)

        let babies = ownBabies()
        if let existing = ownShare {
            // A baby added while sharing failed isn't in the share yet.
            let shares = (try? container.fetchShares(matching: babies.map(\.objectID))) ?? [:]
            let unshared = babies.filter { shares[$0.objectID] == nil }
            guard !unshared.isEmpty else { return await labeled(existing, babies: babies) }
            let updated = try await shareRetrying(unshared, to: existing)
            return await labeled(updated, babies: babies)
        }

        let toShare = babies.isEmpty ? [baby] : babies
        let share = try await shareRetrying(toShare, to: nil)
        return await labeled(share, babies: toShare)
    }

    /// `container.share`, tried a second time 2 seconds later if Core Data's CloudKit side wasn't
    /// ready (Cocoa errors 134400–134499).
    @MainActor
    private func shareRetrying(_ babies: [Baby], to share: CKShare?) async throws -> CKShare {
        do {
            return try await container.share(babies, to: share).1
        } catch let error where CloudErrors.isCoreDataCloudKitError(error) {
            try? await Task.sleep(for: .seconds(2))
            return try await container.share(babies, to: share).1
        }
    }

    /// Gives the share the title and picture Apple's sharing sheet and the invitation show, and
    /// saves them. Shares made by earlier builds have neither, and the title follows the babies'
    /// names. The title is visible to Apple, like any share's (the privacy page says so).
    @MainActor
    private func labeled(_ share: CKShare, babies: [Baby]) async -> CKShare {
        let title = Self.shareTitle(for: babies)
        let thumbnail = ShareThumbnail.pngData
        let needsTitle = share[CKShare.SystemFieldKey.title] as? String != title
        let needsThumbnail = thumbnail != nil && share[CKShare.SystemFieldKey.thumbnailImageData] == nil
        guard needsTitle || needsThumbnail, let privateStore else { return share }
        share[CKShare.SystemFieldKey.title] = title
        if let thumbnail {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnail
        }
        do {
            return try await container.persistUpdatedShare(share, in: privateStore)
        } catch {
            // The invitation still works without them; they're added again next time.
            print("MyBaby: couldn't save the share's title and picture: \(error)")
            return share
        }
    }

    /// "Ava's care log", or "Our babies' care log" for twins and siblings.
    private static func shareTitle(for babies: [Baby]) -> String {
        guard babies.count < 2 else { return "Our babies' care log" }
        guard let name = babies.first?.name, !name.isEmpty else { return "Baby's care log" }
        return "\(name)'s care log"
    }

    /// Joins a log the other parent shared, after they tap the invitation link.
    @MainActor
    func acceptShare(_ metadata: CKShare.Metadata) async {
        // Opening a partner's invitation is a clear request to share, so turn on iCloud for it.
        // Sync stays off without a usable iCloud account, or if deleting the iCloud copy couldn't
        // finish; that error is already showing.
        guard await setSyncEnabled(true), let sharedStore else { return }
        // Joining before iCloud has set up the shared store fails, like sharing does.
        await waitForCloudKitSetup(of: sharedStore)
        do {
            _ = try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
            // Show the partner's baby once it's here, rather than one picked on this iPhone before.
            UserDefaults.shared.removeObject(forKey: SettingsKey.selectedBaby)
            // The partner's baby takes a moment to download. Until it's here, show that instead of
            // onboarding, and keep this parent's own empty baby (if any) until it can be replaced.
            awaitImport(.sharedBaby, message: "Joining your partner's log…")
        } catch {
            CloudStatus.shared.lastError = CloudErrors.sharingMessage(
                for: error, otherwise: "Couldn't join the shared log. Please try again in a minute."
            )
        }
    }

    /// A parent who set up their own empty baby before joining shouldn't end up with two babies.
    @MainActor
    private func removeEmptyOwnBabies() {
        guard let privateStore, let babies = try? viewContext.fetch(Baby.fetchAll()) else { return }
        for baby in babies where baby.objectID.persistentStore == privateStore && !baby.hasEntries {
            viewContext.delete(baby)
        }
        viewContext.saveIfChanged()
    }

    /// Records changes made in the share sheet, e.g. people added or removed, in the store that
    /// holds the baby: the private store for the owner, the shared store for the invited parent.
    func persistUpdatedShare(_ share: CKShare, in store: NSPersistentStore) {
        container.persistUpdatedShare(share, in: store) { _, error in
            guard let error else { return }
            Task { @MainActor in
                CloudStatus.shared.lastError = "Couldn't save the sharing changes: \(error.localizedDescription)"
            }
        }
    }

    /// Called when sharing stops in the share sheet. The owner keeps their log. A parent who left
    /// their partner's log removes it from this iPhone, since it lives in the partner's iCloud.
    @MainActor
    func sharingStopped(_ share: CKShare, in store: NSPersistentStore) async {
        let status = CloudStatus.shared
        status.shareChanged = UUID()
        guard let sharedStore, store == sharedStore else { return }

        await takeDownContent(showing: "Leaving the shared log…")
        let purgeError: Error? = await withCheckedContinuation { continuation in
            container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore) { _, error in
                continuation.resume(returning: error)
            }
        }
        if let purgeError {
            status.lastError = "Couldn't remove the shared log from this iPhone: \(purgeError.localizedDescription)"
        }
        // The purge doesn't reach objects already loaded, so start the screens over from the store.
        viewContext.reset()
        status.shareChanged = UUID()
        status.reloadingMessage = nil
    }

    // MARK: Deleting the iCloud copy

    /// True while deleting the iCloud copy hasn't finished, e.g. because the iPhone was offline.
    static var isICloudDeletionPending: Bool {
        UserDefaults.shared.bool(forKey: SettingsKey.iCloudDeletionPending)
    }

    /// Deletes the log from this Apple ID's iCloud and keeps the copy on this iPhone.
    ///
    /// NSPersistentCloudKitContainer must never see its zone disappear while it's syncing: it
    /// treats that like the parent deleting their data in iPhone Settings, and can clear this
    /// iPhone too. So:
    /// 1. sync is turned off first, so the stores aren't connected to CloudKit;
    /// 2. the zones are deleted straight from the private iCloud database;
    /// 3. the private store is copied into a new file, leaving behind what the container
    ///    remembers about the deleted zone. Turning sync on later then sets up iCloud from scratch
    ///    and uploads the log again, the same way it does for a log that was never synced.
    /// If it's interrupted, `isICloudDeletionPending` stays set, and turning sync on finishes it first.
    /// Only for a log that isn't shared: a shared log lives in a zone the partner uses too.
    @MainActor
    func deleteICloudCopy() async {
        if Self.isSyncEnabled {
            guard ownShare == nil, !hasJoinedLog else { return }
        }
        await takeDownContent(showing: "Deleting your iCloud copy…")
        UserDefaults.shared.set(true, forKey: SettingsKey.iCloudDeletionPending)
        if Self.isSyncEnabled {
            reopenStores(sync: false)
        }
        await finishICloudDeletion()
        CloudStatus.shared.reloadingMessage = nil
    }

    /// Steps 2 and 3 of `deleteICloudCopy`, while sync is off and nothing is on screen. Returns
    /// false, with the reason in `lastError`, if it couldn't finish.
    @MainActor
    @discardableResult
    private func finishICloudDeletion() async -> Bool {
        do {
            try await deleteCloudKitZones()
        } catch {
            CloudStatus.shared.lastError = "Couldn't delete your iCloud copy, so iCloud sync is off for now. Your log is still on this iPhone. Check that you're online and signed in to iCloud, then tap Finish deleting iCloud copy in Settings. (\(error.localizedDescription))"
            return false
        }
        do {
            try startPrivateStoreOver()
        } catch {
            CloudStatus.shared.lastError = "Your iCloud copy was deleted, but this iPhone couldn't finish tidying up, so iCloud sync stays off for now. Your log is still here. Tap Finish deleting iCloud copy in Settings to try again. (\(error.localizedDescription))"
            return false
        }
        UserDefaults.shared.set(false, forKey: SettingsKey.iCloudDeletionPending)
        return true
    }

    /// Deletes the zones Core Data keeps the log in from this Apple ID's private database: the
    /// main zone, and any left over from sharing that was stopped. A zone that's already gone
    /// (from an earlier try, or deleted in iPhone Settings) counts as deleted.
    @MainActor
    private func deleteCloudKitZones() async throws {
        let database = cloudKitContainer.privateCloudDatabase
        let mainZone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        var zoneIDs = try await database.allRecordZones()
            .map(\.zoneID)
            .filter { $0.zoneName.hasPrefix("com.apple.coredata.cloudkit.") }
        if !zoneIDs.contains(where: { $0.zoneName == mainZone.zoneName }) {
            zoneIDs.append(mainZone)
        }
        let (_, deleteResults) = try await database.modifyRecordZones(saving: [], deleting: zoneIDs)
        for result in deleteResults.values {
            do {
                try result.get()
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                continue
            }
        }
    }

    /// Copies everything in the private store into a new database file and puts it in place of
    /// the old one. The copy has none of the records NSPersistentCloudKitContainer keeps about
    /// what it synced, only the log and its history, like a log that was never synced.
    /// Only while sync is off and nothing is on screen. The old file stays until the copy is saved.
    @MainActor
    private func startPrivateStoreOver() throws {
        guard !Self.isSyncEnabled, let oldStore = privateStore else { return }
        viewContext.saveIfChanged()
        viewContext.reset()

        let coordinator = container.persistentStoreCoordinator
        let options = Self.localStoreOptions
        let freshURL = Self.folder.appendingPathComponent("MyBaby-private-fresh.sqlite")
        // Left over from an attempt that was interrupted.
        try? coordinator.destroyPersistentStore(at: freshURL, type: .sqlite, options: options)

        let freshStore = try coordinator.addPersistentStore(type: .sqlite, configuration: nil, at: freshURL, options: options)
        do {
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            try copyObjects(from: oldStore, to: freshStore, in: context)
            try context.save()
            try coordinator.remove(freshStore)
        } catch {
            try? coordinator.remove(freshStore)
            try? coordinator.destroyPersistentStore(at: freshURL, type: .sqlite, options: options)
            throw error
        }

        // Swap the new file in, then open the stores again.
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        defer { loadStores(sync: false) }
        try coordinator.replacePersistentStore(
            at: Self.privateURL, destinationOptions: options,
            withPersistentStoreFrom: freshURL, sourceOptions: options,
            type: .sqlite
        )
        try? coordinator.destroyPersistentStore(at: freshURL, type: .sqlite, options: options)
    }

    /// Copies every object in `source` into `destination`, keeping the links between them.
    private func copyObjects(
        from source: NSPersistentStore, to destination: NSPersistentStore, in context: NSManagedObjectContext
    ) throws {
        var copies: [NSManagedObjectID: NSManagedObject] = [:]
        var originals: [NSManagedObject] = []
        for entity in container.managedObjectModel.entities {
            // Only the app's own entities; never anything CloudKit keeps about what it synced.
            guard let name = entity.name, !name.hasPrefix("NSCK") else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.affectedStores = [source]
            request.includesSubentities = false
            for original in try context.fetch(request) {
                let copy = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
                context.assign(copy, to: destination)
                for attribute in entity.attributesByName.keys {
                    copy.setValue(original.value(forKey: attribute), forKey: attribute)
                }
                copies[original.objectID] = copy
                originals.append(original)
            }
        }
        // Every entry points to its baby; Core Data fills in the baby's side.
        for original in originals {
            for (name, relationship) in original.entity.relationshipsByName where !relationship.isToMany {
                guard let target = original.value(forKey: name) as? NSManagedObject else { continue }
                copies[original.objectID]?.setValue(copies[target.objectID], forKey: name)
            }
        }
    }

    // MARK: Waiting for iCloud

    /// What the app is waiting for iCloud to download.
    private enum ImportGoal {
        /// The partner's baby, after accepting their invitation.
        case sharedBaby
        /// Any baby, when restoring this Apple ID's log. Sync is turned off again if nothing comes
        /// and it was off before.
        case restore(turnedOnSync: Bool)
    }

    private var importGoal: ImportGoal?
    private var importTimeout: Task<Void, Never>?

    /// Brings back a log kept in this Apple ID's iCloud, on a new iPhone or after reinstalling.
    /// Sync starts off on a fresh install, so otherwise nothing would download.
    @MainActor
    func restoreFromICloud() async {
        let turnedOnSync = !Self.isSyncEnabled
        guard await setSyncEnabled(true) else { return }
        awaitImport(.restore(turnedOnSync: turnedOnSync), message: "Looking for your log in iCloud…")
        DuplicateBabies.shared.check()
    }

    /// Shows `message` in place of onboarding until the baby arrives (see `checkForImportedBaby`),
    /// the parent cancels, or a minute passes.
    @MainActor
    private func awaitImport(_ goal: ImportGoal, message: String) {
        importTimeout?.cancel()
        importGoal = goal
        CloudStatus.shared.awaitingImport = message
        importTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self.importTimeout = nil
            await self.stopAwaitingImport(timedOut: true)
        }
        // It may already be here, e.g. when opening an invitation that was accepted before.
        checkForImportedBaby()
    }

    /// Called when iCloud brings in changes: stops waiting once the baby being waited for is here.
    @MainActor
    func checkForImportedBaby() {
        guard let goal = importGoal else { return }
        let request = Baby.fetchAll()
        if case .sharedBaby = goal {
            guard let sharedStore else { return }
            request.affectedStores = [sharedStore]
        }
        guard let count = try? viewContext.count(for: request), count > 0 else { return }
        endAwaitingImport()
        if case .sharedBaby = goal {
            removeEmptyOwnBabies()
        }
    }

    /// Stops waiting, from the Cancel button or when it takes too long. A restore that found
    /// nothing turns sync back off if it was off before, so onboarding starts a log on this iPhone.
    @MainActor
    func stopAwaitingImport(timedOut: Bool) async {
        // It may have arrived just now.
        checkForImportedBaby()
        guard let goal = importGoal else { return }
        endAwaitingImport()
        switch goal {
        case .sharedBaby:
            if timedOut {
                CloudStatus.shared.lastError = "Your partner's log hasn't downloaded yet. Check that both iPhones are online and signed in to iCloud, then open the invitation link again."
            }
        case .restore(let turnedOnSync):
            if timedOut {
                CloudStatus.shared.lastError = "No MyBaby log was found in your iCloud. Check that this iPhone is online and signed in with the Apple ID you used before, then try again."
            }
            if turnedOnSync {
                await setSyncEnabled(false)
            }
        }
    }

    @MainActor
    private func endAwaitingImport() {
        importGoal = nil
        importTimeout?.cancel()
        importTimeout = nil
        CloudStatus.shared.awaitingImport = nil
    }
}

enum SharingError: LocalizedError {
    case syncOff

    var errorDescription: String? { "Turn on iCloud sync to share the log." }
}

/// Sharing problems and store switches, for the UI.
@MainActor
final class CloudStatus: ObservableObject {
    static let shared = CloudStatus()
    @Published var lastError: String?
    /// Set while the stores are being reopened to turn iCloud on or off.
    @Published var reloadingMessage: String?
    /// Set while waiting for iCloud to download a log: the partner's after joining, or your own when restoring.
    @Published var awaitingImport: String?
    /// Changes when sharing stops, so Settings checks again whether the log is shared.
    @Published var shareChanged = UUID()
    /// Goes up each time the stores are reopened in a new container, so the screens are rebuilt
    /// with its `viewContext` (see `RootView`).
    @Published var storeGeneration = 0
    /// How many copies of the app's main screens are on screen, so stores aren't swapped under them.
    var contentOnScreen = 0
}

extension NSManagedObjectContext {
    /// Saves pending changes. Failures are rare (e.g. a full disk) and are left for the next save to retry.
    func saveIfChanged() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            print("MyBaby: couldn't save changes: \(error)")
        }
    }
}
