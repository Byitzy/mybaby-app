import CloudKit
import CoreData
import Foundation

/// Why iCloud can't be used for sync right now.
enum ICloudProblem: Equatable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    /// CloudKit couldn't say, usually because the iPhone is offline.
    case couldNotDetermine
    /// Sync is on, and the iPhone is now signed in to a different iCloud account than when it started.
    case accountChanged

    var message: String {
        switch self {
        case .noAccount:
            return "Sign in to iCloud in the Settings app (tap your name at the top) to sync MyBaby."
        case .restricted:
            return "iCloud is restricted on this iPhone (for example by Screen Time or a work profile)."
        case .temporarilyUnavailable:
            return "iCloud isn't available right now. Check that iCloud is set up in Settings and try again."
        case .couldNotDetermine:
            return "Couldn't reach iCloud. Check your connection and try again."
        case .accountChanged:
            return "This iPhone is signed in to a different iCloud account now. Sign back in to the one you used before to keep syncing this log."
        }
    }
}

extension PersistenceController {
    /// What stops iCloud from being used right now, or nil when the account is ready.
    @MainActor
    func iCloudAvailability() async -> ICloudProblem? {
        do {
            switch try await cloudKitContainer.accountStatus() {
            case .available: return nil
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .couldNotDetermine
            @unknown default: return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    /// Checked before anything turns sync on (`setSyncEnabled(true)`). When iCloud can't be used,
    /// says why in an alert and returns false, so sync stays off.
    @MainActor
    func confirmICloudAvailable() async -> Bool {
        guard let problem = await iCloudAvailability() else { return true }
        CloudStatus.shared.lastError = problem.message
        return false
    }

    /// Waits until NSPersistentCloudKitContainer has finished setting up `store` with iCloud, or
    /// `timeout` passes. Sharing or joining before then fails (Cocoa error 134410), which happened
    /// when Invite partner turned sync on and shared straight away. Shows "Connecting to iCloud…"
    /// meanwhile, and returns at once when the setup already happened.
    @MainActor
    func waitForCloudKitSetup(of store: NSPersistentStore?, timeout: Duration = .seconds(20)) async {
        guard Self.isSyncEnabled, let store else { return }
        let syncStatus = SyncStatus.shared
        guard !syncStatus.hasFinishedSetup(of: store) else { return }

        let cloudStatus = CloudStatus.shared
        let previousMessage = cloudStatus.reloadingMessage
        cloudStatus.reloadingMessage = "Connecting to iCloud…"
        defer { cloudStatus.reloadingMessage = previousMessage }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !syncStatus.hasFinishedSetup(of: store), ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                break
            }
        }
    }

    #if DEBUG
    /// Debug builds only, from Settings › About · Debug build. Creates every record type and field
    /// in the CloudKit **Development** environment, so they can all be deployed to Production in
    /// the CloudKit Console. TestFlight and App Store builds use Production, and sharing fails
    /// there until the schema is deployed. Must never run in release builds: it uploads test
    /// records to the signed-in account. Returns what happened, for an alert.
    @MainActor
    func createCloudKitSchema() async -> String {
        guard Self.isSyncEnabled else {
            return "Turn on Sync with iCloud first. The schema is created through the synced stores."
        }
        let container = self.container
        do {
            // Talks to iCloud and takes a while, so off the main thread.
            try await Task.detached { try container.initializeCloudKitSchema(options: []) }.value
            return "The iCloud schema was created in the Development environment. Now open the CloudKit Console and deploy the schema changes to Production."
        } catch {
            return "Couldn't create the iCloud schema.\n\n\(CloudErrors.details(for: error))"
        }
    }
    #endif
}
