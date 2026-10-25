import CloudKit
import Combine
import CoreData
import Foundation

/// How iCloud sync is doing, for the status row under "Sync with iCloud" in Settings (`SyncStatusRow`).
///
/// Started once at launch (`MyBabyApp.init`), before the stores open, so it sees iCloud's setup.
/// It follows NSPersistentCloudKitContainer's setup, import and export events (with any object,
/// so it keeps working when the stores are reopened in a new container), and, while sync is on,
/// the iCloud account (`CKAccountChanged`). It only reports; it never changes or deletes anything.
@MainActor
final class SyncStatus: ObservableObject {
    static let shared = SyncStatus()

    /// What the row shows, most important first.
    enum State: Equatable {
        case syncing
        case upToDate(lastSynced: Date?)
        case waitingForConnection
        /// `canRetry`: checking the iCloud account again could fix it (Try again).
        case problem(String, canRetry: Bool)
    }

    /// True while a setup, import or export is running.
    @Published private(set) var isSyncing = false
    /// When an import or export last finished without an error. Kept across launches.
    @Published private(set) var lastSynced: Date?
    /// Why the last event failed, until one succeeds.
    @Published private(set) var syncIssue: CloudErrors.SyncIssue?
    /// What's wrong with the iCloud account, while sync is on.
    @Published private(set) var accountProblem: ICloudProblem?

    var state: State {
        if let accountProblem {
            return .problem(accountProblem.message, canRetry: true)
        }
        if let syncIssue {
            return syncIssue.isWaitingForConnection ? .waitingForConnection : .problem(syncIssue.message, canRetry: false)
        }
        if isSyncing { return .syncing }
        return .upToDate(lastSynced: lastSynced)
    }

    /// Events that started and haven't finished.
    private var running: Set<UUID> = []
    /// Stores (by identifier) whose iCloud setup has finished since the stores were last opened.
    private var finishedSetups: Set<String> = []
    /// The iCloud user sync started with, to notice when the iPhone signs in to another account.
    private var accountUser: CKRecord.ID?
    private var subscriptions: Set<AnyCancellable> = []
    private static let lastSyncedKey = "SyncStatus.lastSynced"

    private init() {
        lastSynced = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        let center = NotificationCenter.default
        center.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event
                else { return }
                MainActor.assumeIsolated { self?.handle(event) }
            }
            .store(in: &subscriptions)
        center.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.retry() }
            }
            .store(in: &subscriptions)
        if PersistenceController.isSyncEnabled {
            retry()
        }
    }

    /// Starts over after the stores were reopened to turn sync on or off: nothing is running in
    /// the new stores yet, and old problems no longer apply.
    func restart() {
        running = []
        isSyncing = false
        finishedSetups = []
        syncIssue = nil
        accountProblem = nil
        accountUser = nil
        if PersistenceController.isSyncEnabled {
            retry()
        }
    }

    /// Whether NSPersistentCloudKitContainer has finished setting up `store` with iCloud, with or
    /// without an error. See `PersistenceController.waitForCloudKitSetup`.
    func hasFinishedSetup(of store: NSPersistentStore) -> Bool {
        guard let identifier = store.identifier else { return false }
        return finishedSetups.contains(identifier)
    }

    /// Checks the iCloud account again: when it changes, and from the row's Try again.
    func retry() {
        Task { await checkAccount() }
    }

    private func checkAccount() async {
        guard PersistenceController.isSyncEnabled else {
            accountProblem = nil
            return
        }
        let persistence = PersistenceController.shared
        if let problem = await persistence.iCloudAvailability() {
            accountProblem = problem
            return
        }
        // Signed in. Compare with the account sync started with, if CloudKit can say who it is.
        guard let user = try? await persistence.cloudKitContainer.userRecordID() else {
            accountProblem = nil
            return
        }
        if let accountUser, accountUser != user {
            accountProblem = .accountChanged
        } else {
            accountUser = user
            accountProblem = nil
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        // Each event is posted when it starts, and again with an end date when it finishes.
        guard let endDate = event.endDate else {
            running.insert(event.identifier)
            isSyncing = true
            return
        }
        running.remove(event.identifier)
        isSyncing = !running.isEmpty
        if event.type == .setup {
            finishedSetups.insert(event.storeIdentifier)
        }
        if event.succeeded {
            syncIssue = nil
            if event.type == .import || event.type == .export {
                lastSynced = endDate
                UserDefaults.standard.set(endDate, forKey: Self.lastSyncedKey)
            }
        } else if let error = event.error {
            syncIssue = CloudErrors.syncIssue(for: error)
        }
    }
}
