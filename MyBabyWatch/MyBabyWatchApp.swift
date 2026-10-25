import SwiftUI

/// MyBaby on Apple Watch: the baby's status at a glance and big buttons to log a diaper, sleep, bottle,
/// medicine or breastfeeding without reaching for the phone at night.
///
/// It keeps no database. Everything it shows comes from MyBaby on the paired iPhone, and every tap is sent
/// back to the iPhone to log, over Apple's WatchConnectivity only (see `WatchStore` and, in the app,
/// `WatchBridge`).
@main
struct MyBabyWatchApp: App {
    init() {
        WatchStore.shared.start()
        // Before launch finishes, so an "I'm up" that launched the app reaches it.
        WatchNotifications.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(WatchStore.shared)
        }
    }
}
