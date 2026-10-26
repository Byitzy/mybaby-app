import CloudKit
import CoreData
import Observation
import SwiftUI

/// What a nursery monitor's alert is about.
enum CryAlertKind: String {
    case cry
    case stillCrying
    case test
}

/// Whose phones an alert goes to.
enum CryAlertAudience {
    /// The parent on duty now (and phones that are for both parents), or everyone when there's no shift.
    case onDuty
    /// The other parent, when the crying goes on (`NightPlan.cryEscalationMinutes`).
    case offDuty
    /// Every parent's phone, for a test.
    case everyone
}

/// The `CryAlert` records a monitor writes into a parent's inbox.
///
/// Only a time, a kind and how long the crying has gone on, all in `encryptedValues`, so Apple can't read
/// them. The record name starts with the kind and the time it was made ("cry-1761364800-…"), so old ones
/// can be found and deleted without downloading them; the kind and time alone say nothing about anyone.
enum CryAlertRecord {
    static func recordName(kind: CryAlertKind, createdAt: Date) -> String {
        "\(kind.rawValue)-\(Int(createdAt.timeIntervalSince1970))-\(UUID().uuidString)"
    }

    static func make(
        recordType: CKRecord.RecordType, kind: CryAlertKind, crySeconds: Double, createdAt: Date,
        recordName: String, zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        let kindValue: String = kind.rawValue
        let seconds: Double = crySeconds
        record.encryptedValues["createdAt"] = createdAt
        record.encryptedValues["kind"] = kindValue
        record.encryptedValues["crySeconds"] = seconds
        return record
    }

    /// Whether the record was made more than `lifetime` ago, going by its name.
    static func isExpired(_ recordID: CKRecord.ID, lifetime: TimeInterval, now: Date = .now) -> Bool {
        let parts = recordID.recordName.split(separator: "-")
        guard parts.count > 2, let seconds = TimeInterval(parts[1]) else { return false }
        return now.timeIntervalSince(Date(timeIntervalSince1970: seconds)) > lifetime
    }
}

/// Sends a nursery monitor's alerts to the parents' phones, by saving a `CryAlert` record into each
/// one's private inbox (see `AlertInboxes`). CloudKit then pushes a notification to that phone.
///
/// Alerts go to the parent on duty (from the night plan's `shift(at:)`) and to phones that are for both
/// parents; with no shift going on, to everyone. When it can't get through (offline, iCloud busy), it tries
/// again with a growing wait, for up to 10 minutes. Records are deleted an hour later.
@MainActor
@Observable
final class RemoteCryAlerts {
    static let shared = RemoteCryAlerts()

    /// Alerts waiting to be sent again, for the monitor screen.
    private(set) var waitingCount = 0

    /// An alert older than this isn't worth sending any more; a newer one will follow if the crying goes on.
    private static let maxAge: TimeInterval = 10 * 60

    private struct Target {
        /// The inbox owner's iCloud user record name.
        let owner: String
        let shareURL: String
        /// "Sam's iPhone".
        let name: String
    }

    private struct Delivery {
        let kind: CryAlertKind
        let crySeconds: Double
        let createdAt: Date
        /// The same on every try, so a try that got through without an answer isn't saved twice.
        let recordName: String
        let target: Target
        var attempts = 0
        var dueAt = Date.now
    }

    private enum Outcome {
        case sent
        /// Try again after a while, with what to tell the parent meanwhile.
        case retry(after: TimeInterval, note: String?)
        case failed(String)
    }

    /// A record this monitor wrote, so it can delete it an hour later.
    private struct Written: Codable {
        let recordName: String
        let zoneOwnerName: String
        let isOwn: Bool
        let createdAt: Date
    }

    private static let writtenKey = "remoteCryAlerts.written"

    @ObservationIgnored private var queue: [Delivery] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private init() {}

    // MARK: Sending

