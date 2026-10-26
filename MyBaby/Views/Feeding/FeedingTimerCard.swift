import CoreData
import SwiftUI

/// The breastfeeding timer on Today while it's going: the side and its time, the total, and
/// Switch, Pause / Resume and Done. Tapping the top opens the full timer.
struct FeedingTimerCard: View {
    @Environment(\.managedObjectContext) private var context
    /// The baby shown on Today, to point out when the timer is for the other twin.
    let babyName: String
    let onOpen: () -> Void
    let onSaved: (Activity) -> Void

    private let timer = FeedingTimer.shared

    init(babyName: String, onOpen: @escaping () -> Void, onSaved: @escaping (Activity) -> Void) {
        self.babyName = babyName
        self.onOpen = onOpen
        self.onSaved = onSaved
    }

    var body: some View {
        if let state = timer.state {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpen) {
                    // Redrawn each minute so VoiceOver reads the minutes so far, not a ticking clock.
                    TimelineView(.everyMinute) { timeline in
                        HStack(spacing: Spacing.m) {
                            EmojiBadge(emoji: "🤱", tint: ActivityKind.feeding.color, size: 44)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(title(state))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                FeedingClockText(state: state, side: state.side)
                                    .font(.title2.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                Text("Total")
                                FeedingClockText(state: state)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spokenStatus(state, now: timeline.date))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the breastfeeding timer")

                HStack(spacing: Spacing.s) {
                    Button {
                        timer.switchSide()
                    } label: {
                        Label("Switch", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel(state.side.other == .left ? "Switch to the left side" : "Switch to the right side")
                    Button {
                        timer.togglePause()
                    } label: {
                        Label(state.isRunning ? "Pause" : "Resume", systemImage: state.isRunning ? "pause.fill" : "play.fill")
                    }
                    Spacer(minLength: 0)
                    Button("Done") {
                        if let feed = timer.finish(context: context) {
                            onSaved(feed)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Done, save this feed")
                }
                .buttonStyle(.bordered)
                .tint(ActivityKind.feeding.color)
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 4)
        }
    }

    /// "Breastfeeding, left side, 12 minutes. Total 20 minutes."
    private func spokenStatus(_ state: FeedingTimerState, now: Date) -> String {
        let side = Format.spokenDuration(state.seconds(on: state.side, at: now))
        let total = Format.spokenDuration(state.totalSeconds(at: now))
        return String(
            localized: "\(Format.spoken(title(state))), \(side). Total \(total).",
            comment: "VoiceOver: e.g. “Breastfeeding, left side, 12 minutes. Total 20 minutes.”"
        )
    }

    private func title(_ state: FeedingTimerState) -> String {
        let side = state.side == .left ? String(localized: "Left side") : String(localized: "Right side")
        let what = state.isRunning ? side : String(localized: "Paused · \(side)", comment: "e.g. “Paused · Left side”")
        return state.babyName == babyName
            ? String(localized: "Breastfeeding · \(what)", comment: "e.g. “Breastfeeding · Left side”")
            : "\(state.babyName) · \(what)"
    }
}
