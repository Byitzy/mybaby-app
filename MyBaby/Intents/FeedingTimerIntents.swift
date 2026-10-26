import AppIntents
import Foundation

// Siri and Shortcuts control of the breastfeeding timer. They're `LiveActivityIntent`s so that starting
// the timer from Siri can also start its Live Activity while the app stays in the background. There's one
// timer, for one baby at a time.

/// "Start breastfeeding in MyBaby", or "…on the left".
struct StartBreastfeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Breastfeeding"
    static var description = IntentDescription(
        "Starts the breastfeeding timer. Without a side, it starts on the side MyBaby suggests from the last feed."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Side")
    var side: BreastSide?

    @Parameter(
        title: "Baby",
        description: "Leave it empty for the baby shown in MyBaby.",
        requestValueDialog: IntentDialog("Which baby?")
    )
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start breastfeeding on \(\.$side)") {
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        let timer = FeedingTimer.shared
        if let running = timer.state {
            // A baby named in the request who isn't the one being fed: don't move the other twin's timer.
            if baby?.babyID != nil, let id = running.babyID, id != target.uuid?.uuidString {
                return .result(dialog: "The timer is already running for \(running.babyName). Stop it first.")
            }
            let next = side ?? running.side
            let alreadyThere = running.isRunning && running.side == next
            timer.start(next, baby: target)
            if alreadyThere {
                if next == .left {
                    return .result(dialog: "The timer is already running on the left side.")
                }
                return .result(dialog: "The timer is already running on the right side.")
            }
            if next == .left {
                return .result(dialog: "Now on the left side.")
            }
            return .result(dialog: "Now on the right side.")
        }

        let start = side ?? FeedingTimer.suggestion(for: target, in: QuickLog.context)?.side ?? .left
        timer.start(start, baby: target)
        let text: String
        if start == .left {
            text = SiriText.sentence(
                for: target,
                named: { String(localized: "Started the timer on the left side for \($0).") },
                unnamed: String(localized: "Started the timer on the left side.")
            )
        } else {
            text = SiriText.sentence(
                for: target,
                named: { String(localized: "Started the timer on the right side for \($0).") },
                unnamed: String(localized: "Started the timer on the right side.")
            )
        }
        return .result(dialog: "\(text)")
    }
}

/// "Switch sides" in Shortcuts. Not one of the Siri phrases (MyBaby's 10 are taken); the Live Activity's
/// Switch button does the same.
struct SwitchBreastfeedingSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch Breastfeeding Side"
    static var description = IntentDescription("Switches the breastfeeding timer to the other side.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let timer = FeedingTimer.shared
        guard timer.state != nil else {
            return .result(dialog: "There's no breastfeeding timer running.")
        }
        timer.switchSide()
        switch timer.state?.side {
        case .left?: return .result(dialog: "Switched to the left side.")
        case .right?: return .result(dialog: "Switched to the right side.")
        case nil: return .result(dialog: "Switched to the other side.")
        }
    }
}

/// "Stop breastfeeding in MyBaby." Saves the feed with the minutes on each side, for the baby the timer
/// was started for.
struct StopBreastfeedingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Breastfeeding"
    static var description = IntentDescription("Stops the breastfeeding timer and saves the feed.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let state = FeedingTimer.shared.state else {
            return .result(dialog: "There's no breastfeeding timer running.")
        }
        // The timer's baby, or the baby shown in the app for a timer started before babies were recorded.
        guard let fed = QuickLog.baby(withID: state.babyID) else { throw IntentFailure.noBaby }
        try SiriBaby.checkCanEdit(fed)
        guard let feed = FeedingTimer.shared.finish(context: QuickLog.context) else {
            throw IntentFailure.noBaby
        }
        let sides = SiriText.breastSides(left: feed.leftMinutes ?? 0, right: feed.rightMinutes ?? 0)
        if let name = feed.baby.flatMap({ SiriText.possessiveName($0) }) {
            return .result(dialog: "Saved \(name)'s feed: \(sides).")
        }
        return .result(dialog: "Saved the feed: \(sides).")
    }
}
