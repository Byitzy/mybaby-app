import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The breastfeeding timer on the Lock Screen and in the Dynamic Island, with Switch, Pause / Resume
/// and Done buttons. The clocks count up by themselves (`FeedingClockText`); the app only sends an
/// update when something changes.
struct FeedingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeedingActivityAttributes.self) { context in
            FeedingLockScreenView(babyName: context.attributes.babyName, timer: context.state.timer)
                .padding()
                .activityBackgroundTint(Color.pink.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SideClock(timer: context.state.timer, side: .left)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SideClock(timer: context.state.timer, side: .right)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("🤱 \(context.attributes.babyName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Breastfeeding \(context.attributes.babyName), total")
                        FeedingClockText(state: context.state.timer)
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FeedingButtons(timer: context.state.timer)
                }
            } compactLeading: {
                Text("🤱 \(context.state.timer.side.letter)")
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Breastfeeding, \(context.state.timer.side.title) side")
            } compactTrailing: {
                FeedingClockText(state: context.state.timer, side: context.state.timer.side)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 48)
                    .foregroundStyle(.pink)
            } minimal: {
                Text("🤱")
                    .accessibilityLabel("Breastfeeding")
            }
            .keylineTint(.pink)
        }
    }
}

/// The Lock Screen banner: each side's time with the one running highlighted, the total, and buttons.
private struct FeedingLockScreenView: View {
    let babyName: String
    let timer: FeedingTimerState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("🤱 \(babyName)")
                    .font(.headline)
                    .accessibilityLabel("Breastfeeding \(babyName)")
                Spacer()
                HStack(spacing: 4) {
                    Text(timer.isRunning ? "Total" : "Paused ·")
                        .accessibilityLabel(timer.isRunning ? "Total" : "Paused, total")
                    FeedingClockText(state: timer)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 16) {
                SideClock(timer: timer, side: .left)
                SideClock(timer: timer, side: .right)
            }
            FeedingButtons(timer: timer)
        }
    }
}

/// "Left 4:05", highlighted while that side is running.
private struct SideClock: View {
    let timer: FeedingTimerState
    let side: BreastSide

    private var isCurrent: Bool { timer.side == side }

    var body: some View {
        VStack(spacing: 0) {
            Text(isCurrent && timer.isRunning ? "\(side.title) ●" : side.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.pink : Color.secondary)
                // On the title, so the combined element still reads the clock after it.
                .accessibilityLabel(isCurrent && timer.isRunning ? "\(side.title) side, feeding now" : "\(side.title) side")
            FeedingClockText(state: timer, side: side)
                .font(.title3.weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Switch, Pause / Resume and Done. They run in the app (see Shared/ButtonIntents.swift).
private struct FeedingButtons: View {
    let timer: FeedingTimerState

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: SwitchFeedingSideIntent()) {
                Label("Switch", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Switch to the \(timer.side.other.title.lowercased()) side")

            Button(intent: ToggleFeedingPauseIntent()) {
                Label(timer.isRunning ? "Pause" : "Resume", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }

            Button(intent: FinishFeedingIntent()) {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Done, save this feed")
        }
        .buttonStyle(.bordered)
        .tint(.pink)
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
    }
}
