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

/// "Listening for crying" while cry alerts listen on this iPhone, with a Stop button, and "Crying for
/// 1:20" during a cry.
///
/// `CryMonitor` starts one when listening starts, updates it when a cry starts or ends (it runs in the
/// background with audio), and ends it when listening stops, however that happens. Not on a nursery
/// monitor (see `LiveActivities.syncListening`). It says only that cry alerts are listening, and
/// whether crying is heard now: nothing from the log, not even the baby's name.
struct ListeningActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the crying going on now started, or `nil` while it's quiet.
        var cryingSince: Date?
        /// When listening stops by itself, for "until 7:00", or `nil` to listen until it's stopped.
        var stopsAt: Date?

        var isCrying: Bool { cryingSince != nil }
    }

    /// When listening started, which also tells one listening apart from the next.
    var since: Date
}