    /// Sends an alert and says what happened, e.g. "Sent to Sam's iPhone."
    func send(_ kind: CryAlertKind, crySeconds: Double, to audience: CryAlertAudience) async -> String {
        let targets = targets(for: audience)
        guard !targets.isEmpty else {
            if audience == .offDuty {
                return String(localized: "The crying went on, but the other parent's phone isn't set up for monitor alerts.")
            }
            return String(localized: "No parent's phone is ready for monitor alerts yet. Open MyBaby once on each parent's iPhone, with iCloud on.")
        }

        let createdAt = Date.now
        var sent: [String] = []
        var waiting: [String] = []
        var notes: [String] = []
        for target in targets {
            var delivery = Delivery(
                kind: kind, crySeconds: crySeconds, createdAt: createdAt,
                recordName: CryAlertRecord.recordName(kind: kind, createdAt: createdAt), target: target
            )
            switch await deliver(delivery) {
            case .sent:
                sent.append(target.name)
                // A newer alert got through; older ones still waiting for this phone don't matter now.
                dropQueued(for: target.owner)
            case .retry(let after, let note):
                delivery.attempts = 1
                delivery.dueAt = Date.now.addingTimeInterval(after)
                enqueue(delivery)
                waiting.append(target.name)
                if let note { notes.append(note) }
            case .failed(let reason):
                notes.append(reason)
            }
        }

        var summary: [String] = []
        if !sent.isEmpty {
            let phones = sent.formatted(.list(type: .and))
            summary.append(kind == .test
                ? String(localized: "Test sent to \(phones).", comment: "Nursery monitor; the phones' names, like Sam's iPhone and Alex's iPhone")
                : String(localized: "Sent to \(phones).", comment: "Nursery monitor; the phones' names, like Sam's iPhone and Alex's iPhone")
            )
        }
        if !waiting.isEmpty {
            let phones = waiting.formatted(.list(type: .and))
            summary.append(String(
                localized: "Couldn't reach \(phones) yet, so it's trying again.",
                comment: "Nursery monitor; the phones' names, like Sam's iPhone"
            ))
        }
        summary += notes
        return summary.joined(separator: " ")
    }

    /// The inboxes for `audience`, one per Apple ID: devices on the same Apple ID share an inbox.
    private func targets(for audience: CryAlertAudience) -> [Target] {
        let context = PersistenceController.shared.viewContext
        guard let baby = Baby.current(in: context) else { return [] }
        let inboxes = AlertInboxes.shared
        let rows = (baby.alertInboxes as? Set<AlertInbox> ?? []).filter { row in
            !row.shareURL.isEmpty && !row.ownerUserRecordName.isEmpty && !inboxes.isOwnRow(row)
        }
        let onDuty = NightPlan.load().shift(at: .now)?.parent

        var chosen: [AlertInbox]
        switch audience {
        case .everyone:
            chosen = Array(rows)
        case .onDuty:
            if let onDuty {
                chosen = rows.filter { $0.owner.includes(onDuty) }
                // Nobody's phone is set for this shift: better to wake someone than no one.
                if chosen.isEmpty { chosen = Array(rows) }
            } else {
                chosen = Array(rows)
            }
        case .offDuty:
            if let onDuty {
                // Phones for both parents already got the first alert.
                chosen = rows.filter { $0.owner.rawValue == onDuty.other.rawValue }
            } else {
                chosen = []
            }
        }

        var byOwner: [String: Target] = [:]
        for row in chosen.sorted(by: { $0.updatedAt > $1.updatedAt }) where byOwner[row.ownerUserRecordName] == nil {
            byOwner[row.ownerUserRecordName] = Target(
                owner: row.ownerUserRecordName,
                shareURL: row.shareURL,
                name: row.deviceName.isEmpty
                    ? String(localized: "a parent's phone", comment: "Stands in for a phone's name in the middle of a sentence")
                    : row.deviceName
            )
        }
        return byOwner.values.sorted { $0.name < $1.name }
    }

