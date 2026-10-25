import SwiftUI

/// Colors for the watch. It's always dark; at night the buttons turn a dim red, which is gentler on eyes
/// adjusted to a dark nursery than bright teal and blue.
enum WatchTheme {
    static let night = Color(red: 0.62, green: 0.13, blue: 0.11)

    /// 9 PM to 7 AM, or while a parent is on night duty.
    static func isNight(at date: Date, snapshot: WidgetSnapshot?) -> Bool {
        if snapshot?.shift(at: date) != nil { return true }
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 21 || hour < 7
    }
}

private struct NightModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `ContentView` at night, so buttons use the dim red.
    var isNightMode: Bool {
        get { self[NightModeKey.self] }
        set { self[NightModeKey.self] = newValue }
    }
}

/// An emoji over a short title, filling the button: the label of every big button.
struct BigButtonLabel: View {
    let emoji: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(emoji)
                .font(.title3)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

/// A big, easy-to-hit button. `label` is what VoiceOver reads, since the emoji alone says little.
struct BigButton: View {
    @Environment(\.isNightMode) var isNightMode

    let emoji: String
    let title: String
    var tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BigButtonLabel(emoji: emoji, title: title)
        }
        .buttonStyle(.bordered)
        .tint(isNightMode ? WatchTheme.night : tint)
        .accessibilityLabel(label)
    }
}

/// A big button that opens another screen, such as the bottle amounts.
struct BigLink<Destination: View>: View {
    @Environment(\.isNightMode) var isNightMode

    let emoji: String
    let title: String
    var tint: Color
    let label: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            BigButtonLabel(emoji: emoji, title: title)
        }
        .buttonStyle(.bordered)
        .tint(isNightMode ? WatchTheme.night : tint)
        .accessibilityLabel(label)
    }
}

/// "Wet diaper logged · Will sync to iPhone", with Undo. Shown for about 5 seconds after a tap.
struct ConfirmationBanner: View {
    @Environment(WatchStore.self) var store

    let confirmation: Confirmation

    var body: some View {
        VStack(spacing: 4) {
            Label(confirmation.message, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            if let status = confirmation.status.text {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if confirmation.canUndo {
                Button("Undo") {
                    store.undo()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Undo: \(confirmation.message)")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }
}

/// "2 taps will sync to iPhone" and "Last synced 3 min ago", when either applies.
struct SyncStatusView: View {
    @Environment(WatchStore.self) var store

    let now: Date

    var body: some View {
        VStack(spacing: 2) {
            if store.pendingCount > 0 {
                Label(
                    store.pendingCount == 1 ? "1 tap will sync to iPhone" : "\(store.pendingCount) taps will sync to iPhone",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            if let sentAt = store.context?.sentAt, store.isStale(at: now) {
                Text("Last synced ") + Text(sentAt, style: .relative) + Text(" ago")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
