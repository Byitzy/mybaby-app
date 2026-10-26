import Foundation

/// What the widgets show, written by the app as a small JSON file in the App Group container. The Apple
/// Watch app gets the same snapshot inside a `WatchContext`, over WatchConnectivity.
///
/// Extensions never open the Core Data stores: the app is the only process that reads the log, and
/// `WidgetSnapshotWriter` (in the app) rewrites this file whenever the log, the selected baby, the
/// night plan, the breastfeeding timer or cry alerts' listening changes, then reloads the widgets.
///
/// The top-level fields (`babyName`, `lastFeed`, `sleepStart`, …) are for the baby shown in the app, as
/// they always were, so the Apple Watch and older readers keep working. `babies` has the same and more
/// for every baby, so each widget can show the baby picked in Edit Widget (twins side by side). Who's on
/// night duty, the breastfeeding timer and cry alerts' listening are the same for every baby.
///
/// **Privacy:** it holds only what the widgets show. It stays on this iPhone, in the App Group's folder;
/// it's never synced or sent anywhere, except that the paired Apple Watch gets it over WatchConnectivity
/// (see `WatchContext`), with `babies` trimmed to what the watch's complications show.
///
/// Times are stored as dates, so views count from them (`Text(_:style: .relative)`) and stay current
/// without the file being rewritten. Text is already formatted in the parent's units (ml or oz).
struct WidgetSnapshot: Codable, Equatable {
    struct Feed: Codable, Equatable {
        var date: Date
        /// "Bottle (formula)", "Breastfeeding".
        var title: String
        /// "Formula", "Breast".
        var shortTitle: String
        var emoji: String
        /// "120 ml", "Left 10m · Right 5m", or empty.
        var detail: String
    }

    struct Diaper: Codable, Equatable {
        var date: Date
        /// "Pee", "Poop", "Pee + poop", "Dry".
        var title: String
        var emoji: String
    }

    /// A stretch of a night one parent is on duty for (see `NightPlan`).
    struct Shift: Codable, Equatable {
        var parentName: String
        /// Parent 1 is shown in pink, parent 2 in blue, as in the app.
        var isParent1: Bool
        var start: Date
        var end: Date

        func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// One baby's part of the snapshot. Every baby has one, so a widget set to a particular baby shows
    /// theirs, whichever baby the app is showing.
    ///
    /// Added after the first version of the file: anything added here later must be optional, so
    /// snapshots written before it still decode.
    struct BabySnapshot: Codable, Equatable, Identifiable {
        /// A pumping session.
        struct Pumping: Codable, Equatable {
            var date: Date
            /// "150 ml", or empty without an amount.
            var amountText: String
        }

        /// The milk stash: bags not used or thrown away.
        struct Stash: Codable, Equatable {
            /// "1240 ml", or empty when no bag has an amount.
            var totalText: String
            var bagCount: Int
        }

        /// A medicine with dose timing (`MedicineSchedule`), as the app's medicine list shows it.
        struct NextDose: Codable, Equatable {
            var name: String
            /// When the timing the parent entered allows the next dose, or `nil` when it allows one now.
            var date: Date?
        }

        /// The medicine given last, for the widget's Medicine button, which logs it again.
        struct Medicine: Codable, Equatable {
            var name: String
            /// As the parent wrote it last time ("2.5 ml"), or empty.
            var dosage: String
            /// While the dose timing entered for it doesn't allow another dose yet: when it will.
            var nextAllowed: Date?
            /// The medicine allergy on the baby's list it matches (`AllergyMatch.medicineMatches`), as
            /// listed, e.g. "Amoxicillin". While it's set, the button never logs it: it says "Check
            /// allergy list" and opens the app. Added later, so it's optional.
            var allergyName: String? = nil
        }

        /// The last bottle, for the Bottle button, which logs the same again.
        struct Bottle: Codable, Equatable {
            var isFormula: Bool
            var ml: Double?
            /// "120 ml", or empty without an amount.
            var amountText: String
        }

        /// `Baby.uuid`.
        var id: String
        var name: String
        var lastFeed: Feed?
        var lastDiaper: Diaper?
        /// When the sleep going on now started, or `nil` while awake.
        var sleepStart: Date?
        /// That sleep's `Activity.uuid`.
        var sleepID: String?
        /// When the last sleep ended, while awake.
        var lastWake: Date?
        /// The start of the day `feedsToday` and `diapersToday` count. Once that day is over they read
        /// as 0 until the app writes a new snapshot.
        var countedDay: Date
        var feedsToday = 0
        var diapersToday = 0
        var lastPumping: Pumping?
        var stash: Stash?
        /// The medicine with dose timing whose next dose is allowed soonest, or else the one given most
        /// recently. `nil` when no medicine with dose timing has been given.
        var nextDose: NextDose?
        var lastMedicine: Medicine?
        var usualBottle: Bottle?
        /// When the next feed is probably due (`FeedPredictor`), only when the log shows a pattern, not a
        /// rough guess. `nil` while breastfeeding.
        var nextFeedExpected: Date?

