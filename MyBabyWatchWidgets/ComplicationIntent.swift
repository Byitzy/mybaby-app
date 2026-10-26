import AppIntents
import WidgetKit

// What a watch face complication can be set to. watchOS doesn't show these as a form: the face editor
// lists ready-made choices instead (`ComplicationProvider.recommendations()`), built from the babies in
// the last summary the iPhone sent. The choices are kept by watchOS for each complication on this
// watch; nothing is synced, so each parent sets up their own.
//
// Only in the MyBabyWatchWidgets extension. `BabyEntity`, which it uses, is in Shared/.

/// What a complication shows: the details of the iPhone's Lock Screen widgets, which fit there too.
enum ComplicationStat: String, CaseIterable, AppEnum {
    case lastFeed, lastDiaper, sleep, nextDose, onDuty

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Detail"
    static var caseDisplayRepresentations: [ComplicationStat: DisplayRepresentation] = [
        .lastFeed: "Last feed",
        .lastDiaper: "Last diaper",
        .sleep: "Asleep or awake",
        .nextDose: "Next medicine dose",
        .onDuty: "Who's on night duty",
    ]

    /// The same words, for the face editor's list.
    var title: String {
        switch self {
        case .lastFeed: return String(localized: "Last feed")
        case .lastDiaper: return String(localized: "Last diaper")
        case .sleep: return String(localized: "Asleep or awake")
        case .nextDose: return String(localized: "Next medicine dose")
        case .onDuty: return String(localized: "Who's on night duty")
        }
    }

    /// "Mavie: last feed", for the face editor's list with twins: a whole phrase for each detail, so
    /// each language can word it its own way.
    func editorTitle(babyName: String) -> String {
        switch self {
        case .lastFeed: return String(localized: "\(babyName): last feed", comment: "Watch face editor. The baby's name")
        case .lastDiaper: return String(localized: "\(babyName): last diaper", comment: "Watch face editor. The baby's name")
        case .sleep: return String(localized: "\(babyName): asleep or awake", comment: "Watch face editor. The baby's name")
        case .nextDose: return String(localized: "\(babyName): next medicine dose", comment: "Watch face editor. The baby's name")
        case .onDuty: return String(localized: "\(babyName): who's on night duty", comment: "Watch face editor. The baby's name")
        }
    }

    /// Who's on night duty is the same for every baby.
    var isPerBaby: Bool { self != .onDuty }
}

/// A complication's settings. The defaults are the complication as it was before it could be set up:
/// the baby shown on the iPhone, and the last feed.
struct ComplicationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Baby on the Watch Face"
    static var description = IntentDescription("Choose the baby and what the complication shows.")

    /// `nil` or "Follow the iPhone": the baby shown in MyBaby on the iPhone.
    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @Parameter(title: "Show", default: .lastFeed)
    var stat: ComplicationStat

    init() {}

    /// A ready-made choice for the face editor.
    init(baby: BabyEntity, stat: ComplicationStat) {
        self.init()
        self.baby = baby
        self.stat = stat
    }
}
