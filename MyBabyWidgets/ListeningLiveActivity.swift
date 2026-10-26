import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Cry alerts listening on this iPhone, on the Lock Screen and in the Dynamic Island: "Listening for
/// crying", since when and until when, with a Stop button. During a cry it turns orange, "Crying for
/// 1:20", counting by itself; the app only sends an update when a cry starts or ends.
///
/// It's on all night next to a sleeping parent, so it keeps to 3 AM mode's spirit whatever that
/// setting is: a dark background, soft colors, small type, and nothing that flashes or pulses. It shows
/// only that cry alerts are listening, never anything from the log.
struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningActivityAttributes.self) { context in
            ListeningLockScreenView(since: context.attributes.since, state: context.state, isStale: context.isStale)
                .padding()
                // Light text on a dark background in light mode too, so it doesn't light up the room.
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(ListeningStyle.dimText)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        MicGlyph(isCrying: state.isCrying)
                        state.isCrying
                            ? Text("Crying", comment: "Widget badge and Live Activity: cry alerts hear the baby crying now")
                            : Text("Listening", comment: "Widget badge and Live Activity: cry alerts are listening on this iPhone")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ListeningStyle.color(isCrying: state.isCrying))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(state.isCrying ? Text("Crying heard", comment: "VoiceOver, Live Activity: cry alerts hear the baby crying now") : Text("Listening for crying"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let cryingSince = state.cryingSince {
                        Text(cryingSince, style: .timer)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(ListeningStyle.crying)
                            .frame(maxWidth: 90, alignment: .trailing)
                            .accessibilityHint("Time crying")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ListeningTimes(since: context.attributes.since, stopsAt: state.stopsAt)
                            .font(.subheadline)
                            .foregroundStyle(ListeningStyle.dimText)
                        Spacer()
                        StopListeningButton()
                    }
                }
            } compactLeading: {
                MicGlyph(isCrying: state.isCrying)
            } compactTrailing: {
                if let cryingSince = state.cryingSince {
                    Text(cryingSince, style: .timer)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: 48)
                        .foregroundStyle(ListeningStyle.crying)
                        .accessibilityHint("Time crying")
                } else if let stopsAt = state.stopsAt {
                    Text(stopsAt, style: .time)
                        .font(.caption)
                        .frame(maxWidth: 64)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(ListeningStyle.dimText)
                        .accessibilityLabel(Text("Until \(stopsAt, style: .time)", comment: "Live Activity: when cry alerts stop listening by themselves, e.g. Until 7:00 AM"))
                } else {
                    // Listening, with nothing to count: just a quiet ear, as in the app's privacy page.
                    Image(systemName: "ear")
                        .font(.caption)
                        .foregroundStyle(ListeningStyle.dimText)
                        .accessibilityHidden(true)
                }
            } minimal: {
                MicGlyph(isCrying: state.isCrying)
            }
            .keylineTint(ListeningStyle.color(isCrying: state.isCrying))
        }
    }
}

/// The Lock Screen banner: the mic, what it hears, since when (and until when), and Stop.
private struct ListeningLockScreenView: View {
    let since: Date
    let state: ListeningActivityAttributes.ContentState
    /// Past the stop time without the app ending it: the app is most likely gone, so it isn't
    /// listening any more. Stop clears it.
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            MicGlyph(isCrying: state.isCrying && !isStale)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(ListeningStyle.color(isCrying: state.isCrying && !isStale).opacity(0.15), in: Circle())
                // The text beside it says the same.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if isStale {
                    Text("Not listening", comment: "Live Activity: cry alerts stopped, but the Live Activity is still shown")
                        .font(.headline)
                        .foregroundStyle(ListeningStyle.dimText)
                } else if let cryingSince = state.cryingSince {
                    Text("Crying for \(cryingSince, style: .timer)", comment: "Live Activity: how long the baby has been crying, counting up, e.g. 1:20")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(ListeningStyle.crying)
                } else {
                    Text("Listening for crying")
                        .font(.headline)
                        .foregroundStyle(ListeningStyle.text)
                }
                ListeningTimes(since: since, stopsAt: state.stopsAt)
                    .font(.subheadline)
                    .foregroundStyle(ListeningStyle.dimText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // "Listening for crying, since 9:10 PM, until 7:00 AM" in one stop.
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            StopListeningButton()
        }
    }
}

/// "Since 9:10 PM", or "Since 9:10 PM · until 7:00 AM" when listening stops by itself.
private struct ListeningTimes: View {
    let since: Date
    let stopsAt: Date?

    var body: some View {
        if let stopsAt {
            Text("Since \(since, style: .time) · until \(stopsAt, style: .time)", comment: "Live Activity: when cry alerts started listening, then when they stop by themselves")
        } else {
            Text("Since \(since, style: .time)")
        }
    }
}

/// The mic: green while listening, orange during a cry.
private struct MicGlyph: View {
    let isCrying: Bool

    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundStyle(ListeningStyle.color(isCrying: isCrying))
            .accessibilityLabel(isCrying ? Text("Crying heard", comment: "VoiceOver, Live Activity: cry alerts hear the baby crying now") : Text("Listening for crying"))
    }
}

/// Stops cry alerts, in the app (see Shared/ButtonIntents.swift). Soft gray, so it doesn't stand out at night.
private struct StopListeningButton: View {
    var body: some View {
        Button(intent: StopListeningIntent()) {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .tint(ListeningStyle.dimText)
        .font(.subheadline.weight(.semibold))
        .accessibilityLabel("Stop listening for crying")
    }
}
