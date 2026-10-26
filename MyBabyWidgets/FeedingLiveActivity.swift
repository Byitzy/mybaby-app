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
                        Text(verbatim: "🤱 \(context.attributes.babyName)")
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
                Text(verbatim: "🤱 \(context.state.timer.side.letter)")
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel(context.state.timer.side == .left ? Text("Breastfeeding, left side") : Text("Breastfeeding, right side"))
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
                Text(verbatim: "🤱 \(babyName)")
                    .font(.headline)
                    .accessibilityLabel("Breastfeeding \(babyName)")
                Spacer()
                HStack(spacing: 4) {
                    (timer.isRunning ? Text("Total", comment: "Breastfeeding Live Activity: the time on both sides together") : Text("Paused ·"))
                        .accessibilityLabel(timer.isRunning ? Text("Total") : Text("Paused, total"))
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

    /// "Left side, feeding now", for VoiceOver.
    private var feedingNowLabel: String {
        side == .left
            ? String(localized: "Left side, feeding now", comment: "VoiceOver, breastfeeding Live Activity")
            : String(localized: "Right side, feeding now", comment: "VoiceOver, breastfeeding Live Activity")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isCurrent && timer.isRunning ? "\(side.title) ●" : side.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.pink : Color.secondary)
                // On the title, so the combined element still reads the clock after it.
                .accessibilityLabel(isCurrent && timer.isRunning ? feedingNowLabel : side.sideTitle)
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
            .accessibilityLabel(timer.side.other == .left ? Text("Switch to the left side") : Text("Switch to the right side"))

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
