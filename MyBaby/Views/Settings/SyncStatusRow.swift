import SwiftUI

/// Under "Sync with iCloud" in Settings while sync is on: syncing, up to date (and when it last
/// synced), waiting for a connection, or what's wrong, with Try again for account problems.
/// VoiceOver reads it as one element, with Try again as its action.
struct SyncStatusRow: View {
    @ObservedObject private var status = SyncStatus.shared

    var body: some View {
        // Moves on every minute, so "synced 2 minutes ago" stays right.
        TimelineView(.everyMinute) { timeline in
            let state = status.state
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label {
                    Text(text(for: state, now: timeline.date, spoken: false))
                        .foregroundStyle(isProblem(state) ? HierarchicalShapeStyle.primary : .secondary)
                } icon: {
                    icon(for: state)
                }
                if canRetry(state) {
                    Button("Try again") { status.retry() }
                        .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("iCloud sync: \(text(for: state, now: timeline.date, spoken: true))")
            .accessibilityActions {
                if canRetry(state) {
                    Button("Try again") { status.retry() }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for state: SyncStatus.State) -> some View {
        switch state {
        case .syncing:
            ProgressView()
        case .upToDate:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(Palette.ok)
        case .waitingForConnection:
            Image(systemName: "icloud.slash")
                .foregroundStyle(Palette.inactive)
        case .problem:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
        }
    }

    /// `spoken` uses a comma where the screen shows a dot, so VoiceOver doesn't read "dot".
    private func text(for state: SyncStatus.State, now: Date, spoken: Bool) -> String {
        switch state {
        case .syncing:
            return String(localized: "Syncing…")
        case .upToDate(let lastSynced):
            guard let lastSynced else { return String(localized: "Up to date") }
            let synced = Self.relative(lastSynced, now: now)
            return spoken
                ? String(localized: "Up to date, synced \(synced)", comment: "Read by VoiceOver. \"2 minutes ago\" or \"just now\"")
                : String(localized: "Up to date · synced \(synced)", comment: "\"2 minutes ago\" or \"just now\"")
        case .waitingForConnection:
            return CloudErrors.waitingForConnection
        case .problem(let message, _):
            return message
        }
    }

    private func isProblem(_ state: SyncStatus.State) -> Bool {
        if case .problem = state { return true }
        return false
    }

    private func canRetry(_ state: SyncStatus.State) -> Bool {
        if case .problem(_, canRetry: true) = state { return true }
        return false
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// "just now", "2 minutes ago", "3 hours ago".
    private static func relative(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "just now", comment: "After \"synced\"") }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
