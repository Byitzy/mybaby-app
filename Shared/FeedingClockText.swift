import SwiftUI

/// A breastfeeding timer's elapsed time ("4:05") for one side, or both when `side` is `nil`.
///
/// While that side runs, it's a `Text(_:style: .timer)`, which the system counts up by itself, so it
/// stays right in a Live Activity, a widget or the app without pushes, reloads or a ticking clock.
/// Paused (or for the side not being fed on) it's the fixed time so far.
struct FeedingClockText: View {
    let state: FeedingTimerState
    var side: BreastSide?

    var body: some View {
        if let runningSince {
            Text(runningSince, style: .timer)
                .monospacedDigit()
        } else {
            Text(FeedingTimerState.clock(secondsSoFar))
                .monospacedDigit()
        }
    }

    private var runningSince: Date? {
        if let side { return state.timerStart(for: side) }
        return state.totalTimerStart
    }

    private var secondsSoFar: TimeInterval {
        if let side { return state.seconds(on: side) }
        return state.totalSeconds()
    }
}
