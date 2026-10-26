import CloudKit
import CoreData
import Observation
import UIKit

/// Each parent phone's private "alert inbox" in iCloud, so a nursery monitor can reach it without a server.
///
/// CloudKit shows a normal, visible push notification for a `CKQuerySubscription`, but only in a database
/// the subscriber owns. (Subscriptions in the shared database cover the whole database, so they would
/// fire for every log entry.) So:
/// 1. Each parent phone makes a record zone, `MyBabyAlertInbox`, in its **own private database**, and
///    subscribes to new `CryAlert` records in it. CloudKit then pushes "👶 Your baby is crying" for each one.
/// 2. It shares that zone with the family: the people the log is shared with, who can make changes.
/// 3. It publishes where to deliver as an `AlertInbox` row, synced with the log, end-to-end encrypted.
/// 4. Family devices, and the monitor, join each other's inboxes from those rows. The monitor then
///    writes a `CryAlert` into the inbox of the parent on duty (see `RemoteCryAlerts`).
///
/// The zone isn't part of the Core Data log, so it's handled with `CKContainer` directly. The records carry
/// only a time, a kind and how long the crying has gone on, all encrypted, never a name. The pushes don't
/// count against iOS's 64 pending local notifications (see `NotificationManager`).
///
/// Never keeps the Core Data container or its context: they're read fresh each time, since the stores are
/// reopened when iCloud is switched on or off.
@MainActor
@Observable
final class AlertInboxes {
    static let shared = AlertInboxes()

    static let zoneName = "MyBabyAlertInbox"
    static let cryRecordType = "CryAlert"
    /// Test alerts are their own record type, so they get their own wording ("Test from the nursery
    /// monitor"): a subscription's text is fixed, and can't come from encrypted fields.
    static let testRecordType = "CryAlertTest"
    static let crySubscriptionID = "MyBabyAlertInbox-cry"
    static let testSubscriptionID = "MyBabyAlertInbox-test"
    /// This Apple ID's own inbox, in its private database.
    static let ownZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    /// Records older than this are deleted.
    static let alertLifetime: TimeInterval = 3600

