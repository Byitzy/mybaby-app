import CoreData
import Foundation
import Observation

/// The breastfeeding timer: start on a side, switch with one tap, pause, and save it as a feeding.
///
/// The state lives in the App Group as a `FeedingTimerState` (see Shared/FeedingTimerState.swift), so
/// the timer keeps going if the app is closed, and the Today screen, the Live Activity, widgets and Siri
/// all see the same timer. Every change goes through here, which saves it, updates the Live Activity
/// and refreshes the widgets.
@MainActor
@Observable
final class FeedingTimer {
    static let shared = FeedingTimer()

    /// The timer going on now, or `nil`.
    private(set) var state: FeedingTimerState?

    private init() {
        state = FeedingTimerState.load()
    }

    var isActive: Bool { state != nil }

    /// Picks up a change made by another process.
    func reload() {
        let saved = FeedingTimerState.load()
        if saved != state { state = saved }
    }

    // MARK: Controls

    /// Starts feeding on `side` for `baby`. If a timer is already going, switches it to `side` instead.
    /// `now` is when it happened; the Apple Watch passes the time it was tapped.
    func start(_ side: BreastSide, baby: Baby?, at now: Date = .now) {
        if var current = state {
            current.feed(on: side, at: now)
            commit(current)
            return
        }
        let new = FeedingTimerState(
            side: side,
            at: now,
            babyID: baby?.uuid?.uuidString,
            babyName: baby?.displayName ?? String(localized: "Baby", comment: "Shown on the Live Activity when the baby has no name")
        )
        commit(new, startLiveActivity: true)
    }

    /// Feeds on `side`, or pauses it if it's the side running now. What tapping a side's button does.
    func tap(_ side: BreastSide, baby: Baby?) {
        if let current = state, current.isRunning, current.side == side {
            pause()
        } else {
            start(side, baby: baby)
        }
    }

    func switchSide(at now: Date = .now) {
        guard var current = state else { return }
        current.switchSide(at: now)
        commit(current)
    }

    func pause() {
        guard var current = state else { return }
        current.pause()
        commit(current)
    }

    func resume() {
        guard var current = state else { return }
        current.resume()
        commit(current)
    }

    func togglePause() {
        guard let current = state else { return }
        if current.isRunning { pause() } else { resume() }
    }

    /// Saves the timer as a breastfeeding entry with minutes on each side, and stops it.
    /// Returns the new entry, or `nil` when there was no timer (or no baby to save it for).
    @discardableResult
    func finish(context: NSManagedObjectContext, at now: Date = .now) -> Activity? {
        guard let current = state else { return nil }
        guard let baby = Self.baby(withID: current.babyID, in: context) ?? Baby.current(in: context) else {
            commit(nil)
            return nil
        }

        let activity = Activity.create(.feeding, startDate: current.startDate, in: context)
        // `create` attaches the baby shown in the app; the timer may have been started for the other twin.
        if activity.baby != baby {
            if let store = baby.objectID.persistentStore {
                context.assign(activity, to: store)
            }
            activity.baby = baby
        }
        activity.feedingType = .breast
        activity.leftMinutes = current.minutes(on: .left, at: now)
        activity.rightMinutes = current.minutes(on: .right, at: now)
        // Credited to the parent on duty, like the quick log on Today.
        activity.caregiver = NightPlan.load().shift(at: activity.startDate)?.parent
        context.saveIfChanged()
        NotificationManager.refreshFeedingReminder(context: context)

        UserDefaults.shared.set(current.side.rawValue, forKey: SharedKey.lastBreastSide)
        commit(nil)
        return activity
    }

    /// Stops the timer without saving anything.
    func discard() {
        commit(nil)
    }

    private func commit(_ new: FeedingTimerState?, startLiveActivity: Bool = false) {
        state = new
        FeedingTimerState.save(new)
        LiveActivities.updateFeeding(new, startIfNeeded: startLiveActivity)
        WidgetSnapshotWriter.shared.refreshNow()
    }

    private static func baby(withID id: String?, in context: NSManagedObjectContext) -> Baby? {
        guard let id, let babies = try? context.fetch(Baby.fetchAll()) else { return nil }
        return babies.first { $0.uuid?.uuidString == id }
    }

    // MARK: Which side next

    /// A suggestion for the side to start on, from the last breastfeeding.
    struct Suggestion {
        let side: BreastSide
        /// Why, e.g. "It had less time last feed."
        let reason: String
    }

    /// Start on the side that got less time last feed (or wasn't used at all). When both got the same,
    /// start on the side the last timed feed didn't end on. `nil` without a breastfeeding to go on.
    static func suggestion(for baby: Baby, in context: NSManagedObjectContext) -> Suggestion? {
        let request = baby.entries(Activity.fetch(
            NSPredicate(format: "kindRaw == %@ AND feedingTypeRaw == %@", ActivityKind.feeding.rawValue, FeedingType.breast.rawValue),
            limit: 1
        ))
        guard let last = try? context.fetch(request).first else { return nil }
        let left = last.leftMinutes ?? 0
        let right = last.rightMinutes ?? 0

        if left == 0 && right == 0 { return nil }
        if left == 0 { return Suggestion(side: .left, reason: String(localized: "Only the right side was used last feed.", comment: "Breastfeeding")) }
        if right == 0 { return Suggestion(side: .right, reason: String(localized: "Only the left side was used last feed.", comment: "Breastfeeding")) }
        if left < right { return Suggestion(side: .left, reason: lessTime(left, vs: right)) }
        if right < left { return Suggestion(side: .right, reason: lessTime(right, vs: left)) }

        guard let raw = UserDefaults.shared.string(forKey: SharedKey.lastBreastSide),
              let ended = BreastSide(rawValue: raw)
        else { return nil }
        let reason = ended == .left
            ? String(localized: "The last feed ended on the left side.", comment: "Breastfeeding")
            : String(localized: "The last feed ended on the right side.", comment: "Breastfeeding")
        return Suggestion(side: ended.other, reason: reason)
    }

    /// "It had less time last feed (4 vs 9 min)."
    private static func lessTime(_ minutes: Int, vs other: Int) -> String {
        String(localized: "It had less time last feed (\(minutes) vs \(other) min).", comment: "Breastfeeding: the suggested side, then the other side, in minutes")
    }
}