    /// One try at saving the alert into the target's inbox: straight into this Apple ID's private
    /// database when the inbox is its own, otherwise into the zone it joined in the shared database.
    private func deliver(_ delivery: Delivery) async -> Outcome {
        guard PersistenceController.isSyncEnabled else {
            return .failed(String(localized: "iCloud sync is off on this device, so it can't reach the parents' phones."))
        }
        let inboxes = AlertInboxes.shared
        let container = AlertInboxes.container
        let target = delivery.target
        let me: String
        do {
            me = try await inboxes.currentUserRecordName()
        } catch {
            return .retry(after: Self.backoff(delivery.attempts), note: nil)
        }

        let isOwn = target.owner == me
        let zoneID: CKRecordZone.ID
        if isOwn {
            zoneID = AlertInboxes.ownZoneID
        } else if let joined = await inboxes.joinedZone(owner: target.owner, shareURL: target.shareURL, container: container) {
            zoneID = joined
        } else {
            return .retry(after: 60, note: Self.notLetInNote(target.name))
        }

        let record = CryAlertRecord.make(
            recordType: delivery.kind == .test ? AlertInboxes.testRecordType : AlertInboxes.cryRecordType,
            kind: delivery.kind,
            crySeconds: delivery.crySeconds,
            createdAt: delivery.createdAt,
            recordName: delivery.recordName,
            zoneID: zoneID
        )
        let database = isOwn ? container.privateCloudDatabase : container.sharedCloudDatabase
        do {
            _ = try await database.save(record)
            remember(Written(recordName: delivery.recordName, zoneOwnerName: zoneID.ownerName, isOwn: isOwn, createdAt: delivery.createdAt))
            return .sent
        } catch let error as CKError {
            switch error.code {
            case .serverRecordChanged:
                // An earlier try got through after all.
                return .sent
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
                 .zoneBusy, .serverResponseLost, .operationCancelled:
                return .retry(after: error.retryAfterSeconds ?? Self.backoff(delivery.attempts), note: nil)
            case .zoneNotFound, .userDeletedZone:
                if isOwn {
                    let phone = target.name
                    return .retry(after: 60, note: String(
                        localized: "\(phone)'s inbox is missing. Open MyBaby once on it to set it up again.",
                        comment: "Nursery monitor; a phone's name, like Sam's iPhone"
                    ))
                }
                inboxes.forgetJoined(owner: target.owner)
                return .retry(after: 5, note: nil)
            case .unknownItem, .permissionFailure, .participantMayNeedVerification:
                // The share was stopped or changed: join it again.
                inboxes.forgetJoined(owner: target.owner)
                return .retry(after: 30, note: Self.notLetInNote(target.name))
            case .notAuthenticated:
                return .failed(String(localized: "Sign in to iCloud on this device so it can reach the parents' phones."))
            case .quotaExceeded:
                let phone = target.name
                return .failed(String(
                    localized: "The iCloud storage for \(phone) is full, so the alert couldn't be saved there.",
                    comment: "Nursery monitor; a phone's name, like Sam's iPhone"
                ))
            default:
                return .retry(after: Self.backoff(delivery.attempts), note: nil)
            }
        } catch {
            return .retry(after: Self.backoff(delivery.attempts), note: nil)
        }
    }

    /// "Sam's iPhone hasn't let this monitor in yet…"
    private static func notLetInNote(_ phone: String) -> String {
        String(
            localized: "\(phone) hasn't let this monitor in yet. Open MyBaby once on it, with iCloud on.",
            comment: "Nursery monitor; a phone's name, like Sam's iPhone"
        )
    }

    /// 2, 4, 8, 16, 32, then 60 seconds.
    private static func backoff(_ attempts: Int) -> TimeInterval {
        min(60, 2 * pow(2, Double(min(attempts, 6))))
    }

    // MARK: Trying again

