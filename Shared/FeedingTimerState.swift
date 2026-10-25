import AppIntents
import Foundation

/// A breast, for the breastfeeding timer.
enum BreastSide: String, Codable, Hashable, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }

    var other: BreastSide { self == .left ? .right : .left }

    /// "Left" or "Right".
    var title: String { self == .left ? "Left" : "Right" }

    /// "L" or "R", for the Dynamic Island.
    var letter: String { self == .left ? "L" : "R" }
}

/// So Siri can be asked to "start breastfeeding on the left".
extension BreastSide: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Side"
    static var caseDisplayRepresentations: [BreastSide: DisplayRepresentation] = [
        .left: "Left",
        .right: "Right",
    ]
}

/// A breastfeeding timer in progress: which side is running, since when, and the time banked on each side.
///
/// It's kept in `UserDefaults.shared` (see `load()` / `save(_:)`) rather than in memory, so it survives the
/// app being closed, and widgets, Live Activities and the Apple Watch app can read it. Elapsed time is
/// always worked out from dates, never counted by a running clock, so nothing needs to tick in the
/// background. `FeedingTimer` (in the app) is the only thing that changes it.
struct FeedingTimerState: Codable, Hashable {
    /// When the feed began. The saved breastfeeding entry starts here.
    var startDate: Date
    /// The side being fed on, or the side it was paused on.
    var side: BreastSide
    /// False while paused.
    var isRunning: Bool
    /// When `side` started running this time. Only meaningful while `isRunning`.
    var segmentStart: Date
    /// Time on each side before the current stretch.
    var leftSeconds: TimeInterval = 0
    var rightSeconds: TimeInterval = 0
    /// The baby being fed (`Baby.uuid`), so the entry goes to the right twin.
    var babyID: String?
    var babyName: String

    init(side: BreastSide, at date: Date = .now, babyID: String?, babyName: String) {
        startDate = date
        self.side = side
        isRunning = true
        segmentStart = date
        self.babyID = babyID
        self.babyName = babyName
    }

    // MARK: Reading

    /// Seconds on `side` so far, including the stretch running now.
    func seconds(on side: BreastSide, at now: Date = .now) -> TimeInterval {
        let banked = side == .left ? leftSeconds : rightSeconds
        guard isRunning, side == self.side else { return banked }
        return banked + max(0, now.timeIntervalSince(segmentStart))
    }

    func totalSeconds(at now: Date = .now) -> TimeInterval {
        seconds(on: .left, at: now) + seconds(on: .right, at: now)
    }

    /// The moment a clock for `side` would have started from zero, for `Text(_:style: .timer)`,
    /// which then counts up by itself. `nil` when that side isn't running (show `clock(_:)` instead).
    func timerStart(for side: BreastSide) -> Date? {
        guard isRunning, side == self.side else { return nil }
        return segmentStart.addingTimeInterval(-(side == .left ? leftSeconds : rightSeconds))
    }

    /// Like `timerStart(for:)`, for both sides together.
    var totalTimerStart: Date? {
        guard isRunning else { return nil }
        return segmentStart.addingTimeInterval(-(leftSeconds + rightSeconds))
    }

    /// Whole minutes for the saved entry: rounded, at least 1 for a side that was used, 0 for one that wasn't.
    func minutes(on side: BreastSide, at now: Date = .now) -> Int {
        let seconds = seconds(on: side, at: now)
        guard seconds > 0 || side == self.side else { return 0 }
        return max(1, Int((seconds / 60).rounded()))
    }

    // MARK: Changing

    /// Banks the running stretch and carries on with the other side (unpausing if needed).
    mutating func switchSide(at now: Date = .now) {
        bankRunningStretch(at: now)
        side = side.other
        isRunning = true
        segmentStart = now
    }

    /// Feeds on `side`: switches to it, or resumes it if paused there.
    mutating func feed(on side: BreastSide, at now: Date = .now) {
        if side != self.side {
            switchSide(at: now)
        } else if !isRunning {
            resume(at: now)
        }
    }

    mutating func pause(at now: Date = .now) {
        guard isRunning else { return }
        bankRunningStretch(at: now)
        isRunning = false
    }

    mutating func resume(at now: Date = .now) {
        guard !isRunning else { return }
        isRunning = true
        segmentStart = now
    }

    private mutating func bankRunningStretch(at now: Date) {
        guard isRunning else { return }
        let stretch = max(0, now.timeIntervalSince(segmentStart))
        if side == .left { leftSeconds += stretch } else { rightSeconds += stretch }
        segmentStart = now
    }

    // MARK: Storage

    /// The timer in progress, or `nil` when there isn't one.
    static func load(from defaults: UserDefaults = .shared) -> FeedingTimerState? {
        guard let data = defaults.data(forKey: SharedKey.feedingTimer) else { return nil }
        return try? JSONDecoder().decode(FeedingTimerState.self, from: data)
    }

    /// Saves the timer, or clears it when `state` is `nil`.
    static func save(_ state: FeedingTimerState?, to defaults: UserDefaults = .shared) {
        if let state, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: SharedKey.feedingTimer)
        } else {
            defaults.removeObject(forKey: SharedKey.feedingTimer)
        }
    }

    // MARK: Formatting

    /// "4:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