        var isSleeping: Bool { sleepStart != nil }

        /// Feeds on the day of `date`: 0 once the counted day is over.
        func feeds(on date: Date, calendar: Calendar = .current) -> Int {
            calendar.isDate(date, inSameDayAs: countedDay) ? feedsToday : 0
        }

        /// Diapers on the day of `date`: 0 once the counted day is over.
        func diapers(on date: Date, calendar: Calendar = .current) -> Int {
            calendar.isDate(date, inSameDayAs: countedDay) ? diapersToday : 0
        }
    }

    /// Cry alerts listening on this iPhone (`CryMonitor`), for the widgets' mic badge. It's the app's
    /// state, not a baby's, and it's never set on a nursery monitor, which has its own screen.
    struct Listening: Codable, Equatable {
        /// When listening started.
        var since: Date
        /// When the crying going on now started, or `nil` while it's quiet.
        var cryingSince: Date?
        /// When listening stops by itself (`ListeningStop`), or `nil` to listen until it's stopped.
        var stopsAt: Date?

        var isCrying: Bool { cryingSince != nil }
    }

    /// Bumped if the format changes in a way older readers can't handle.
    var version = 1
    var babyName: String
    /// `Baby.uuid` of the baby shown.
    var babyID: String?
    /// How many babies there are, to say whose log this is when there are twins.
    var babyCount = 1
    var lastFeed: Feed?
    var lastDiaper: Diaper?
    /// When the sleep going on now started, or `nil` while baby is awake.
    var sleepStart: Date?
    /// That sleep's `Activity.uuid`, so a Woke up button ends this one.
    var sleepID: String?
    /// When the last sleep ended, while baby is awake.
    var lastWake: Date?
    /// Tonight's and tomorrow night's shifts when the night plan is on, so a widget can tell who's on
    /// duty at any moment in its timeline. Empty when the plan is off.
    var shifts: [Shift] = []
    /// The breastfeeding timer, while one is going.
    var feedingTimer: FeedingTimerState?
    var updatedAt = Date.now
    /// Every baby, oldest first, the one shown in the app included. `nil` in snapshots written before
    /// widgets could pick a baby (`baby(_:)` then falls back to the top-level fields). In the copy sent to
    /// the Apple Watch, each is trimmed to what the complications show (`WatchBridge.makeContext`).
    var babies: [BabySnapshot]?
    /// While cry alerts listen on this iPhone. Added later, so it's optional: snapshots written before
    /// it decode without it, as not listening. Left out of the copy sent to the Apple Watch.
    var listening: Listening?

    var isSleeping: Bool { sleepStart != nil }

    /// Cry alerts listening at `date`, as far as the snapshot knows. From its stop time on it reads as
    /// stopped, so a widget's timeline stops showing "Listening" then even if the app couldn't reload it.
    func activeListening(at date: Date) -> Listening? {
        guard let listening else { return nil }
        if let stop = listening.stopsAt, date >= stop { return nil }
        return listening
    }

    /// The baby shown in the app (`Baby.uuid`): the same as `babyID`.
    var selectedBabyID: String? { babyID }

    /// The baby with `Baby.uuid` `id`, or the one shown in the app when `id` is `nil` or that baby
    /// isn't here any more.
    func baby(_ id: String?) -> BabySnapshot {
        let list = babies ?? []
        if let id, let match = list.first(where: { $0.id == id }) { return match }
        if let match = list.first(where: { $0.id == (babyID ?? "") }) { return match }
        // Written before `babies`: only the shown baby's basics.
        return BabySnapshot(
            id: babyID ?? "",
            name: babyName,
            lastFeed: lastFeed,
            lastDiaper: lastDiaper,
            sleepStart: sleepStart,
            sleepID: sleepID,
            lastWake: lastWake,
            countedDay: .distantPast
        )
    }

    /// The breastfeeding timer, if it's for `baby`. A timer without a baby is for the one shown in the app.
    func timer(for baby: BabySnapshot) -> FeedingTimerState? {
        guard let timer = feedingTimer else { return nil }
        return (timer.babyID ?? babyID ?? "") == baby.id ? timer : nil
    }

    /// The parent on night duty at `date`, if any.
    func shift(at date: Date) -> Shift? {
        shifts.first { $0.contains(date) }
    }

    /// Same content, ignoring when it was written.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.updatedAt = updatedAt
        return copy == self
    }

    // MARK: Storage

    /// `WidgetSnapshot.json` in the App Group, or `nil` when the App Group isn't set up.
    static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("WidgetSnapshot.json")
    }

    /// The latest snapshot, or `nil` before the app has written one (or when there's no baby yet).
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes `snapshot`, or removes the file when it's `nil`.
    static func save(_ snapshot: WidgetSnapshot?) {
        guard let url = fileURL else { return }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
