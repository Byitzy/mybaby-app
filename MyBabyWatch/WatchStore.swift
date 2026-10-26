import Foundation
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch app's state: the last `WatchContext` from the iPhone, whether the iPhone can be reached
/// right now, and the taps still on their way to it.
///
/// The watch keeps no log of its own. A tap becomes a `WatchCommand` for the iPhone (see `log(_:message:)`):
/// - **iPhone reachable:** it goes as a message, which wakes MyBaby on the iPhone if needed. The reply is
///   the fresh context, and the confirmation changes to "Saved on iPhone".
/// - **Not reachable** (or the message fails): it's queued with `transferUserInfo`. The system keeps the
///   queue even if this app closes, and delivers it in order when the iPhone is back in range. The
///   confirmation says "Will sync to iPhone", and the home screen counts the taps still waiting.
/// Either way the screen shows the tap's effect at once (`WatchContext.apply(_:)`), and the next context
/// from the iPhone replaces it with what was actually logged.
@MainActor
@Observable
final class WatchStore {
    static let shared = WatchStore()

    /// What's shown. `nil` until the iPhone has sent anything.
    private(set) var context: WatchContext?
    /// Whether the iPhone can be messaged right now.
    private(set) var isReachable = false
    /// Taps queued for the iPhone that haven't been delivered yet.
    private(set) var pendingCount = 0
    /// The short confirmation shown after a tap.
    private(set) var confirmation: Confirmation?
    /// Something to read and dismiss, shown as an alert: why a medicine on the baby's allergy list
    /// isn't logged from the watch.
    private(set) var notice: String?

    @ObservationIgnored private var delegate: SessionDelegate?
    /// Taps made before the session finished activating (right after launch), sent once it has.
    @ObservationIgnored private var waitingForActivation: [WatchCommand] = []
    /// What was shown before the tap the confirmation is for, so Undo can put it back.
    @ObservationIgnored private var contextBeforeTap: WatchContext?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private init() {
        context = WatchContext.load()
    }

    /// Starts talking to the iPhone. Called once at launch.
    func start() {
        guard delegate == nil, WCSession.isSupported() else { return }
        let delegate = SessionDelegate()
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    private var session: WCSession { WCSession.default }

    private var isActivated: Bool { session.activationState == .activated }

    /// True when what's shown may be out of date: the iPhone can't be reached, or nothing has come from
    /// it for a while. The home screen then says when it last synced.
    func isStale(at now: Date) -> Bool {
        guard let sentAt = context?.sentAt else { return false }
        return !isReachable || now.timeIntervalSince(sentAt) > 15 * 60
    }

    // MARK: Taps

    /// Sends `action` to the iPhone, shows its effect right away, buzzes, and shows `message` (with
    /// Undo for about 5 seconds when the action can be undone).
    func log(_ action: WatchCommand.Action, message: String) {
        let command = WatchCommand(action: action, babyID: context?.snapshot?.babyID)
        let before = context
        if var updated = context {
            updated.apply(command)
            setContext(updated)
        }
        WKInterfaceDevice.current().play(.success)
        contextBeforeTap = action.isUndoable ? before : nil
        show(Confirmation(
            message: message,
            status: isActivated && session.isReachable ? .sending : .queued,
            commandID: command.id,
            canUndo: action.isUndoable
        ))
        deliver(command)
    }

    /// Sends `action` to the iPhone without a buzz or a confirmation, e.g. "I'm up" on a wake-up
    /// forwarded from the iPhone. Same delivery as a tap: a message, or queued until the iPhone is in reach.
    func send(_ action: WatchCommand.Action) {
        deliver(WatchCommand(action: action, babyID: context?.snapshot?.babyID))
    }

    /// Takes back the tap the confirmation is for: removes it from the queue if it hasn't left the watch
    /// yet, and otherwise asks the iPhone to undo it.
    func undo() {
        guard let shown = confirmation, shown.canUndo else { return }
        let id = shown.commandID
        var status = Confirmation.Status.local
        if let index = waitingForActivation.firstIndex(where: { $0.id == id }) {
            waitingForActivation.remove(at: index)
            updatePendingCount()
        } else if isActivated,
                  let transfer = session.outstandingUserInfoTransfers.first(where: {
                      WatchCommand.id(in: $0.userInfo) == id && !$0.isTransferring
                  }) {
            transfer.cancel()
            updatePendingCount()
        } else {
            let undoCommand = WatchCommand(action: .undo(id), babyID: context?.snapshot?.babyID)
            status = isActivated && session.isReachable ? .sending : .queued
            deliver(undoCommand)
            show(Confirmation(message: String(localized: "Undone", comment: "Watch: a tap was taken back"), status: status, commandID: undoCommand.id, canUndo: false))
        }
        if let before = contextBeforeTap {
            setContext(before)
        }
        contextBeforeTap = nil
        WKInterfaceDevice.current().play(.click)
        if status == .local {
            show(Confirmation(message: String(localized: "Undone", comment: "Watch: a tap was taken back"), status: .local, commandID: id, canUndo: false))
        }
    }

    func dismissConfirmation() {
        dismissTask?.cancel()
        withAnimation { confirmation = nil }
        contextBeforeTap = nil
    }

    /// Shows `message` as an alert, with a gentle buzz, instead of logging.
    func showNotice(_ message: String) {
        WKInterfaceDevice.current().play(.notification)
        notice = message
    }

    func dismissNotice() {
        notice = nil
    }

    /// Asks the iPhone for the latest context, when it can be reached. Sent when the app opens.
    func requestSync() {
        guard isActivated, session.isReachable else { return }
        Self.sendMessage(WatchCommand(action: .sync), queueOnFailure: false)
    }

    private func show(_ new: Confirmation) {
        withAnimation { confirmation = new }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissConfirmation()
        }
    }

