import ActivityKit
import Foundation

/// Starts, updates and ends the breastfeeding and sleep Live Activities.
///
/// ActivityKit's `Activity` is written in full (`ActivityKit.Activity`) because the app's own Core Data
/// entity is also called `Activity`. The views are in the MyBabyWidgets extension; the types they show
/// are in Shared/LiveActivityAttributes.swift.
///
/// Live Activities are local: their content comes from this phone, with no push server.
@MainActor
enum LiveActivities {
    private typealias FeedingActivity = ActivityKit.Activity<FeedingActivityAttributes>
    private typealias SleepActivity = ActivityKit.Activity<SleepActivityAttributes>
    private typealias ListeningActivity = ActivityKit.Activity<ListeningActivityAttributes>

    /// When the listening a Live Activity was last started for began, so one the parent swiped away
    /// isn't started again for the same night. In memory only: listening never outlives the app.
    private static var listeningActivityStart: Date?

    private static var areEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: Breastfeeding

    /// Shows `state` in the feeding Live Activity, or ends it when the timer stopped (`nil`).
    /// A new one is only started with a new timer, so a parent who swiped it away isn't shown it again.
    static func updateFeeding(_ state: FeedingTimerState?, startIfNeeded: Bool) {
        let running = FeedingActivity.activities
        guard let state else {
            for activity in running {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let content = ActivityContent(state: FeedingActivityAttributes.ContentState(timer: state), staleDate: nil)
        if running.isEmpty {
            guard startIfNeeded, areEnabled else { return }
            do {
                _ = try FeedingActivity.request(
                    attributes: FeedingActivityAttributes(babyName: state.babyName),
                    content: content,
                    pushType: nil
                )
            } catch {
                print("MyBaby: couldn't start the feeding Live Activity: \(error)")
            }
        } else {
            for activity in running {
                Task { await activity.update(content) }
            }
        }
    }

    /// Ends every MyBaby Live Activity at once, for Delete all MyBaby data (see `DataWipe`).
    static func endAll() async {
        for activity in FeedingActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in SleepActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in ListeningActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: Cry alerts

    /// Matches the listening Live Activity to cry alerts on this iPhone (`CryMonitor.listeningSummary`):
    /// started when listening starts, updated when a cry starts or ends or the stop time changes, and
    /// ended, right away, when listening stops (`nil`). Any other listening's activity, such as one left
    /// behind when iOS closed the app, is ended too.
    ///
    /// Each listening gets one Live Activity at most: if the parent swipes it away, it stays away until
    /// they start listening again. Starting one can fail while the app is in the background (when
    /// listening starts again by itself after a call); `WidgetSnapshotWriter` tries again when the app
    /// opens. A parent who turned off Live Activities for MyBaby isn't shown one.
    ///
    /// Not on a nursery monitor: `listeningSummary` is `nil` there. The monitor has its own full-screen,
    /// dim screen that stays on by the crib, and Stop monitor asks first; a Lock Screen Stop button
    /// would stop it with one tap, and nobody is by it to see the activity anyway. The parents' phones
    /// already show whether it's listening.
    static func syncListening(_ listening: WidgetSnapshot.Listening?) {
        let running = ListeningActivity.activities
        for activity in running where !isSameListening(activity, as: listening) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let listening else { return }

        let state = ListeningActivityAttributes.ContentState(cryingSince: listening.cryingSince, stopsAt: listening.stopsAt)
        // Marked out of date at the stop time, in case the app is gone by then and can't end it.
        let content = ActivityContent(state: state, staleDate: listening.stopsAt)
        if let current = running.first(where: { isSameListening($0, as: listening) }) {
            if current.content.state != state {
                Task { await current.update(content) }
            }
            return
        }

        if let started = listeningActivityStart, abs(started.timeIntervalSince(listening.since)) < 1 { return }
        guard areEnabled else { return }
        do {
            _ = try ListeningActivity.request(
                attributes: ListeningActivityAttributes(since: listening.since),
                content: content,
                pushType: nil
            )
            listeningActivityStart = listening.since
        } catch {
            // Usually because the app is in the background. Tried again when it opens.
        }
    }

    /// Ends the listening Live Activity before iOS closes the app (`applicationWillTerminate`), waiting
    /// a moment for it: once the app is gone, nothing would end it.
    nonisolated static func endListeningBeforeExit() {
        let running = ListeningActivity.activities
        guard !running.isEmpty else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    /// Whether `activity` is for `listening`. Compared to the second: the start time goes through
    /// ActivityKit's encoding.
    private static func isSameListening(_ activity: ListeningActivity, as listening: WidgetSnapshot.Listening?) -> Bool {
        guard let listening else { return false }
        return abs(activity.attributes.since.timeIntervalSince(listening.since)) < 1
    }

    // MARK: Sleep

    /// Matches the sleep Live Activity to the shown baby's sleep: started when a sleep is going on,
    /// updated if its start time was edited, ended when the baby wakes up. Called with every widget
    /// snapshot, so it follows sleeps started or ended anywhere, including on the partner's phone.
    ///
    /// Each sleep gets one Live Activity at most: if the parent dismisses it, it stays dismissed.
    /// Starting one can fail while the app is in the background; it's tried again when the app opens.
    static func syncSleep(start: Date?, sleepID: String?, babyName: String) {
        let running = SleepActivity.activities
        for activity in running where activity.attributes.sleepID != sleepID || start == nil {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let start, let sleepID else { return }

        let content = ActivityContent(state: SleepActivityAttributes.ContentState(startDate: start), staleDate: nil)
        if let current = running.first(where: { $0.attributes.sleepID == sleepID }) {
            if current.content.state.startDate != start {
                Task { await current.update(content) }
            }
            return
        }

        let defaults = UserDefaults.shared
        guard defaults.string(forKey: SharedKey.sleepLiveActivityID) != sleepID, areEnabled else { return }
        do {
            _ = try SleepActivity.request(
                attributes: SleepActivityAttributes(babyName: babyName, sleepID: sleepID),
                content: content,
                pushType: nil
            )
            defaults.set(sleepID, forKey: SharedKey.sleepLiveActivityID)
        } catch {
            // Usually because the app is in the background. Tried again when it opens.
        }
    }
}
