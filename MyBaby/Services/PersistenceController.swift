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
    private static let privateURL = folder.appendingPathComponent("MyBaby-private\(storeSuffix).sqlite")
    private static let sharedURL = folder.appendingPathComponent("MyBaby-shared\(storeSuffix).sqlite")

    /// Builds run from Xcode sync with CloudKit's Development environment, TestFlight and App Store
    /// builds with Production. NSPersistentCloudKitContainer records in the database file what it
    /// synced and where, so each keeps its own files: a TestFlight build opening a file a debug build
    /// had synced stopped with "Cannot replace assigned container ID" (see `repairAfterEnvironmentMixUp`).
    #if DEBUG
    private static let storeSuffix = "-development"
    #else
    private static let storeSuffix = ""
    #endif

    private init() {
        container = Self.makeContainer()
        Self.moveStoresIntoAppGroup()
        // A safe launch after a crash opens the same stores without iCloud, just this once.
        loadStores(sync: Self.isSyncEnabled && !LastCrash.isSafeLaunch)
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
            let reason = error.localizedDescription
            let message = String(
                localized: "iCloud sync couldn't start, so MyBaby turned it off. Your log is safe on this iPhone. (\(reason))",
                comment: "The system's description of the error is in brackets"
            )
            Task { @MainActor in CloudStatus.shared.lastError = message }
        }
        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: Self.privateURL)
        sharedStore = coordinator.persistentStore(for: Self.sharedURL)
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // What the screens show about sharing, looked up once the stores are open (see `CloudStatus`).
        // `self` is passed in because this also runs while `shared` is being made.
        let persistence = self
        if Thread.isMainThread {
            MainActor.assumeIsolated { CloudStatus.shared.refreshSharing(persistence) }
        } else {
            Task { @MainActor in CloudStatus.shared.refreshSharing(persistence) }
        }
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
        await takeDownContent(showing: enabled ? String(localized: "Turning on iCloud…") : String(localized: "Turning off iCloud…"))
        if enabled && Self.isICloudDeletionPending {
            // Deleting the iCloud copy didn't finish. Syncing now could bring the old copy back,
            // or make iCloud clear this iPhone, so finish deleting first. After Delete all MyBaby data
            // that includes leaving the logs and alert inboxes other parents shared, so they don't come back.
            guard await DataWipe.shared.leaveSharedLogs(), await finishICloudDeletion() else {
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
    /// Also used by `DataWipe`, to open new, empty stores after Delete all MyBaby data.
    @MainActor
    func reopenStores(sync: Bool) {
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
    /// Also used by `DataWipe` while it deletes everything.
    @MainActor
    func takeDownContent(showing message: String) async {
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

    // MARK: Persistent history

    /// How much persistent history is kept. With history tracking on, every save adds rows to the
    /// store's history tables, and they stay until they're deleted, so without purging the database
    /// files would only ever grow.
    ///
    /// The app itself never reads the history; only NSPersistentCloudKitContainer does, to find what
    /// to upload. It keeps its own place in the history for each store and only needs what it hasn't
    /// uploaded yet, which is seconds or minutes old when the iPhone is online. A week leaves a wide
    /// margin for a phone that was offline for days, and recent history is never touched. If the
    /// container ever finds its place older than what's left, it sets sync up again from the store
    /// itself, which costs time but loses nothing.
    static let historyKeptFor: TimeInterval = 7 * 86_400
    /// Purging runs at most this often.
    private static let historyPurgeInterval: TimeInterval = 86_400
    /// When history was last purged, in `UserDefaults.standard` (this iPhone only).
    private static let historyPurgedAtKey = "historyPurgedAt"

    /// Deletes history older than `historyKeptFor` from both stores, at most once a day, on a
    /// background context so it never holds up the screens. Called a little after launch
    /// (`AppDelegate`). The space it frees inside the database files is reused by later saves.
    @MainActor
    func purgeOldHistoryIfDue(now: Date = .now) {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.historyPurgedAtKey) as? Date,
           last <= now, now.timeIntervalSince(last) < Self.historyPurgeInterval {
            return
        }
        // While the stores are being reopened or erased, try again another time.
        guard CloudStatus.shared.reloadingMessage == nil, privateStore != nil || sharedStore != nil else { return }
        defaults.set(now, forKey: Self.historyPurgedAtKey)

        let cutoff = now.addingTimeInterval(-Self.historyKeptFor)
        let context = container.newBackgroundContext()
        context.perform {
            // Without `affectedStores`, the request covers every store the container has open: the
            // private and the shared one.
            guard !(context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true) else { return }
            do {
                try context.execute(NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff))
            } catch {
                print("MyBaby: couldn't purge old persistent history: \(error)")
            }
        }
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
                let babyName = baby.displayName
                let reason = error.localizedDescription
                CloudStatus.shared.lastError = String(
                    localized: "\(babyName) was added on this iPhone, but couldn't be shared with your partner. Open Manage sharing to try again. (\(reason))",
                    comment: "The baby's name; the system's description of the error is in brackets"
                )
            }
        }
        return baby
    }

    /// Deletes a baby and everything logged for them. The screens are taken down first, so none
    /// of them shows the baby while it's being deleted.
    @MainActor
    func deleteBaby(_ baby: Baby) async {
        let objectID = baby.objectID
        let name = baby.displayName
        await takeDownContent(showing: String(localized: "Removing \(name)…", comment: "While a baby is being deleted; the baby's name"))
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
        let name = first.displayName
        await takeDownContent(showing: String(localized: "Merging \(name)…", comment: "While two copies of a baby are merged; the baby's name"))
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
                let babyName = keeper.displayName
                let reason = error.localizedDescription
                CloudStatus.shared.lastError = String(
                    localized: "\(babyName)'s log was merged on this iPhone, but couldn't be shared with your partner. Open Manage sharing to try again. (\(reason))",
                    comment: "The baby's name; the system's description of the error is in brackets"
                )
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
    /// Asks the store each time; screens read `CloudStatus.canEdit` instead, which is kept up to date.
    func canEdit(_ baby: Baby) -> Bool {
        // Only a log someone else shared can be view only; your own is always yours to change.
        guard isJoined(baby) else { return true }
        return container.canUpdateRecord(forManagedObjectWith: baby.objectID)
    }

    /// The babies this iPhone can't change (`canEdit` is false), for `CloudStatus`. Only babies in the
    /// shared store can be view only, so only they are looked up, by object ID without loading them.
    func viewOnlyBabyIDs() -> Set<NSManagedObjectID> {
        guard let sharedStore else { return [] }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "Baby")
        request.resultType = .managedObjectIDResultType
        request.affectedStores = [sharedStore]
        let ids = (try? viewContext.fetch(request)) ?? []
        return Set(ids.filter { !container.canUpdateRecord(forManagedObjectWith: $0) })
    }

    func existingShare(for baby: Baby) -> CKShare? {
        (try? container.fetchShares(matching: [baby.objectID]))?[baby.objectID]
    }

    /// The share this parent created to invite their partner, if they have.
    var ownShare: CKShare? {
        guard let privateStore else { return nil }
        return Self.logShare(in: privateStore, container: container)
    }

    /// The log's share among the shares in this Apple ID's private database. Only one of Core Data's
    /// own zones counts: the nursery monitor's alert inbox has a share of its own there too
    /// (`AlertInboxes`), and offering that one as the invitation gave the partner alerts, not the log.
    private static func logShare(in store: NSPersistentStore, container: NSPersistentCloudKitContainer) -> CKShare? {
        (try? container.fetchShares(in: store))?.first(where: isLogShare)
    }

    /// Whether `share` is in one of Core Data's zones, so it shares a baby's log.
    static func isLogShare(_ share: CKShare) -> Bool {
        share.recordID.zoneID.zoneName.hasPrefix("com.apple.coredata.cloudkit.")
    }

    /// Which way the last `share(_:)` found its share, for the message when it isn't the log's.
    private(set) var lastShareSource = ""

    /// The share for the baby's log, creating it the first time someone invites a partner.
    /// Twins and siblings are one log, so every baby this iPhone created goes in the same share.
    @MainActor
    func share(_ baby: Baby) async throws -> CKShare {
        guard Self.isSyncEnabled else { throw SharingError.syncOff }
        if isJoined(baby), let existing = existingShare(for: baby) {
            lastShareSource = "joined"
            return existing
        }
        // Right after sync is turned on, iCloud may still be setting up the store.
        await waitForCloudKitSetup(of: privateStore)

        let babies = ownBabies()
        // Off the main thread: looking up shares can wait on iCloud, which froze the sheet for seconds.
        let container = self.container
        let store = privateStore
        let currentShare = await Task.detached {
            store.flatMap { Self.logShare(in: $0, container: container) }
        }.value
        if let existing = currentShare {
            // A baby added while sharing failed isn't in the share yet.
            let shares = (try? container.fetchShares(matching: babies.map(\.objectID))) ?? [:]
            let unshared = babies.filter { shares[$0.objectID] == nil }
            guard !unshared.isEmpty else {
                lastShareSource = "existing"
                return existing
            }
            lastShareSource = "added \(unshared.count)"
            return try await shareRetrying(unshared, to: existing)
        }

        let toShare = babies.isEmpty ? [baby] : babies
        lastShareSource = "new for \(toShare.count)"
        return try await shareRetrying(toShare, to: nil)
    }

    /// `container.share`, tried a second time 2 seconds later if Core Data's CloudKit side wasn't
    /// ready (Cocoa errors 134400–134499).
    @MainActor
    private func shareRetrying(_ babies: [Baby], to share: CKShare?) async throws -> CKShare {
        // A new share would come back as the nursery monitor's own: see `clearAlertInboxShare`.
        if share == nil {
            await clearAlertInboxShare()
        }
        let result: CKShare
        let ids = babies.map(\.objectID)
        do {
            result = try await Self.shareInBackground(ids, to: share, container: container)
        } catch let error where CloudErrors.isCoreDataCloudKitError(error) {
            try? await Task.sleep(for: .seconds(2))
            result = try await Self.shareInBackground(ids, to: share, container: container)
        }
        if share == nil {
            // It sets its share up again, with the family, next time it refreshes.
            AlertInboxes.shared.refreshSoon(force: true)
        }
        return await resolvedLogShare(result, for: babies)
    }

    /// `container.share` on a background context. Core Data waits for the store inside it, and on the
    /// main thread that froze the screen for seconds (a hang report showed 2 s on Invite partner).
    private static func shareInBackground(
        _ ids: [NSManagedObjectID], to share: CKShare?, container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        let context = container.newBackgroundContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                let objects = ids.map { context.object(with: $0) }
                container.share(objects, to: share) { _, share, _, error in
                    if let share {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: error ?? CKError(.internalError))
                    }
                }
            }
        }
    }

    /// Both the log's share and the nursery monitor's are zone-wide shares, which CloudKit always
    /// names `cloudkit.zoneshare` (in different zones). When the log's share was made while the
    /// monitor's existed, `container.share` handed back the monitor's ("Nursery monitor alerts"),
    /// so the invitation would have shared alerts, not the log. The monitor's share is removed just
    /// before (`AlertInboxes` makes it again), and a wrong answer is looked past in `resolvedLogShare`.
    private func clearAlertInboxShare() async {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: AlertInboxes.ownZoneID)
        _ = try? await cloudKitContainer.privateCloudDatabase.modifyRecords(
            saving: [], deleting: [shareID], savePolicy: .ifServerRecordUnchanged, atomically: false
        )
    }

    /// `share` if it's the log's; otherwise the log's own share, looked up by its babies and in the
    /// private store, a few times while Core Data finishes saving it.
    private func resolvedLogShare(_ share: CKShare, for babies: [Baby]) async -> CKShare {
        guard !Self.isLogShare(share) else { return share }
        let container = self.container
        let ids = babies.map(\.objectID)
        let store = privateStore
        for attempt in 0..<3 {
            let found = await Task.detached { () -> CKShare? in
                if let byBaby = (try? container.fetchShares(matching: ids))?.values.first(where: Self.isLogShare) {
                    return byBaby
                }
                return store.flatMap { Self.logShare(in: $0, container: container) }
            }.value
            if let found {
                lastShareSource += " · looked up"
                return found
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
        lastShareSource += " · not found"
        return share
    }

    /// The title Apple's sharing sheet and the invitation show, from the babies' names. The sheet
    /// writes it into the share when it saves (`SharingDelegate.itemTitle`), with the picture.
    /// Saving the share a second time from here, right after `container.share`, crashed inside
    /// CloudKit. The title is visible to Apple, like any share's (the privacy page says so).
    /// Nil on a phone that only joined a partner's log, whose share keeps the owner's title.
    @MainActor
    var invitationTitle: String? {
        let babies = ownBabies()
        return babies.isEmpty ? nil : Self.shareTitle(for: babies)
    }

    /// "Ava's care log", or "Our babies' care log" for twins and siblings.
    private static func shareTitle(for babies: [Baby]) -> String {
        guard babies.count < 2 else {
            return String(localized: "Our babies' care log", comment: "Title of the shared log, for twins or siblings, in the invitation")
        }
        guard let name = babies.first?.name, !name.isEmpty else {
            return String(localized: "Baby's care log", comment: "Title of the shared log in the invitation, for a baby with no name yet")
        }
        return String(localized: "\(name)'s care log", comment: "Title of the shared log in the invitation; the baby's name")
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
            awaitImport(.sharedBaby, message: String(localized: "Joining your partner's log…"))
        } catch {
            CloudStatus.shared.lastError = CloudErrors.sharingMessage(
                for: error, otherwise: String(localized: "Couldn't join the shared log. Please try again in a minute.")
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
        // Off the main thread: Core Data waits for the store inside this call, which froze the
        // share sheet for most of a second when it saved.
        let container = self.container
        DispatchQueue.global(qos: .userInitiated).async {
            container.persistUpdatedShare(share, in: store) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    let reason = error.localizedDescription
                    CloudStatus.shared.lastError = String(
                        localized: "Couldn't save the sharing changes: \(reason)",
                        comment: "The system's description of the error"
                    )
                }
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

        await takeDownContent(showing: String(localized: "Leaving the shared log…"))
        let purgeError: Error? = await withCheckedContinuation { continuation in
            container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore) { _, error in
                continuation.resume(returning: error)
            }
        }
        if let purgeError {
            let reason = purgeError.localizedDescription
            status.lastError = String(
                localized: "Couldn't remove the shared log from this iPhone: \(reason)",
                comment: "The system's description of the error"
            )
        }
        // The purge doesn't reach objects already loaded, so start the screens over from the store.
        viewContext.reset()
        status.refreshSharing(self)
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
        await takeDownContent(showing: String(localized: "Deleting your iCloud copy…"))
        UserDefaults.shared.set(true, forKey: SettingsKey.iCloudDeletionPending)
        if Self.isSyncEnabled {
            reopenStores(sync: false)
        }
        await finishICloudDeletion()
        CloudStatus.shared.reloadingMessage = nil
    }

    /// Whether the last launch stopped because the database file held what a build run from Xcode
    /// had synced with CloudKit's Development environment (builds before `storeSuffix`).
    static var lastLaunchHitEnvironmentMixUp: Bool {
        LastCrash.previous?.contains("Cannot replace assigned container ID") == true
    }

    /// On the safe launch after that crash: rebuilds the log's database without CloudKit's records of
    /// what it synced (keeping every entry), drops the shared store (a partner's log, which comes back
    /// when they invite again), deletes the private zones in iCloud, which only held this iPhone's
    /// older entries, and turns sync back on, which uploads the whole log again. A partner who shared
    /// this log needs a new invitation, since the old share was in the deleted zone.
    @MainActor
    func repairAfterEnvironmentMixUp() async {
        let wantsSync = Self.isSyncEnabled
        await takeDownContent(showing: String(localized: "Repairing iCloud sync…"))
        UserDefaults.shared.set(false, forKey: SettingsKey.iCloudSync)
        UserDefaults.shared.set(true, forKey: SettingsKey.iCloudDeletionPending)

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        try? coordinator.destroyPersistentStore(at: Self.sharedURL, type: .sqlite, options: Self.localStoreOptions)
        loadStores(sync: false)

        let repaired = await finishICloudDeletion()
        CloudStatus.shared.reloadingMessage = nil
        if repaired && wantsSync {
            await setSyncEnabled(true)
        }
        if repaired {
            CloudStatus.shared.lastError = String(
                localized: "MyBaby repaired its iCloud sync, and every entry on this iPhone is safe. If you share the log with your partner, invite them again from More › Settings."
            )
        }
    }

    /// Steps 2 and 3 of `deleteICloudCopy`, while sync is off and nothing is on screen. Returns
    /// false, with the reason in `lastError`, if it couldn't finish.
    @MainActor
    @discardableResult
    private func finishICloudDeletion() async -> Bool {
        do {
            try await deleteCloudKitZones()
        } catch {
            let reason = error.localizedDescription
            CloudStatus.shared.lastError = String(
                localized: "Couldn't delete your iCloud copy, so iCloud sync is off for now. Your log is still on this iPhone. Check that you're online and signed in to iCloud, then tap Finish deleting iCloud copy in Settings. (\(reason))",
                comment: "“Finish deleting iCloud copy” is a button in Settings; the system's description of the error is in brackets"
            )
            return false
        }
        do {
            try startPrivateStoreOver()
        } catch {
            let reason = error.localizedDescription
            CloudStatus.shared.lastError = String(
                localized: "Your iCloud copy was deleted, but this iPhone couldn't finish tidying up, so iCloud sync stays off for now. Your log is still here. Tap Finish deleting iCloud copy in Settings to try again. (\(reason))",
                comment: "“Finish deleting iCloud copy” is a button in Settings; the system's description of the error is in brackets"
            )
            return false
        }
        UserDefaults.shared.set(false, forKey: SettingsKey.iCloudDeletionPending)
        return true
    }

    /// Deletes the zones Core Data keeps the log in from this Apple ID's private database: the
    /// main zone, and any left over from sharing that was stopped. A zone that's already gone
    /// (from an earlier try, or deleted in iPhone Settings) counts as deleted. Deleting a zone also
    /// deletes the shares in it. Also used by `DataWipe`.
    @MainActor
    func deleteCloudKitZones() async throws {
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

    // MARK: Deleting everything on this iPhone

    /// The folder the database files are in (see `folder`).
    static var storeFolder: URL { folder }

    /// Whether `name`, in `storeFolder`, belongs to the stores: the database files with their -wal and
    /// -shm files, Core Data's hidden support folders (photos kept outside the database) and the files
    /// NSPersistentCloudKitContainer keeps there, like `ckAssetFiles`.
    static func isStoreItem(_ name: String) -> Bool {
        name.hasPrefix("MyBaby-") || name.hasPrefix(".MyBaby-") || name.hasPrefix("ckAsset")
    }

    /// For `DataWipe` only, while nothing is on screen: closes both stores, destroys their database
    /// files and everything kept next to them, then opens new, empty stores without iCloud
    /// (`reopenStores(sync: false)`). Done in one go on the main actor, so nothing can use the
    /// coordinator while it has no stores. Returns what couldn't be removed; anything left over would
    /// only be files, never shown, since the new stores are opened from new files.
    @MainActor
    func eraseLocalStores() -> [Error] {
        // Nothing unsaved may be written back afterwards.
        viewContext.reset()
        removeAllStores()
        privateStore = nil
        sharedStore = nil

        var errors: [Error] = []
        let coordinator = container.persistentStoreCoordinator
        let fresh = Self.folder.appendingPathComponent("MyBaby-private-fresh.sqlite")
        for url in [Self.privateURL, Self.sharedURL, fresh] where FileManager.default.fileExists(atPath: url.path) {
            do {
                try coordinator.destroyPersistentStore(at: url, type: .sqlite, options: Self.localStoreOptions)
            } catch {
                errors.append(error)
            }
        }
        // The -wal and -shm files, support folders and CloudKit's files, if any are left. In the App
        // Group the folder holds only the stores; without it, it's the app's own Application Support.
        let fileManager = FileManager.default
        let onlyStores = AppGroup.containerURL != nil
        let names = (try? fileManager.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        for name in names where onlyStores || Self.isStoreItem(name) {
            do {
                try fileManager.removeItem(at: Self.folder.appendingPathComponent(name))
            } catch {
                errors.append(error)
            }
        }
        // The old database is gone whatever happened, so new, empty files are opened.
        reopenStores(sync: false)
        return errors
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
        awaitImport(.restore(turnedOnSync: turnedOnSync), message: String(localized: "Looking for your log in iCloud…"))
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
                CloudStatus.shared.lastError = String(
                    localized: "Your partner's log hasn't downloaded yet. Check that both iPhones are online and signed in to iCloud, then open the invitation link again."
                )
            }
        case .restore(let turnedOnSync):
            if timedOut {
                CloudStatus.shared.lastError = String(
                    localized: "No MyBaby log was found in your iCloud. Check that this iPhone is online and signed in with the Apple ID you used before, then try again."
                )
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

    var errorDescription: String? { String(localized: "Turn on iCloud sync to share the log.") }
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

    /// Whether this iPhone has a log someone else shared (`PersistenceController.hasJoinedLog`).
    /// Kept here, like `viewOnlyBabies`, so screens don't ask the store on every render: each lookup
    /// goes through the store coordinator on the main thread, and waits while iCloud is importing.
    /// Looked up again when the stores open, when sharing stops, and shortly after changes arrive
    /// (`refreshSharing`), which covers joining a log, leaving it and the owner changing permissions.
    @Published private(set) var hasJoinedLog = false
    /// The babies this iPhone can't change, invited as view only (`PersistenceController.canEdit`).
    @Published private(set) var viewOnlyBabies: Set<NSManagedObjectID> = []

    private var remoteChangeObserver: NSObjectProtocol?
    private var pendingSharingRefresh: Task<Void, Never>?

    private init() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSharingSoon() }
        }
    }

    /// Whether this iPhone can change `baby`'s log (see `PersistenceController.canEdit`).
    func canEdit(_ baby: Baby) -> Bool {
        !viewOnlyBabies.contains(baby.objectID)
    }

    /// See `PersistenceController.canAddBabies`.
    var canAddBabies: Bool { !hasJoinedLog }

    /// Looks up `hasJoinedLog` and `viewOnlyBabies` again, right away.
    func refreshSharing(_ persistence: PersistenceController = .shared) {
        pendingSharingRefresh?.cancel()
        pendingSharingRefresh = nil
        let joined = persistence.hasJoinedLog
        let viewOnly = persistence.viewOnlyBabyIDs()
        if joined != hasJoinedLog { hasJoinedLog = joined }
        if viewOnly != viewOnlyBabies { viewOnlyBabies = viewOnly }
    }

    /// Shortly, so a burst of changes (an iCloud import) looks once.
    private func refreshSharingSoon() {
        pendingSharingRefresh?.cancel()
        pendingSharingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshSharing()
        }
    }
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