    // MARK: Delivery

    private func deliver(_ command: WatchCommand) {
        guard isActivated else {
            waitingForActivation.append(command)
            updatePendingCount()
            return
        }
        if session.isReachable {
            Self.sendMessage(command, queueOnFailure: true)
        } else {
            queue(command)
        }
    }

    /// Hands `command` to WatchConnectivity, which delivers it when the iPhone is back in reach, even if
    /// this app has closed by then. The iPhone logs it at the time it was tapped.
    fileprivate func queue(_ command: WatchCommand) {
        guard isActivated else {
            waitingForActivation.append(command)
            updatePendingCount()
            return
        }
        session.transferUserInfo(command.userInfo)
        updatePendingCount()
        if confirmation?.commandID == command.id {
            confirmation?.status = .queued
        }
    }

    /// Sends a message, outside the main actor because WatchConnectivity calls back on its own queue.
    /// If it fails (the iPhone went out of reach, or didn't answer), it's queued instead. The iPhone
    /// ignores a command it has already logged, so one that arrives twice is logged once.
    nonisolated private static func sendMessage(_ command: WatchCommand, queueOnFailure: Bool) {
        WCSession.default.sendMessage(
            command.userInfo,
            replyHandler: { reply in
                let context = WatchContext(message: reply)
                Task { @MainActor in
                    WatchStore.shared.delivered(command.id, reply: context)
                }
            },
            errorHandler: { _ in
                guard queueOnFailure else { return }
                Task { @MainActor in
                    WatchStore.shared.queue(command)
                }
            }
        )
    }

    private func updatePendingCount(excluding finished: WCSessionUserInfoTransfer? = nil) {
        let queued = isActivated ? session.outstandingUserInfoTransfers.filter { $0 !== finished }.count : 0
        pendingCount = queued + waitingForActivation.count
    }

    // MARK: From the iPhone

    fileprivate func activated(reachable: Bool, context incoming: WatchContext?) {
        isReachable = reachable
        if let incoming {
            receive(incoming)
        }
        let waiting = waitingForActivation
        waitingForActivation = []
        for command in waiting {
            deliver(command)
        }
        updatePendingCount()
        requestSync()
    }

    fileprivate func reachabilityChanged(_ reachable: Bool) {
        isReachable = reachable
        if reachable {
            requestSync()
        }
    }

