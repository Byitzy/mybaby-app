import Foundation
import UserNotifications

/// "I'm up" on the wrist for the night-shift wake-ups the iPhone schedules.
///
/// iOS forwards the iPhone's notifications to the watch while the iPhone is locked and the watch is worn.
/// The watch shows an action button only for a category the watch app has registered itself, so this
/// registers the iPhone's wake-up category with the same "I'm up" action (`WakeUpNotification`). When it's
/// tapped (or the alert is dismissed, which also counts as an answer on the iPhone), the watch tells the
/// iPhone with `WatchCommand.Action.acknowledgeWakeUp`, through the same path as a tap on a button
/// (a message, or queued until the iPhone is in reach), and the iPhone stops the rest of the buzzes.
///
/// Started once at launch (`MyBabyWatchApp.init`).
final class WatchNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotifications()

    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let imUp = UNNotificationAction(identifier: WakeUpNotification.imUpAction, title: "I'm up", options: [])
        let wakeUp = UNNotificationCategory(
            identifier: WakeUpNotification.category,
            actions: [imUp],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([wakeUp])
    }

    /// Shows a wake-up even while the watch app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// "I'm up", dismissing the alert, or opening it: any answer stops the remaining buzzes on the iPhone.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        guard request.content.categoryIdentifier == WakeUpNotification.category else {
            completionHandler()
            return
        }
        let identifier = request.identifier
        Task { @MainActor in
            WatchStore.shared.send(.acknowledgeWakeUp(notificationID: identifier))
            completionHandler()
        }
    }
}