    static var container: CKContainer { CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier) }

    /// For Cry alerts: whether this phone is ready for alerts from a nursery monitor, or what's in the way.
    private(set) var status: String?
    private(set) var isReady = false

    /// Set up at most this often, unless something changed.
    private static let refreshInterval: TimeInterval = 10 * 60
    /// A failed attempt to join an inbox isn't tried again sooner than this.
    private static let acceptRetryInterval: TimeInterval = 60

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var pendingSettingsCheck: Task<Void, Never>?
    @ObservationIgnored private var lastSignature: String?
    @ObservationIgnored private var cleanedUpThisLaunch = false
    @ObservationIgnored private var savedSubscriptionsThisLaunch = false
    @ObservationIgnored private var userRecordName: String?
    @ObservationIgnored private var failedAccepts: [String: Date] = [:]
    /// Kept in UserDefaults through `setJoined`.
    @ObservationIgnored private var joined: [String: Joined] = [:]

    /// Inboxes this device has joined, by the owner's user record name.
    private struct Joined: Codable {
        var shareURL: String
        /// The zone's owner as this device sees it.
        var zoneOwnerName: String
    }

    private enum Key {
        static let rows = "alertInbox.rows"
        static let joined = "alertInbox.joined"
        static let subscriptionSignature = "alertInbox.subscriptionSignature"
        static let subscriptionIDs = "alertInbox.subscriptionIDs"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Key.joined),
           let saved = try? JSONDecoder().decode([String: Joined].self, from: data) {
            joined = saved
        }
    }

    private func setJoined(_ inbox: Joined?, for owner: String) {
        joined[owner] = inbox
        if let data = try? JSONEncoder().encode(joined) {
            UserDefaults.standard.set(data, forKey: Key.joined)
        }
    }

    // MARK: Starting

    /// Called once at launch. Sets up this phone's inbox when sync is on, and again when the app comes to
    /// the front, iCloud is switched on, or *This iPhone belongs to* or the alert style changes.
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AlertInboxes.shared.refreshSoon(force: false) }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AlertInboxes.shared.settingsMayHaveChanged() }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in AlertInboxes.shared.accountChanged() }
        })
        lastSignature = settingsSignature
        refreshSoon(force: true)
    }

    /// After a moment, so the stores have finished opening after a switch.
    func refreshSoon(force: Bool) {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await refresh(force: force)
        }
    }

    /// What the inbox depends on: whether iCloud is on, and whose phone this is and how it alerts.
    private var settingsSignature: String {
        let plan = NightPlan.load()
        return [
            "\(PersistenceController.isSyncEnabled)", plan.alarmOwner.rawValue, plan.alarmStyle.rawValue,
            plan.name(of: .parent1), plan.name(of: .parent2),
        ].joined(separator: "|")
    }

    /// Settings change often (every slider move), so this looks once things have settled.
    private func settingsMayHaveChanged() {
        guard pendingSettingsCheck == nil else { return }
        pendingSettingsCheck = Task {
            try? await Task.sleep(for: .seconds(1))
            pendingSettingsCheck = nil
            let signature = settingsSignature
            guard signature != lastSignature else { return }
            lastSignature = signature
            refreshSoon(force: true)
        }
    }

    private func accountChanged() {
        userRecordName = nil
        failedAccepts = [:]
        joined = [:]
        UserDefaults.standard.removeObject(forKey: Key.joined)
        refreshSoon(force: true)
    }

    /// After Delete all MyBaby data: forgets the inboxes this device joined and everything it learned
    /// while setting up its own, so nothing from before is used again. `DataWipe` deletes the zones
    /// and subscriptions in iCloud; with sync off, `refresh` does nothing until it's turned on again.
    func forgetEverything() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingSettingsCheck?.cancel()
        pendingSettingsCheck = nil
        userRecordName = nil
        failedAccepts = [:]
        joined = [:]
        lastRefresh = nil
        cleanedUpThisLaunch = false
        savedSubscriptionsThisLaunch = false
        UserDefaults.standard.removeObject(forKey: Key.joined)
        lastSignature = settingsSignature
        setStatus(nil, ready: false)
    }

    // MARK: Setting up

    /// Makes sure this phone's inbox, its subscription and its share exist, publishes it to the family,
    /// and joins the family's other inboxes. Safe to call often: it does the work at most every 10 minutes
    /// unless `force` is set.
    func refresh(force: Bool = false) async {
        guard PersistenceController.isSyncEnabled, CloudStatus.shared.reloadingMessage == nil, !isRefreshing else { return }
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        guard !CrashGuard.isPaused(.alertInboxes) else {
            setStatus(String(localized: "Alerts from a nursery monitor are paused on this iPhone after a problem. They try again tomorrow."), ready: false)
            return
        }
        isRefreshing = true
        // If the app ends in here, the next launches skip it for a day instead of crashing again.
        CrashGuard.begin(.alertInboxes)
        defer {
            isRefreshing = false
            CrashGuard.end(.alertInboxes)
        }

        let container = Self.container
        do {
            guard try await container.accountStatus() == .available else {
                setStatus(String(localized: "Sign in to iCloud on this iPhone to get alerts from a nursery monitor."), ready: false)
                return
            }
            let me = try await currentUserRecordName()
            if NurseryMonitor.isThisDeviceAMonitor {
                // The monitor sends alerts; it doesn't get them.
                removeOwnRows()
                setStatus(nil, ready: false)
            } else {
                let share = try await setUpOwnInbox(container: container, me: me)
                if let url = share.url?.absoluteString {
                    publishRows(shareURL: url, me: me)
                }
                if !cleanedUpThisLaunch {
                    try? await Self.deleteOldAlerts(
                        in: container.privateCloudDatabase, zoneID: Self.ownZoneID, lifetime: Self.alertLifetime
                    )
                    cleanedUpThisLaunch = true
                }
                setStatus(readyMessage, ready: true)
                await askForNotificationsIfThereIsAMonitor()
            }
            await joinFamilyInboxes(container: container, me: me)
            lastRefresh = .now
        } catch {
            setStatus(Self.notReadyMessage(for: error), ready: false)
        }
    }

    /// Plain words for why this phone can't get monitor alerts yet. Cry alerts on the phone itself
    /// don't depend on this. The technical reason is added in debug builds only.
    private static func notReadyMessage(for error: Error) -> String {
        var message: String
        if CloudErrors.isSchemaError(error) {
            message = String(localized: "Alerts from a nursery monitor aren't available in this version yet. Cry alerts on this iPhone still work.")
        } else {
            message = String(localized: "This iPhone couldn't get ready for alerts from a nursery monitor. It tries again the next time MyBaby opens.")
        }
        #if DEBUG
        if CloudErrors.isSchemaError(error) {
            message += "\n\n" + CloudErrors.developerSchemaNote
        }
        message += "\n\n" + CloudErrors.details(for: error)
        #endif
        return message
    }

    #if DEBUG
    /// Debug builds only, for Settings › Create iCloud schema: makes the `CryAlert` and `CryAlertTest`
    /// record types in CloudKit's Development environment, so they can be deployed to Production
    /// with the rest of the schema. They're plain CloudKit records, so Core Data's
    /// `initializeCloudKitSchema` doesn't know about them.
    func createSchemaForDeployment() async throws {
        let database = Self.container.privateCloudDatabase
        let (zoneResults, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.ownZoneID)], deleting: [])
        for result in zoneResults.values {
            _ = try result.get()
        }
        try await createRecordTypes(in: database)
    }
    #endif

    /// The iCloud user this device is signed in as, e.g. "_4c3f…". Kept until the account changes.
    func currentUserRecordName() async throws -> String {
        if let userRecordName { return userRecordName }
        let name = try await Self.container.userRecordID().recordName
        userRecordName = name
        return name
    }

    private var readyMessage: String {
        let plan = NightPlan.load()
        switch plan.alarmOwner {
        case .both:
            return String(localized: "This iPhone gets alerts from a nursery monitor for every shift.")
        case .parent1, .parent2:
            let parent: Parent = plan.alarmOwner == .parent1 ? .parent1 : .parent2
            return String(localized: "This iPhone gets alerts from a nursery monitor on \(plan.name(of: parent))'s shifts.")
        }
    }

    private func setStatus(_ message: String?, ready: Bool) {
        if status != message { status = message }
        if isReady != ready { isReady = ready }
    }

    /// The zone, the subscription and the share, each made only if it isn't there yet.
    private func setUpOwnInbox(container: CKContainer, me: String) async throws -> CKShare {
        let database = container.privateCloudDatabase
        let (zoneResults, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.ownZoneID)], deleting: [])
        for result in zoneResults.values {
            _ = try result.get()
        }
        try await saveSubscriptions(in: database)
        return try await saveShare(in: database, container: container, me: me)
    }

    /// One subscription for cry alerts and one for tests, firing when a record is created in this inbox.
    /// Saved again when the alert style changes, since the sound is part of it. Its words are in this
    /// phone's language: the subscription is this phone's own, and only it shows them.
    private func saveSubscriptions(in database: CKDatabase) async throws {
        let style = NightPlan.load().alarmStyle
        let signature = "1|\(style.rawValue)"
        let defaults = UserDefaults.standard
        guard !savedSubscriptionsThisLaunch || defaults.string(forKey: Key.subscriptionSignature) != signature else { return }

        let subscriptions = [
            Self.subscription(
                id: Self.crySubscriptionID, recordType: Self.cryRecordType,
                title: String(localized: "👶 Your baby is crying"),
                body: String(localized: "Heard just now.", comment: "Cry alert body: the crying was heard a moment ago"),
                style: style
            ),
            Self.subscription(
                id: Self.testSubscriptionID, recordType: Self.testRecordType,
                title: String(localized: "🔔 Test from the nursery monitor"),
                body: String(localized: "Alerts from the monitor will look like this."),
                style: style
            ),
        ]
        do {
            try await save(subscriptions, in: database)
        } catch where CloudErrors.isSchemaError(error) || (error as? CKError)?.code == .invalidArguments {
            // In CloudKit's development environment a record type only exists once a record of it has
            // been saved, and a subscription to a type that doesn't exist yet is refused. In Production
            // (TestFlight and the App Store) types can't be made this way: the schema has to be deployed.
            try await createRecordTypes(in: database)
            try await save(subscriptions, in: database)
        }
        defaults.set(signature, forKey: Key.subscriptionSignature)
        defaults.set(subscriptions.map(\.subscriptionID), forKey: Key.subscriptionIDs)
        savedSubscriptionsThisLaunch = true
    }

    private func save(_ subscriptions: [CKSubscription], in database: CKDatabase) async throws {
        for subscription in subscriptions {
            _ = try await database.save(subscription)
        }
    }

    /// Saves one record of each type, with the same encrypted fields the monitor writes, then deletes them.
    private func createRecordTypes(in database: CKDatabase) async throws {
        let records = [Self.cryRecordType, Self.testRecordType].map { type in
            CryAlertRecord.make(
                recordType: type, kind: .test, crySeconds: 0, createdAt: .now,
                recordName: "schema-\(type)", zoneID: Self.ownZoneID
            )
        }
        _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
        _ = try? await database.modifyRecords(
            saving: [], deleting: records.map(\.recordID), savePolicy: .ifServerRecordUnchanged, atomically: false
        )
    }

    /// The notification CloudKit shows for each new record. Its text is stored with the subscription, which
    /// isn't encrypted, so it never names anyone. Vibrate-only plays the same silent sound as reminders.
    private static func subscription(
        id: CKSubscription.ID, recordType: CKRecord.RecordType, title: String, body: String, style: AlarmStyle
    ) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        subscription.zoneID = ownZoneID
        let info = CKSubscription.NotificationInfo()
        // Both a title and a body, so it's always shown as an alert, never delivered silently.
        info.title = title
        info.subtitle = String(localized: "Nursery monitor", comment: "Subtitle of a cry alert sent by a spare device left by the baby")
        info.alertBody = body
        info.soundName = style == .vibrate ? "silence.wav" : "default"
        info.shouldBadge = false
        info.category = NotificationManager.cryAlertCategory
        subscription.notificationInfo = info
        return subscription
    }

    /// The zone-wide share for this inbox: private (no public link access), and open to the people the log
    /// is shared with who can make changes. Someone removed from the log is removed here too.
    private func saveShare(in database: CKDatabase, container: CKContainer, me: String) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.ownZoneID)
        var changed = false
        let share: CKShare
        if let existing = try await Self.existingShare(shareID, in: database) {
            share = existing
        } else {
            share = CKShare(recordZoneID: Self.ownZoneID)
            changed = true
        }

        if share.publicPermission != .none {
            share.publicPermission = .none
            changed = true
        }
        // Shown by iCloud to the family members the inbox is shared with.
        let title = String(localized: "Nursery monitor alerts", comment: "Name of the iCloud share that carries cry alerts")
        if share[CKShare.SystemFieldKey.title] as? String != title {
            share[CKShare.SystemFieldKey.title] = title
            changed = true
        }

        let family = familyUserRecordNames(excluding: me)
        for participant in share.participants where participant.role != .owner {
            guard let name = participant.userIdentity.userRecordID?.recordName, !family.contains(name) else { continue }
            share.removeParticipant(participant)
            changed = true
        }
        let present = Set(share.participants.compactMap { $0.userIdentity.userRecordID?.recordName })
        for name in family where !present.contains(name) {
            do {
                let participant = try await Self.shareParticipant(for: CKRecord.ID(recordName: name), container: container)
                participant.permission = .readWrite
                participant.role = .privateUser
                share.addParticipant(participant)
                changed = true
            } catch {
                // Tried again on the next refresh.
                print("MyBaby: couldn't add someone to the alert inbox: \(error)")
            }
        }

        guard changed else { return share }
        let (results, _) = try await database.modifyRecords(
            saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
        )
        if let result = results[share.recordID], let saved = try result.get() as? CKShare {
            return saved
        }
        return share
    }

    /// The inbox's share, or `nil` before it's made.
    private static func existingShare(_ id: CKRecord.ID, in database: CKDatabase) async throws -> CKShare? {
        do {
            return try await database.record(for: id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Everyone the log is shared with who can change it (so who could run a monitor), but not this user.
    /// From the log's own share: the owner's, or the one this phone joined.
    private func familyUserRecordNames(excluding me: String) -> Set<String> {
        let persistence = PersistenceController.shared
        var shares: [CKShare] = []
        if let own = persistence.ownShare { shares.append(own) }
        for baby in (try? persistence.viewContext.fetch(Baby.fetchAll())) ?? [] {
            if let share = persistence.existingShare(for: baby) { shares.append(share) }
        }
        var names: Set<String> = []
        for share in shares {
            for participant in share.participants
            where participant.permission == .readWrite && participant.acceptanceStatus != .removed {
                guard let name = participant.userIdentity.userRecordID?.recordName,
                      name != CKCurrentUserDefaultName, name != me else { continue }
                names.insert(name)
            }
        }
        return names
    }

    // MARK: Publishing

    /// The `AlertInbox` rows this device made, by baby `uuid`.
    private var ownRowIDs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Key.rows) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Key.rows) }
    }

    /// One row per baby this phone can change, so the monitor finds it whichever baby it listens for.
    private func publishRows(shareURL: String, me: String) {
        let persistence = PersistenceController.shared
        let context = persistence.viewContext
        let babies = ((try? context.fetch(Baby.fetchAll())) ?? []).filter { persistence.canEdit($0) }
        let plan = NightPlan.load()
        let deviceName = Self.phoneName(plan: plan)
        let stored = ownRowIDs
        var kept: [String: String] = [:]

        for baby in babies {
            guard let babyID = baby.uuid?.uuidString else { continue }
            let rows = baby.alertInboxes as? Set<AlertInbox> ?? []
            let mine = stored[babyID].flatMap { id in rows.first { $0.uuid?.uuidString == id } }
            // Left by an earlier install on this device: same Apple ID and name.
            for row in rows where row !== mine && row.ownerUserRecordName == me && row.deviceName == deviceName {
                context.delete(row)
            }
            let row = mine ?? Self.newRow(for: baby, in: context)
            if row.owner != plan.alarmOwner || row.shareURL != shareURL
                || row.ownerUserRecordName != me || row.deviceName != deviceName {
                row.owner = plan.alarmOwner
                row.shareURL = shareURL
                row.ownerUserRecordName = me
                row.deviceName = deviceName
                row.updatedAt = .now
            }
            if let id = row.uuid?.uuidString {
                kept[babyID] = id
            }
        }
        ownRowIDs = kept
        context.saveIfChanged()
    }

    private static func newRow(for baby: Baby, in context: NSManagedObjectContext) -> AlertInbox {
        let row = AlertInbox(context: context)
        row.uuid = UUID()
        row.updatedAt = .now
        // In the baby's store, so it syncs to whoever the baby is shared with.
        if let store = baby.objectID.persistentStore {
            context.assign(row, to: store)
        }
        row.baby = baby
        return row
    }

    /// The monitor removes its own rows, so alerts aren't sent to it.
    private func removeOwnRows() {
        let ids = Set(ownRowIDs.values)
        guard !ids.isEmpty else { return }
        let context = PersistenceController.shared.viewContext
        for row in (try? context.fetch(AlertInbox.fetchAll())) ?? [] where ids.contains(row.uuid?.uuidString ?? "") {
            context.delete(row)
        }
        context.saveIfChanged()
        ownRowIDs = [:]
    }

    /// Whether `row` was published by this device.
    func isOwnRow(_ row: AlertInbox) -> Bool {
        guard let id = row.uuid?.uuidString else { return false }
        return ownRowIDs.values.contains(id)
    }

    /// "Sam's iPhone", or just "iPhone" when the phone is for both parents.
    static func phoneName(plan: NightPlan) -> String {
        let model = UIDevice.current.model
        switch plan.alarmOwner {
        case .parent1: return String(localized: "\(plan.name(of: .parent1))'s \(model)", comment: "A parent's device, e.g. Sam's iPhone")
        case .parent2: return String(localized: "\(plan.name(of: .parent2))'s \(model)", comment: "A parent's device, e.g. Sam's iPhone")
        case .both: return model
        }
    }

    /// CloudKit's pushes need notification permission. Only asked once a monitor is in use.
    private func askForNotificationsIfThereIsAMonitor() async {
        let context = PersistenceController.shared.viewContext
        guard ((try? context.count(for: MonitorDevice.fetchAll())) ?? 0) > 0 else { return }
        _ = await NotificationManager.requestAuthorization()
    }

    // MARK: Joining the family's inboxes

    /// Joins every inbox in the family's rows that this device hasn't joined yet, apart from its own.
    private func joinFamilyInboxes(container: CKContainer, me: String) async {
        let context = PersistenceController.shared.viewContext
        let rows = (try? context.fetch(AlertInbox.fetchAll())) ?? []
        // Copied out first: the rows may be gone after the awaits below.
        var inboxes: [String: String] = [:]
        for row in rows where row.ownerUserRecordName != me && !row.ownerUserRecordName.isEmpty && !row.shareURL.isEmpty {
            if inboxes[row.ownerUserRecordName] == nil {
                inboxes[row.ownerUserRecordName] = row.shareURL
            }
        }
        for (owner, url) in inboxes {
            _ = await joinedZone(owner: owner, shareURL: url, container: container)
        }
    }

    /// The zone to write to for someone else's inbox, joining it first if needed. `nil` when it can't be
    /// joined yet, usually because that phone hasn't added this device to its share (it does the next
    /// time MyBaby opens on it).
    func joinedZone(owner: String, shareURL: String, container: CKContainer) async -> CKRecordZone.ID? {
        if let existing = joined[owner], existing.shareURL == shareURL {
            return CKRecordZone.ID(zoneName: Self.zoneName, ownerName: existing.zoneOwnerName)
        }
        if let failed = failedAccepts[shareURL], Date.now.timeIntervalSince(failed) < Self.acceptRetryInterval {
            return nil
        }
        guard let url = URL(string: shareURL) else { return nil }
        do {
            let metadata = try await Self.shareMetadata(for: url, container: container)
            // Our own inbox, on another device with this Apple ID: written to directly.
            guard metadata.participantRole != .owner else { return nil }
            if metadata.participantStatus != .accepted {
                try await Self.accept(metadata, container: container)
            }
            let zoneID = metadata.share.recordID.zoneID
            setJoined(Joined(shareURL: shareURL, zoneOwnerName: zoneID.ownerName), for: owner)
            failedAccepts[shareURL] = nil
            return CKRecordZone.ID(zoneName: Self.zoneName, ownerName: zoneID.ownerName)
        } catch {
            failedAccepts[shareURL] = .now
            print("MyBaby: couldn't join an alert inbox: \(error)")
            return nil
        }
    }

    /// After a write was refused (the share was stopped, or the zone is gone), join again next time.
    func forgetJoined(owner: String) {
        setJoined(nil, for: owner)
    }

    // MARK: CloudKit calls

    /// Wraps CKFetchShareMetadataOperation. Built outside the main actor: CloudKit calls back on its own queue.
    private nonisolated static func shareMetadata(for url: URL, container: CKContainer) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let box = ResultBox<CKShare.Metadata>()
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = false
            operation.perShareMetadataResultBlock = { _, result in
                box.result = result
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(with: box.result ?? .failure(CKError(.unknownItem)))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// Wraps CKAcceptSharesOperation.
    private nonisolated static func accept(_ metadata: CKShare.Metadata, container: CKContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = ResultBox<CKShare>()
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.perShareResultBlock = { _, result in
                box.result = result
            }
            operation.acceptSharesResultBlock = { result in
                if case .failure(let error) = result {
                    continuation.resume(throwing: error)
                } else if case .failure(let error)? = box.result {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            container.add(operation)
        }
    }

    /// A participant to add to a share, looked up from their iCloud user record.
    private nonisolated static func shareParticipant(for userRecordID: CKRecord.ID, container: CKContainer) async throws -> CKShare.Participant {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchShareParticipant(withUserRecordID: userRecordID) { participant, error in
                if let participant {
                    continuation.resume(returning: participant)
                } else {
                    continuation.resume(throwing: error ?? CKError(.unknownItem))
                }
            }
        }
    }

    /// Deletes alerts older than an hour from an inbox, found through the zone's changes (which needs no
    /// query index). Their age is in their record names (see `CryAlertRecord`), so nothing is downloaded.
    nonisolated static func deleteOldAlerts(in database: CKDatabase, zoneID: CKRecordZone.ID, lifetime: TimeInterval) async throws {
        var token: CKServerChangeToken?
        var old: [CKRecord.ID] = []
        var moreComing = true
        while moreComing {
            let (modifications, _, newToken, more) = try await database.recordZoneChanges(
                inZoneWith: zoneID, since: token, desiredKeys: [], resultsLimit: nil
            )
            old += modifications.keys.filter { CryAlertRecord.isExpired($0, lifetime: lifetime) }
            token = newToken
            moreComing = more
        }
        var start = 0
        while start < old.count {
            let chunk = Array(old[start..<min(start + 200, old.count)])
            _ = try await database.modifyRecords(
                saving: [], deleting: chunk, savePolicy: .ifServerRecordUnchanged, atomically: false
            )
            start += 200
        }
    }
}

/// Holds a CloudKit operation's per-item result until its final callback. The operation calls both on
/// its own queue, one after the other.
private final class ResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
}
