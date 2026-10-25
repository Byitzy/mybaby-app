import CloudKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct MyBabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        SyncStatus.shared.start()
        // Keeps the widgets' snapshot and the sleep Live Activity up to date. Also runs when iOS
        // launches the app in the background for a Siri, widget or Live Activity button.
        WidgetSnapshotWriter.shared.start()
        // Talks to the Apple Watch app. Also runs when a tap on the watch launches the app in the background.
        WatchBridge.shared.start()
        // "Keep appointments in my calendar", when it's on (off by default).
        CalendarSync.shared.start()
        // "How did it go?" an hour after each appointment.
        VisitFollowUp.shared.start()
        // Tells Siri the babies' names ("Log a diaper for Mavie in MyBaby"), now and when they change.
        SiriBabyNames.shared.start()
        // Feed and diaper reminders, moved whenever the log changes here or on the partner's phone.
        SmartReminders.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
        // Also how a nursery monitor's alerts arrive: as CloudKit pushes (see `AlertInboxes`).
        application.registerForRemoteNotifications()
        AlertInboxes.shared.start()
        // Crash and hang reports from iOS, kept on this iPhone until the parent attaches one to feedback.
        CrashReports.shared.start()
        return true
    }

    /// A scene delegate is the only place iOS hands over an accepted iCloud share invitation.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Show reminders even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The nursery monitor itself stays quiet: on the same Apple ID as a parent, it gets that
        // parent's pushes too.
        if notification.request.content.categoryIdentifier == NotificationManager.cryAlertCategory,
           await MainActor.run(body: { NurseryMonitor.shared.isActive }) {
            return []
        }
        return [.banner, .sound]
    }

    /// Handles "I'm up" (or dismissing a wake-up), including from the Lock Screen. A tap on a cry
    /// alert opens Today.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.content.categoryIdentifier == NotificationManager.cryAlertCategory,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { CryAlertTaps.shared.openToday = true }
        }
        await NotificationManager.handle(response)
        // "How did it go?" opens the visit's recap.
        await VisitFollowUp.handle(response)
    }
}

/// Receives the invitation when the other parent's share link is tapped.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // The app was launched by tapping the invitation.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await PersistenceController.shared.acceptShare(metadata)
        }
    }
}
