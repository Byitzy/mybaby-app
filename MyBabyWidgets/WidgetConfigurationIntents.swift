import AppIntents
import WidgetKit

// What a parent can choose in Edit Widget (touch and hold a widget). The choices are kept by iOS for
// each widget on this iPhone; nothing is synced, so each parent sets up their own.
//
// Only in the MyBabyWidgets extension: the configuration intents never run in the app. `BabyEntity`,
// which they use, is in Shared/.

/// Something a widget can show, one line each.
enum WidgetStat: String, CaseIterable, AppEnum {
    case lastFeed, lastDiaper, sleep, onDuty, nextDose, lastPumping, stashTotal, feedsToday, diapersToday

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Detail"
    static var caseDisplayRepresentations: [WidgetStat: DisplayRepresentation] = [
        .lastFeed: "Last feed",
        .lastDiaper: "Last diaper",
        .sleep: "Asleep or awake",
        .onDuty: "Who's on night duty",
        .nextDose: "Next medicine dose",
        .lastPumping: "Last pumping",
        .stashTotal: "Milk stash",
        .feedsToday: "Feeds today",
        .diapersToday: "Diapers today",
    ]
}

/// A button on the medium and large Home Screen widgets. Each logs for the widget's baby.
enum WidgetButton: String, CaseIterable, AppEnum {
    case wet, dirty, both, sleepToggle, bottle, breastfeed, medicine

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Button"
    static var caseDisplayRepresentations: [WidgetButton: DisplayRepresentation] = [
        .wet: "Wet diaper",
        .dirty: "Dirty diaper",
        .both: "Wet and dirty diaper",
        .sleepToggle: "Sleep / Woke up",
        .bottle: "Bottle, same as last time",
        .breastfeed: "Start breastfeeding",
        .medicine: "Medicine given last, same dose",
    ]
}

/// What a Lock Screen widget shows: the details of `WidgetStat` that fit there.
enum LockScreenStat: String, CaseIterable, AppEnum {
    case lastFeed, lastDiaper, sleep, nextDose, onDuty

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Detail"
    static var caseDisplayRepresentations: [LockScreenStat: DisplayRepresentation] = [
        .lastFeed: "Last feed",
        .lastDiaper: "Last diaper",
        .sleep: "Asleep or awake",
        .nextDose: "Next medicine dose",
        .onDuty: "Who's on night duty",
    ]

    var stat: WidgetStat {
        switch self {
        case .lastFeed: return .lastFeed
        case .lastDiaper: return .lastDiaper
        case .sleep: return .sleep
        case .nextDose: return .nextDose
        case .onDuty: return .onDuty
        }
    }
}

/// Edit Widget for the Home Screen widget ("Baby at a glance").
///
/// The defaults are the widget as it was before it could be set up: the baby shown in the app, who's
/// on night duty, the last feed and diaper, asleep or awake, and Wet, Dirty and Sleep buttons.
struct StatusWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Baby at a Glance"
    static var description = IntentDescription("Choose the baby, what the widget shows, and its buttons.")

    /// `nil` or "Follow the app": the baby shown in the app.
    @Parameter(title: "Baby")
    var baby: BabyEntity?

    /// In order. Who's on night duty shows at the top during a night shift; the others are a line each,
    /// as many as fit (`StatusLayout`).
    @Parameter(title: "Show", default: [.onDuty, .lastFeed, .lastDiaper, .sleep])
    var stats: [WidgetStat]

    /// Medium and large widgets only, up to 4.
    @Parameter(title: "Buttons", default: [.wet, .dirty, .sleepToggle])
    var buttons: [WidgetButton]

    init() {}

    /// The same as the parameters' defaults, for the placeholder (which gets no configuration).
    static let defaultStats: [WidgetStat] = [.onDuty, .lastFeed, .lastDiaper, .sleep]
    static let defaultButtons: [WidgetButton] = [.wet, .dirty, .sleepToggle]
}

/// Edit Widget for the Lock Screen widget. The default is the last feed, as before.
struct LockScreenWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Lock Screen"
    static var description = IntentDescription("Choose the baby and what the widget shows.")

    /// `nil` or "Follow the app": the baby shown in the app.
    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @Parameter(title: "Show", default: .lastFeed)
    var stat: LockScreenStat

    init() {}
}
