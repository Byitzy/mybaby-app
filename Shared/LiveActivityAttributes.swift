import ActivityKit
import Foundation

/// The breastfeeding timer's Live Activity, on the Lock Screen and in the Dynamic Island.
///
/// The app starts it with the timer and updates it on every change (switch, pause, resume), and ends it
/// on Done or Discard. The clocks count up on their own between updates (see `FeedingClockText`).
struct FeedingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timer: FeedingTimerState
    }

    var babyName: String
}

/// "Sleeping 0:42" while a sleep is going on, with a Woke up button.
///
/// The app starts one when a sleep starts (an `Activity` with no end date) and ends it when the sleep
/// ends, from wherever that happened: the app, Siri, a widget or the partner's phone.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the sleep started. Can change if the start time is edited.
        var startDate: Date
    }

    var babyName: String
    /// The sleep's `Activity.uuid`, so Woke up ends this sleep even if another baby is shown in the app.
    var sleepID: String
}
