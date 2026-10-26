import CoreData
import SwiftUI

/// The breastfeeding timer: tap a side to start, tap the other side (or Switch) to change, pause,
/// then Done to save the feed with the minutes on each side.
///
/// Closing the sheet leaves the timer running; it's on Today, the Lock Screen and in the Dynamic Island.
struct BreastfeedingTimerView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var baby: Baby
    /// Called with the saved entry after Done, so Today can offer Undo.
    let onSaved: (Activity) -> Void

    private let timer = FeedingTimer.shared
    @State private var suggestion: FeedingTimer.Suggestion?
    @State private var confirmingDiscard = false

    init(baby: Baby, onSaved: @escaping (Activity) -> Void = { _ in }) {
        self.baby = baby
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let state = timer.state {
                        summary(state)
                    } else {
                        hint
                    }

                    HStack(spacing: 12) {
                        ForEach(BreastSide.allCases) { side in
                            SideButton(
                                side: side,
                                state: timer.state,
                                isSuggested: timer.state == nil && suggestion?.side == side
                            ) {
                                timer.tap(side, baby: baby)
                            }
                        }
                    }

                    if let state = timer.state {
                        controls(state)
                    }
                }
                .padding()
            }
            .navigationTitle("Breastfeeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(timer.isActive ? "Close" : "Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Discard this feed?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    timer.discard()
                    dismiss()
                }
            } message: {
                Text("The timer stops and nothing is saved.")
            }
            .onAppear {
                suggestion = FeedingTimer.suggestion(for: baby, in: context)
            }
        }
        .threeAMSheet()
    }

    // MARK: Pieces

    /// Which side to start on, before the timer starts.
    @ViewBuilder
    private var hint: some View {
        VStack(spacing: 6) {
            if let suggestion {
                EmojiTitle("💡", "Start with the \(suggestion.side.title.lowercased()) side next")
                    .font(.headline)
                Text(suggestion.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap the side you're starting on")
                    .font(.headline)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Total time and when the feed started.
    private func summary(_ state: FeedingTimerState) -> some View {
        // Redrawn each minute so VoiceOver reads the minutes so far, not a ticking clock.
        TimelineView(.everyMinute) { timeline in
            summaryContent(state)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenSummary(state, now: timeline.date))
        }
    }

    /// "Total 20 minutes, started 9:10 PM", or "Paused, …".
    private func spokenSummary(_ state: FeedingTimerState, now: Date) -> String {
        let total = Format.spokenDuration(state.totalSeconds(at: now))
        let started = state.startDate.formatted(date: .omitted, time: .shortened)
        var text = state.isRunning
            ? String(localized: "Total \(total), started \(started)")
            : String(localized: "Paused. Total \(total), started \(started)")
        if state.babyID != baby.uuid?.uuidString {
            text += ". " + String(localized: "Feeding \(state.babyName)", comment: "The breastfeeding timer is for this baby, e.g. the other twin")
        }
        return text
    }

    private func summaryContent(_ state: FeedingTimerState) -> some View {
        VStack(spacing: Spacing.xs) {
            FeedingClockText(state: state)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(state.isRunning
                 ? "Total · started \(state.startDate.formatted(date: .omitted, time: .shortened))"
                 : "Paused · started \(state.startDate.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if state.babyID != baby.uuid?.uuidString {
                NoticeLabel("Feeding \(state.babyName)", systemImage: "person.fill", tint: ActivityKind.feeding.color)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controls(_ state: FeedingTimerState) -> some View {
        VStack(spacing: Spacing.m) {
            // One above the other at the largest text sizes.
            AdaptiveStack(horizontalAlignment: .center, spacing: Spacing.m) {
                Button {
                    timer.togglePause()
                } label: {
                    Label(state.isRunning ? "Pause" : "Resume", systemImage: state.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                Button {
                    timer.switchSide()
                } label: {
                    Label(state.side.other == .left ? "Switch to left" : "Switch to right", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
            .buttonStyle(.bordered)

            Button {
                if let feed = timer.finish(context: context) {
                    onSaved(feed)
                }
                dismiss()
            } label: {
                Text("Done · save feed")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)

            Button("Discard", role: .destructive) {
                confirmingDiscard = true
            }
            .padding(.top, Spacing.xs)
        }
        .tint(ActivityKind.feeding.color)
    }
}

/// A big button for one side, showing its time. Tapping it starts, switches to or pauses that side.
private struct SideButton: View {
    let side: BreastSide
    let state: FeedingTimerState?
    let isSuggested: Bool
    let action: () -> Void

    private var isRunning: Bool { state?.isRunning == true && state?.side == side }
    private var tint: Color { ActivityKind.feeding.color }

    var body: some View {
        // Redrawn each minute so VoiceOver reads this side's minutes, not a ticking clock.
        TimelineView(.everyMinute) { timeline in
            button(now: timeline.date)
        }
    }

    /// "12 minutes, feeding", "4 minutes, paused, tap to resume".
    private func spokenValue(now: Date) -> String {
        let status = Format.spoken(self.status.replacingOccurrences(of: "● ", with: ""))
        guard let state else { return status }
        return "\(Format.spokenDuration(state.seconds(on: side, at: now))), \(status)"
    }

    private func button(now: Date) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                Text(side.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Group {
                    if let state {
                        FeedingClockText(state: state, side: side)
                    } else {
                        Text("0:00")
                    }
                }
                .font(.system(.title, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(isRunning ? tint : Color.secondary)
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(.vertical, Spacing.s)
            .background(tint.opacity(isRunning ? 0.25 : 0.1), in: RoundedRectangle(cornerRadius: Radius.largeButton))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.largeButton)
                    .strokeBorder(tint.opacity(isRunning || isSuggested ? 0.9 : 0.3), lineWidth: isRunning || isSuggested ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .left ? "Left side" : "Right side")
        .accessibilityValue(spokenValue(now: now))
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts timing this side")
        .accessibilityAddTraits(isRunning ? .isSelected : [])
    }

    /// Said in words too, so the running side isn't shown by color alone.
    private var status: String {
        if isRunning { return String(localized: "● Feeding", comment: "This side is the one feeding now") }
        if let state {
            if state.side == side { return String(localized: "Paused · tap to resume") }
            return String(localized: "Tap to switch")
        }
        return isSuggested ? String(localized: "Suggested · tap to start") : String(localized: "Tap to start")
    }
}
