import Foundation

// Words for the watch's buttons and confirmations, and how a tap changes what's shown before the iPhone
// confirms it.

extension WatchCommand.Diaper {
    var buttonTitle: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Both"
        }
    }

    var buttonEmoji: String {
        switch self {
        case .wet: return "💧"
        case .dirty: return "💩"
        case .both: return "💧💩"
        }
    }

    /// As the app shows it (`DiaperType.quickTitle` and `emoji`).
    var loggedTitle: String {
        switch self {
        case .wet: return "Pee"
        case .dirty: return "Poop"
        case .both: return "Pee + poop"
        }
    }

    var loggedEmoji: String {
        self == .wet ? "💧" : "💩"
    }

    var accessibilityLabel: String {
        switch self {
        case .wet: return "Log a wet diaper"
        case .dirty: return "Log a dirty diaper"
        case .both: return "Log a wet and dirty diaper"
        }
    }

    var confirmation: String {
        switch self {
        case .wet: return "Wet diaper logged"
        case .dirty: return "Dirty diaper logged"
        case .both: return "Wet + dirty logged"
        }
    }
}

extension WatchCommand.Bottle {
    /// As the app shows it (`FeedingType.title` and `shortTitle`).
    var title: String {
        self == .formula ? "Bottle (formula)" : "Bottle (breast milk)"
    }

    var shortTitle: String {
        self == .formula ? "Formula" : "Breast milk"
    }
}

extension WatchContext {
    /// Shows a tap's effect right away. The next context from the iPhone replaces it with what was
    /// actually logged.
    mutating func apply(_ command: WatchCommand) {
        guard var snapshot else { return }
        let date = command.date
        switch command.action {
        case .logDiaper(let diaper):
            snapshot.lastDiaper = WidgetSnapshot.Diaper(date: date, title: diaper.loggedTitle, emoji: diaper.loggedEmoji)
        case .logBottle(let type, let ml):
            let amount = bottlePresets.first(where: { abs($0.ml - ml) < 0.5 })?.title ?? "\(Int(ml.rounded())) ml"
            snapshot.lastFeed = WidgetSnapshot.Feed(
                date: date,
                title: type.title,
                shortTitle: type.shortTitle,
                emoji: "🍼",
                detail: amount
            )
            lastBottle = type
        case .startSleep:
            if snapshot.sleepStart == nil {
                snapshot.sleepStart = date
                snapshot.sleepID = nil
            }
        case .endSleep:
            if snapshot.sleepStart != nil {
                snapshot.sleepStart = nil
                snapshot.sleepID = nil
                snapshot.lastWake = date
            }
        case .timerStart(let side):
            if var timer = snapshot.feedingTimer {
                timer.feed(on: side, at: date)
                snapshot.feedingTimer = timer
            } else {
                snapshot.feedingTimer = FeedingTimerState(
                    side: side,
                    at: date,
                    babyID: snapshot.babyID,
                    babyName: snapshot.babyName
                )
            }
        case .timerSwitch:
            snapshot.feedingTimer?.switchSide(at: date)
        case .timerStop:
            if let timer = snapshot.feedingTimer {
                let sides = BreastSide.allCases.compactMap { side -> String? in
                    let minutes = timer.minutes(on: side, at: date)
                    return minutes > 0 ? "\(side.title) \(minutes)m" : nil
                }
                snapshot.lastFeed = WidgetSnapshot.Feed(
                    date: timer.startDate,
                    title: "Breastfeeding",
                    shortTitle: "Breast",
                    emoji: "🤱",
                    detail: sides.joined(separator: " · ")
                )
                snapshot.feedingTimer = nil
            }
        case .logMedicine, .sync, .undo, .acknowledgeWakeUp:
            break
        }
        self.snapshot = snapshot
    }
}
