import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// "Sleeping 0:42" on the Lock Screen and in the Dynamic Island while a sleep is going on, with a
/// Woke up button that ends it.
struct SleepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text("😴")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.babyName) is sleeping")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(context.state.startDate, style: .timer)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer()
                WokeUpButton(sleepID: context.attributes.sleepID)
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("😴 Sleeping")
                        .font(.headline)
                        .accessibilityLabel("\(context.attributes.babyName) is sleeping")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: 90, alignment: .trailing)
                        .accessibilityHint("Time asleep")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Since \(context.state.startDate.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Asleep since \(context.state.startDate.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        WokeUpButton(sleepID: context.attributes.sleepID)
                    }
                }
            } compactLeading: {
                Text("😴")
                    .accessibilityLabel("Sleeping")
            } compactTrailing: {
                Text(context.state.startDate, style: .timer)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 48)
                    .foregroundStyle(.indigo)
                    .accessibilityHint("Time asleep")
            } minimal: {
                Text("😴")
                    .accessibilityLabel("Sleeping")
            }
            .keylineTint(.indigo)
        }
    }
}

/// Ends this sleep, in the app (see Shared/ButtonIntents.swift).
private struct WokeUpButton: View {
    let sleepID: String

    var body: some View {
        Button(intent: SleepButtonIntent(start: false, sleepID: sleepID)) {
            Label("Woke up", systemImage: "sun.max.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .font(.subheadline.weight(.semibold))
        .accessibilityLabel("Baby woke up, stop the sleep timer")
    }
}