    private func enqueue(_ delivery: Delivery) {
        queue.append(delivery)
        updateWaitingCount()
        scheduleRetry()
    }

    private func dropQueued(for owner: String) {
        queue.removeAll { $0.target.owner == owner }
        updateWaitingCount()
    }

    private func updateWaitingCount() {
        if waitingCount != queue.count { waitingCount = queue.count }
    }

    private func scheduleRetry() {
        guard retryTask == nil, let next = queue.map(\.dueAt).min() else { return }
        retryTask = Task {
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            retryTask = nil
            await retryDue()
        }
    }

    /// Sends what's due again. Gives up on alerts older than 10 minutes.
    private func retryDue() async {
        let now = Date.now
        let due = queue.filter { $0.dueAt <= now }
        queue.removeAll { $0.dueAt <= now }
        var later: [Delivery] = []
        for var delivery in due where now.timeIntervalSince(delivery.createdAt) < Self.maxAge {
            delivery.attempts += 1
            switch await deliver(delivery) {
            case .sent:
                later.removeAll { $0.target.owner == delivery.target.owner }
            case .retry(let after, _):
                delivery.dueAt = Date.now.addingTimeInterval(after)
                later.append(delivery)
            case .failed:
                break
            }
        }
        queue += later
        updateWaitingCount()
        scheduleRetry()
    }

    // MARK: Cleaning up

    private func remember(_ written: Written) {
        var all = loadWritten()
        all.append(written)
        saveWritten(all)
    }

    private func loadWritten() -> [Written] {
        guard let data = UserDefaults.standard.data(forKey: Self.writtenKey) else { return [] }
        return (try? JSONDecoder().decode([Written].self, from: data)) ?? []
    }

    private func saveWritten(_ written: [Written]) {
        if let data = try? JSONEncoder().encode(written) {
            UserDefaults.standard.set(data, forKey: Self.writtenKey)
        }
    }

    /// Deletes the alerts this monitor wrote more than an hour ago. Called while the monitor runs.
    func cleanUp() async {
        let written = loadWritten()
        let cutoff = Date.now.addingTimeInterval(-AlertInboxes.alertLifetime)
        let expired = written.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty, PersistenceController.isSyncEnabled else { return }

        let container = AlertInboxes.container
        var done: Set<String> = []
        for (zoneOwner, items) in Dictionary(grouping: expired, by: \.zoneOwnerName) {
            guard let first = items.first else { continue }
            let database = first.isOwn ? container.privateCloudDatabase : container.sharedCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: AlertInboxes.zoneName, ownerName: zoneOwner)
            let ids = items.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
            do {
                let (_, results) = try await database.modifyRecords(
                    saving: [], deleting: ids, savePolicy: .ifServerRecordUnchanged, atomically: false
                )
                for (id, result) in results {
                    switch result {
                    case .success:
                        done.insert(id.recordName)
                    case .failure(let error):
                        if (error as? CKError)?.code == .unknownItem { done.insert(id.recordName) }
                    }
                }
            } catch let error as CKError
                where [CKError.Code.zoneNotFound, .userDeletedZone, .unknownItem, .permissionFailure].contains(error.code) {
                // Nothing left there that this monitor can delete.
                done.formUnion(items.map(\.recordName))
            } catch {
                // Offline: next time.
            }
        }
        // Whatever couldn't be deleted in a day is left to the inbox's owner, which deletes old ones too.
        let dayAgo = Date.now.addingTimeInterval(-24 * 3600)
        saveWritten(loadWritten().filter { !done.contains($0.recordName) && $0.createdAt > dayAgo })
    }
}

/// A tap on a cry alert (from this phone, or a nursery monitor's push) opens Today. Set by the app
/// delegate, read by `RootView`, which owns the selected tab.
@MainActor
final class CryAlertTaps: ObservableObject {
    static let shared = CryAlertTaps()

    @Published var openToday = false

    private init() {}
}
