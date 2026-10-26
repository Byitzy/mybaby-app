import Foundation

// Everything in Shared/ is compiled into both the app and the MyBabyWidgets extension, so it only uses
// Foundation, SwiftUI, ActivityKit and AppIntents, never the app's Core Data model. App-only code inside
// these files is wrapped in `#if !WIDGET_EXTENSION`. The Apple Watch targets (MyBabyWatch and its
// complications) build it too, except ButtonIntents.swift and LiveActivityAttributes.swift, and
// BabyEntity.swift in the watch app (the complications use it), which the project excludes for them;
// anything else added here must build on watchOS.

/// The App Group the app shares its database and settings through, with widgets and the Apple Watch app.
enum AppGroup {
    /// From Info.plist: `group.<app bundle id>`. The app derives it from its bundle identifier, and the
    /// widget extension from `MYBABY_APP_BUNDLE_IDENTIFIER`, so both open the same group.
    static let identifier: String =
        Bundle.main.object(forInfoDictionaryKey: "MyBabyAppGroup") as? String ?? "group.com.mybaby.ios"

    /// The group's shared folder, or `nil` when the App Group isn't set up in Signing & Capabilities.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

extension UserDefaults {
    /// Settings shared with widgets and the Apple Watch app. Falls back to the app's own settings
    /// if the App Group can't be opened.
    static let shared = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
}

/// Keys in `UserDefaults.shared` that the app and its extensions both use.
/// (App-only settings keys are in `SettingsKey`, in MyBaby/Utilities/Settings.swift.)
enum SharedKey {
    /// JSON-encoded `FeedingTimerState` while a breastfeeding timer is going.
    static let feedingTimer = "feedingTimer"
    /// `BreastSide` the last timed breastfeeding ended on, for the "start with" hint.
    static let lastBreastSide = "lastBreastSide"
    /// The `uuid` of the sleep a Live Activity was last started for, so one the parent dismissed
    /// isn't started again.
    static let sleepLiveActivityID = "sleepLiveActivityID"
}

/// The `kind` strings of the widgets, for reloading one of them.
enum WidgetKind {
    static let status = "MyBabyStatus"
    static let lockScreen = "MyBabyLockScreen"
}
