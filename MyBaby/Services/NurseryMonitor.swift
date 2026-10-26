import CoreData
import Observation
import UIKit

/// Monitor mode: an old iPhone or iPad left near the baby listens for crying and sends alerts to the
/// parents' phones through their private iCloud inboxes (`RemoteCryAlerts`), with no server.
///
/// While it's on, the device shows `MonitorView` full screen, and checks in every 5 minutes with a
/// `MonitorDevice` row, so the parents' phones can show it's still listening.
@MainActor
@Observable
final class NurseryMonitor {
    static let shared = NurseryMonitor()

    /// Whether this device is the monitor right now.
    private(set) var isActive = false
    /// Listening stopped by itself (an interruption, or the microphone went away), with what to tell the parent.
    private(set) var problem: String?
    /// The baby it listens for, for "Listening for Noah".
    private(set) var babyName = String(localized: "Baby", comment: "Stands in for the baby's name when there's none")

    /// Why a device can't be the monitor.
    enum Availability: Equatable {
        case available
        case noBaby
        case syncOff
        case viewOnly

        var explanation: String? {
            switch self {
            case .available:
                return nil
            case .noBaby:
                return String(localized: "Add your baby first, so the monitor knows who it's listening for.")
            case .syncOff:
                return String(localized: "Turn on iCloud sync in Settings first. The monitor reaches your phones through your family's own iCloud.")
            case .viewOnly:
                return String(localized: "This device can only view the log, so it can't be the monitor. Sign in with a parent's Apple ID, or ask the parent who shared the log to let you make changes.")
            }
        }
    }

    static func availability(for baby: Baby?) -> Availability {
        guard let baby else { return .noBaby }
        guard PersistenceController.isSyncEnabled else { return .syncOff }
        guard PersistenceController.shared.canEdit(baby) else { return .viewOnly }
        return .available
    }

    /// While monitoring, this device doesn't publish an inbox of its own, so alerts aren't sent to it.
    static var isThisDeviceAMonitor: Bool { shared.isActive }

    /// The `uuid` of this device's `MonitorDevice` row, so the parents' rows don't include it here.
    static var ownRowID: String? { UserDefaults.standard.string(forKey: rowIDKey) }
    private static let rowIDKey = "nurseryMonitor.rowID"

    @ObservationIgnored private var babyID: UUID?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var isStopping = false

    private init() {}

    // MARK: Start & stop

    func start(baby: Baby) async {
        guard !isActive, Self.availability(for: baby) == .available else { return }
        if baby.uuid == nil {
            baby.uuid = UUID()
            baby.managedObjectContext?.saveIfChanged()
        }
        babyID = baby.uuid
        babyName = baby.displayName
        problem = nil

        // A phone that was listening for its own alerts starts over as the monitor.
        let cryMonitor = CryMonitor.shared
        if cryMonitor.isListening { cryMonitor.stop() }
        await cryMonitor.start(mode: .monitorDevice)
        guard cryMonitor.isListening else { return }

        isActive = true
        checkIn()
        startHeartbeat()
        // Takes this device's own inbox rows away, and joins the family's inboxes.
        Task { await AlertInboxes.shared.refresh(force: true) }
    }

    /// Stops listening and closes the monitor screen. The parents' phones show it as off.
    func stop() {
        isStopping = true
        defer { isStopping = false }
        CryMonitor.shared.stop()
        finish()
        if isActive { isActive = false }
        problem = nil
        // This device can get alerts again.
        AlertInboxes.shared.refreshSoon(force: true)
    }

    /// After listening stopped by itself.
    func startAgain() async {
        guard isActive, !CryMonitor.shared.isListening else { return }
        await CryMonitor.shared.start(mode: .monitorDevice)
        guard CryMonitor.shared.isListening else {
            problem = CryMonitor.shared.errorMessage ?? String(localized: "Listening couldn't start again.")
            return
        }
        problem = nil
        checkIn()
        startHeartbeat()
    }

    /// Called by `CryMonitor` whenever monitor-mode listening stops: from Stop monitor, or by itself.
    /// The screen stays open after an unexpected stop, saying so, with a way to start again.
    func cryMonitorDidStop() {
        guard isActive, !isStopping else { return }
        finish()
        problem = CryMonitor.shared.errorMessage ?? String(localized: "Listening stopped. Tap Start again.", comment: "“Start again” is a button")
    }

    /// Sends a test alert to every parent's phone.
    func sendTest() async -> String {
        await RemoteCryAlerts.shared.send(.test, crySeconds: 0, to: .everyone)
    }

    private func finish() {
        heartbeat?.cancel()
        heartbeat = nil
        checkIn(listening: false)
    }

    // MARK: Checking in

    /// Every 5 minutes: check in, keep the inboxes up to date, and delete alerts older than an hour.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MonitorDevice.checkInInterval))
                guard !Task.isCancelled else { return }
                checkIn(listening: CryMonitor.shared.isListening)
                await AlertInboxes.shared.refresh()
                await RemoteCryAlerts.shared.cleanUp()
            }
        }
    }

    /// Updates this device's `MonitorDevice` row, which syncs to the family with the log.
    private func checkIn(listening: Bool = true) {
        guard CloudStatus.shared.reloadingMessage == nil, let babyID else { return }
        let context = PersistenceController.shared.viewContext
        let request = Baby.fetchAll()
        request.predicate = NSPredicate(format: "uuid == %@", babyID as CVarArg)
        guard let baby = try? context.fetch(request).first else { return }

        let device = ownDevice(for: baby, in: context)
        let who = baby.displayName
        let model = UIDevice.current.model
        // Shown on the parents' phones, in this device's language.
        let name = String(localized: "\(who)'s \(model)", comment: "The monitor's name; the baby's name, then iPhone or iPad")
        if device.deviceName != name { device.deviceName = name }
        if device.isListening != listening { device.isListening = listening }
        let noise = WhiteNoise.shared.color.rawValue
        if device.noiseRaw != noise { device.noiseRaw = noise }
        device.lastSeen = .now
        context.saveIfChanged()
    }

    /// This device's row for `baby`, made the first time. Read fresh each time, since the stores are
    /// reopened when iCloud is switched on or off.
    private func ownDevice(for baby: Baby, in context: NSManagedObjectContext) -> MonitorDevice {
        if let id = Self.ownRowID.flatMap(UUID.init(uuidString:)) {
            let request = MonitorDevice.fetchAll()
            request.predicate = NSPredicate(format: "uuid == %@", id as CVarArg)
            if let existing = try? context.fetch(request).first {
                if existing.baby == baby { return existing }
                // Monitoring another baby now: the old row says it's off.
                existing.isListening = false
            }
        }
        let device = MonitorDevice(context: context)
        device.uuid = UUID()
        device.lastSeen = .now
        // In the baby's store, so it syncs to whoever the baby is shared with.
        if let store = baby.objectID.persistentStore {
            context.assign(device, to: store)
        }
        device.baby = baby
        UserDefaults.standard.set(device.uuid?.uuidString, forKey: Self.rowIDKey)
        return device
    }
}
