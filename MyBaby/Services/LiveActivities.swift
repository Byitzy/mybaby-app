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
