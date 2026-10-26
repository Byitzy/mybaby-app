import Foundation

// Words for the watch's buttons and confirmations, and how a tap changes what's shown before the iPhone
// confirms it.

extension WatchCommand.Diaper {
    var buttonTitle: String {
        switch self {
        case .wet: return String(localized: "Wet", comment: "Watch button: log a wet diaper")
        case .dirty: return String(localized: "Dirty", comment: "Watch button: log a dirty diaper")
        case .both: return String(localized: "Both", comment: "Watch button: log a wet and dirty diaper")
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
        case .wet: return String(localized: "Pee", comment: "A wet diaper, short")
        case .dirty: return String(localized: "Poop", comment: "A dirty diaper, short")
        case .both: return String(localized: "Pee + poop", comment: "A wet and dirty diaper, short")
        }
    }

    var loggedEmoji: String {
        self == .wet ? "💧" : "💩"
    }

    var accessibilityLabel: String {
        switch self {
        case .wet: return String(localized: "Log a wet diaper")
        case .dirty: return String(localized: "Log a dirty diaper")
        case .both: return String(localized: "Log a wet and dirty diaper")
        }
    }

    var confirmation: String {
        switch self {
        case .wet: return String(localized: "Wet diaper logged")
        case .dirty: return String(localized: "Dirty diaper logged")
        case .both: return String(localized: "Wet + dirty logged")
        }
    }
}

extension WatchCommand.Bottle {
    /// As the app shows it (`FeedingType.title` and `shortTitle`).
    var title: String {
        self == .formula ? String(localized: "Bottle (formula)") : String(localized: "Bottle (breast milk)")
    }

    var shortTitle: String {
        self == .formula
            ? String(localized: "Formula", comment: "A bottle of formula, short")
            : String(localized: "Breast milk", comment: "A bottle of breast milk, short")
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
            let amount = bottlePresets.first(where: { abs($0.ml - ml) < 0.5 })?.title
                ?? String(localized: "\(Int(ml.rounded())) ml", comment: "An amount in milliliters")
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
                    guard minutes > 0 else { return nil }
                    return side == .left
                        ? String(localized: "Left \(minutes)m", comment: "Minutes of breastfeeding on the left side, short")
                        : String(localized: "Right \(minutes)m", comment: "Minutes of breastfeeding on the right side, short")
                }
                snapshot.lastFeed = WidgetSnapshot.Feed(
                    date: timer.startDate,
                    title: String(localized: "Breastfeeding"),
                    shortTitle: String(localized: "Breast", comment: "A breastfeeding, very short"),
                    emoji: "🤱",
                    detail: sides.joined(separator: " · ")
                )
                snapshot.feedingTimer = nil
            }
        case .logMedicine, .sync, .undo, .acknowledgeWakeUp:
            break
        }
        snapshot.mirrorShownBaby(after: command.action, at: date)
        self.snapshot = snapshot
    }
}

extension WidgetSnapshot {
    /// Copies the shown baby's fields (just changed by a tap) into their part of `babies`, which the
    /// complications read, so they show the tap too while the iPhone is out of reach.
    mutating func mirrorShownBaby(after action: WatchCommand.Action, at date: Date, calendar: Calendar = .current) {
        guard let id = babyID, let index = babies?.firstIndex(where: { $0.id == id }), var baby = babies?[index]
        else { return }
        baby.lastFeed = lastFeed
        baby.lastDiaper = lastDiaper
        baby.sleepStart = sleepStart
        baby.sleepID = sleepID
        baby.lastWake = lastWake
        if case .logDiaper = action {
            if calendar.isDate(date, inSameDayAs: baby.countedDay) {
                baby.diapersToday += 1
            } else if date > baby.countedDay {
                // The first one of a new day: the iPhone's next context counts the rest.
                baby.countedDay = calendar.startOfDay(for: date)
                baby.feedsToday = 0
                baby.diapersToday = 1
            }
        }
        babies?[index] = baby
    }
}
