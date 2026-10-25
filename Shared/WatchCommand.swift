import Foundation

/// Something tapped on the Apple Watch, for the iPhone to log.
///
/// The watch never opens the database: it sends one of these to the iPhone over WatchConnectivity, and
/// the iPhone app runs it (`WatchBridge`, in the app) through the same code as Siri and the widgets, then
/// answers with a fresh `WatchContext`. When the iPhone can't be reached, the watch queues it with
/// `transferUserInfo`, which the system delivers when the phone is back in range, even hours later. So
/// each command carries the moment it was tapped (`date`), and the entry is logged at that time.
///
/// Each command has its own `id`, so the iPhone logs it only once, even if it arrives twice (a message
/// whose reply timed out, then the queued copy), and so a later `.undo(id)` can find what it logged.
///
/// Built into the app, the widgets and both watch targets, so it only uses Foundation.
struct WatchCommand: Codable, Equatable, Identifiable {
    /// A diaper, as the watch's buttons offer it.
    enum Diaper: String, Codable, CaseIterable {
        case wet, dirty, both
    }

    /// What was in the bottle.
    enum Bottle: String, Codable, CaseIterable {
        case breastMilk, formula
    }

    enum Action: Codable, Equatable {
        /// Logs nothing; the reply is the latest context. Sent when the watch app opens.
        case sync
        case logDiaper(Diaper)
        case startSleep
        case endSleep
        case logBottle(type: Bottle, ml: Double)
        /// One of the medicines given before (`WatchContext.medicines`), with the dose logged last time.
        case logMedicine(name: String)
        /// Starts the breastfeeding timer on `side`, or switches or resumes the one going on.
        case timerStart(BreastSide)
        case timerSwitch
        /// Saves the breastfeeding with the minutes on each side.
        case timerStop
        /// Takes back the command with this `id`: deletes the entry it added, or reopens the sleep it ended.
        case undo(UUID)
        /// "I'm up" on a night-shift wake-up that iOS forwarded to the watch: the iPhone stops the
        /// rest of that wake-up's buzzes. `notificationID` is the buzz that was answered.
        case acknowledgeWakeUp(notificationID: String)
    }

    var id = UUID()
    var action: Action
    /// When it was tapped on the watch. The entry is logged at this time, not when the iPhone gets it.
    var date = Date.now
    /// `Baby.uuid` of the baby shown on the watch, so it's logged for that baby even if the iPhone has
    /// switched to the other twin since. `nil` logs for the baby shown in the app.
    var babyID: String?

    /// Keys in the WatchConnectivity message and user info dictionaries.
    static let key = "command"
    static let idKey = "id"
}

extension WatchCommand {
    /// The command as a WatchConnectivity message or user info: the JSON, plus the `id` on its own so a
    /// queued transfer can be found (and cancelled) without decoding it.
    var userInfo: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data, Self.idKey: id.uuidString]
    }

    init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.key] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: data)
        else { return nil }
        self = command
    }

    /// The `id` of the command in a message or user info, without decoding it.
    static func id(in userInfo: [String: Any]) -> UUID? {
        (userInfo[idKey] as? String).flatMap(UUID.init(uuidString:))
    }
}

extension WatchCommand.Action {
    /// Whether the watch offers Undo after it. The breastfeeding timer has its own controls instead.
    var isUndoable: Bool {
        switch self {
        case .logDiaper, .logBottle, .logMedicine, .startSleep, .endSleep: return true
        case .sync, .timerStart, .timerSwitch, .timerStop, .undo, .acknowledgeWakeUp: return false
        }
    }
}

/// The night-shift wake-up notification's category and its "I'm up" button. The iPhone schedules
/// it (`NotificationManager`); iOS may forward it to the watch, where the watch app registers the same
/// category so "I'm up" works on the wrist too (`WatchNotifications`, in the watch app).
enum WakeUpNotification {
    static let category = "night-shift-wake"
    static let imUpAction = "im-up"
}