    /// The iPhone answered a message.
    fileprivate func delivered(_ id: UUID, reply: WatchContext?) {
        if let reply {
            receive(reply)
        }
        if confirmation?.commandID == id {
            confirmation?.status = .saved
        }
    }

    /// A queued tap reached the iPhone (or was cancelled by Undo).
    fileprivate func transferFinished(_ transfer: WCSessionUserInfoTransfer, delivered: Bool) {
        updatePendingCount(excluding: transfer)
        if delivered, let id = WatchCommand.id(in: transfer.userInfo), confirmation?.commandID == id {
            confirmation?.status = .saved
        }
    }

    /// A context from the iPhone. One older than what's shown is ignored, since replies and application
    /// contexts can arrive out of order.
    fileprivate func receive(_ incoming: WatchContext) {
        if let current = context, incoming.sentAt < current.sentAt { return }
        // No baby on the iPhone any more (e.g. all MyBaby data was deleted there): there's nothing left
        // to undo, and Undo mustn't bring back what was shown before.
        if incoming.snapshot == nil, context?.snapshot != nil {
            dismissConfirmation()
        }
        setContext(incoming)
        if let refusal = incoming.refusal {
            showOnce(refusal)
        }
    }

    /// A tap the iPhone didn't log: says why, once, in place of its "logged" confirmation.
    private func showOnce(_ refusal: WatchContext.Refusal) {
        var shown = (UserDefaults.standard.array(forKey: Self.shownRefusalsKey) as? [String]) ?? []
        let id = refusal.commandID.uuidString
        guard !shown.contains(id) else { return }
        shown.append(id)
        UserDefaults.standard.set(Array(shown.suffix(20)), forKey: Self.shownRefusalsKey)
        if confirmation?.commandID == refusal.commandID {
            dismissConfirmation()
        }
        showNotice(refusal.message)
    }

    /// The `WatchCommand.id`s of the refusals already shown, kept on the watch so each shows once.
    private static let shownRefusalsKey = "shownWatchRefusals"

    /// Shows `new`, saves it for next launch and the complications, and redraws them if it changed.
    private func setContext(_ new: WatchContext) {
        let changed = context.map { !new.hasSameContent(as: $0) } ?? true
        let babiesChanged = Self.babyList(context) != Self.babyList(new)
        context = new
        WatchContext.save(new)
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
        if babiesChanged {
            // The face editor's presets list each baby by name (`recommendations()`).
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    /// The babies' ids and names, which the complications' presets are made from.
    private static func babyList(_ context: WatchContext?) -> [String] {
        (context?.snapshot?.babies ?? []).map { "\($0.id) \($0.name)" }
    }
}

/// The confirmation shown at the bottom after a tap.
struct Confirmation: Equatable {
    enum Status {
        /// The message is on its way to the iPhone.
        case sending
        /// The iPhone has it.
        case saved
        /// Queued until the iPhone is back in reach.
        case queued
        /// Nothing to report, e.g. an Undo that never had to leave the watch.
        case local

        var text: String? {
            switch self {
            case .sending: return String(localized: "Sending to iPhone…")
            case .saved: return String(localized: "Saved on iPhone")
            case .queued: return String(localized: "Will sync to iPhone")
            case .local: return nil
            }
        }
    }

    var message: String
    var status: Status
    /// The command it's for, to follow its delivery and undo it.
    var commandID: UUID
    var canUndo: Bool
}

/// WatchConnectivity's callbacks, on its own background queue. Each hands over to the store on the
/// main actor. (A separate object, so the store itself needn't be an `NSObject`.)
private final class SessionDelegate: NSObject, WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        // The latest context the iPhone sent while this app wasn't running.
        let context = WatchContext(message: session.receivedApplicationContext)
        Task { @MainActor in
            WatchStore.shared.activated(reachable: reachable, context: context)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            WatchStore.shared.reachabilityChanged(reachable)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let context = WatchContext(message: applicationContext) else { return }
        Task { @MainActor in
            WatchStore.shared.receive(context)
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let delivered = error == nil
        Task { @MainActor in
            WatchStore.shared.transferFinished(userInfoTransfer, delivered: delivered)
        }
    }
}
