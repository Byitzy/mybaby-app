import AppIntents
import Foundation

// The buttons on the widgets and Live Activities.
//
// A widget or Live Activity is drawn by the MyBabyWidgets extension, but the log is in Core Data, which
// only the app opens. These intents conform to `LiveActivityIntent`, and the system always runs a
// `LiveActivityIntent` in the app's process (launching it in the background if needed), even when the
// button that triggered it is in a widget. So:
//
// - this file is compiled into both targets: the extension needs the types to build `Button(intent:)`,
//   and the app needs them to run `perform()`;
// - the work in `perform()` uses app-only code (Core Data, `FeedingTimer`, `QuickLog`), so it's wrapped in
//   `#if !WIDGET_EXTENSION`. The widget target sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS =
//   "WIDGET_EXTENSION $(inherited)"`, where `perform()` compiles to an empty stub that never runs.
//
// After `perform()` the app rewrites the widget snapshot and updates the Live Activities, which redraws
// everything. They're hidden from Shortcuts (`isDiscoverable = false`); MyBaby/Intents has the Siri and
// Shortcuts versions, with spoken confirmations.

/// Wet, dirty or both, for diaper buttons and Siri.
enum DiaperChoice: String, CaseIterable, AppEnum {
    case wet, dirty, both

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper"
    /// The synonyms are other words Siri understands, e.g. "Log a poopy diaper in MyBaby".
    static var caseDisplayRepresentations: [DiaperChoice: DisplayRepresentation] = [
        .wet: DisplayRepresentation(title: "Wet", synonyms: ["pee", "peed"]),
        .dirty: DisplayRepresentation(title: "Dirty", synonyms: ["poopy", "poop", "poo", "soiled"]),
        .both: DisplayRepresentation(title: "Wet and dirty", synonyms: ["mixed", "pee and poop", "wet and poopy"]),
    ]
}

/// Logs a diaper from the widget's Wet, Dirty and Both buttons.
struct LogDiaperButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Diaper from Widget"
    static var isDiscoverable = false

    @Parameter(title: "Diaper")
    var choice: DiaperChoice

    /// `Baby.uuid` of the baby the widget shows. `nil` (or a baby that's gone) logs for the baby shown in the app.
    @Parameter(title: "Baby")
    var babyID: String?

    init() {}

    init(choice: DiaperChoice, babyID: String? = nil) {
        self.choice = choice
        self.babyID = babyID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try QuickLog.logDiaper(choice.diaperType, for: QuickLog.baby(withID: babyID))
        #endif
        return .result()
    }
}

/// Starts or ends a sleep: the widget's Sleep / Woke up button and the sleep Live Activity's Woke up.
struct SleepButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or End Sleep from Widget"
    static var isDiscoverable = false

    /// True to start a sleep, false to end the one going on.
    @Parameter(title: "Start")
    var start: Bool

    /// The sleep to end (`Activity.uuid`), from a Live Activity or widget. `nil` ends `babyID`'s sleep.
    @Parameter(title: "Sleep")
    var sleepID: String?

    /// `Baby.uuid` of the baby the widget shows. `nil` (or a baby that's gone) means the baby shown in the app.
    @Parameter(title: "Baby")
    var babyID: String?

    init() {}

    init(start: Bool, sleepID: String? = nil, babyID: String? = nil) {
        self.start = start
        self.sleepID = sleepID
        self.babyID = babyID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        // The widget may be a little out of date (e.g. the partner just started a sleep), so these
        // do nothing when the sleep is already in the state the button asks for.
        let baby = QuickLog.baby(withID: babyID)
        if start {
            _ = try QuickLog.startSleep(for: baby)
        } else {
            _ = QuickLog.endSleep(id: sleepID, for: baby)
        }
        #endif
        return .result()
    }
}

/// The widget's Bottle button: logs the same bottle as last time (formula or breast milk, and the
/// amount), which the button shows.
struct LogBottleButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Bottle from Widget"
    static var isDiscoverable = false

    @Parameter(title: "Formula")
    var formula: Bool

    /// In milliliters. `nil` logs a bottle without an amount.
    @Parameter(title: "Amount")
    var amountML: Double?

    /// `Baby.uuid` of the baby the widget shows. `nil` (or a baby that's gone) means the baby shown in the app.
    @Parameter(title: "Baby")
    var babyID: String?

    init() {}

    init(formula: Bool, amountML: Double?, babyID: String? = nil) {
        self.formula = formula
        self.amountML = amountML
        self.babyID = babyID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try QuickLog.logBottle(formula: formula, ml: amountML, for: QuickLog.baby(withID: babyID))
        #endif
        return .result()
    }
}

/// The widget's Breastfeed button: starts the breastfeeding timer for the widget's baby, on the side
/// MyBaby suggests. Its Live Activity takes over from there (Switch, Pause, Done).
struct StartBreastfeedingButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Breastfeeding from Widget"
    static var isDiscoverable = false

    /// `Baby.uuid` of the baby the widget shows. `nil` (or a baby that's gone) means the baby shown in the app.
    @Parameter(title: "Baby")
    var babyID: String?

    init() {}

    init(babyID: String?) {
        self.babyID = babyID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        QuickLog.startBreastfeeding(for: QuickLog.baby(withID: babyID))
        #endif
        return .result()
    }
}

/// The widget's Medicine button: logs the medicine given last again, with the dose logged last time,
/// which the button shows. It never suggests a dose, and isn't offered while the dose timing the
/// parent entered doesn't allow one yet.
struct LogMedicineButtonIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Medicine from Widget"
    static var isDiscoverable = false

    @Parameter(title: "Medicine")
    var name: String

    /// `Baby.uuid` of the baby the widget shows. `nil` (or a baby that's gone) means the baby shown in the app.
    @Parameter(title: "Baby")
    var babyID: String?

    init() {}

    init(name: String, babyID: String?) {
        self.name = name
        self.babyID = babyID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try QuickLog.logMedicineAgain(name, for: QuickLog.baby(withID: babyID))
        #endif
        return .result()
    }
}

/// The feeding Live Activity's Switch button.
struct SwitchFeedingSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch Breastfeeding Side from Live Activity"
    static var isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        FeedingTimer.shared.switchSide()
        #endif
        return .result()
    }
}

/// The feeding Live Activity's Pause / Resume button.
struct ToggleFeedingPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Breastfeeding from Live Activity"
    static var isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        FeedingTimer.shared.togglePause()
        #endif
        return .result()
    }
}

/// The feeding Live Activity's Done button: saves the breastfeeding and ends the Live Activity.
struct FinishFeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Breastfeeding from Live Activity"
    static var isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        FeedingTimer.shared.finish(context: PersistenceController.shared.viewContext)
        #endif
        return .result()
    }
}
