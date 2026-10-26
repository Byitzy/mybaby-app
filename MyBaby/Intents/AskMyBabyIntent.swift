import AppIntents
import CoreData
import Foundation

// "Ask MyBaby when the baby last ate": one action for every question, so they share one of MyBaby's 10 Siri
// phrases. The answers are spoken, so they're short, and they only say what's in the log.

/// What can be asked. The titles and synonyms are what Siri listens for after "Ask MyBaby" or "Ask MyBaby
/// about".
enum BabyQuestion: String, CaseIterable, AppEnum {
    case lastFeed, lastDiaper, sleep, today, nextDose, onDuty

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Question"
    static var caseDisplayRepresentations: [BabyQuestion: DisplayRepresentation] = [
        .lastFeed: DisplayRepresentation(
            title: "When the baby last ate",
            synonyms: ["when baby last ate", "when my baby last ate", "the last feed", "the last feeding", "feeding"]
        ),
        .lastDiaper: DisplayRepresentation(
            title: "The last diaper",
            synonyms: ["when the baby was last changed", "the last diaper change", "diapers", "the last nappy"]
        ),
        .sleep: DisplayRepresentation(
            title: "How long the baby has slept",
            synonyms: [
                "how long the baby's been asleep", "how long the baby has been asleep", "when the baby last slept",
                "the baby's sleep", "sleep",
            ]
        ),
        .today: DisplayRepresentation(
            title: "Today so far",
            synonyms: ["today", "how today is going", "how the day is going", "the day so far", "today's summary"]
        ),
        .nextDose: DisplayRepresentation(
            title: "The next medicine dose",
            synonyms: ["medicine", "the next dose", "when the next dose is allowed", "when medicine is allowed"]
        ),
        .onDuty: DisplayRepresentation(
            title: "Who's on duty",
            synonyms: ["who's on duty tonight", "who's on duty now", "the night shift", "whose turn it is", "tonight's shifts"]
        ),
    ]
}

/// "Ask MyBaby about today", "When did the baby last eat in MyBaby?"
struct AskMyBabyIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask MyBaby"
    static var description = IntentDescription(
        "Answers from your log: the last feed or diaper, sleep, today so far, when the next medicine dose is allowed by the dose timing you entered, or who's on night duty."
    )
    static var openAppWhenRun = false

    /// The last feed when not asked, so "When did the baby last eat in MyBaby?" works without saying more.
    @Parameter(title: "Question", default: .lastFeed)
    var question: BabyQuestion

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask MyBaby: \(\.$question)") {
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer: String
        if question == .onDuty {
            // The night plan is the same for every baby, and works before one is added.
            answer = BabyAnswers.onDuty()
        } else {
            let target = try SiriBaby.resolve(baby)
            switch question {
            case .lastFeed: answer = BabyAnswers.lastFeed(target)
            case .lastDiaper: answer = BabyAnswers.lastDiaper(target)
            case .sleep: answer = BabyAnswers.sleep(target)
            case .today: answer = BabyAnswers.today(target)
            case .nextDose: answer = BabyAnswers.nextDose(target)
            case .onDuty: answer = BabyAnswers.onDuty()
            }
        }
        return .result(dialog: "\(answer)")
    }
}

/// The spoken answers, for `AskMyBabyIntent` and `LastFeedIntent`.
@MainActor
enum BabyAnswers {
    private static var context: NSManagedObjectContext { QuickLog.context }

    // MARK: Feeds and diapers

    /// "Mavie's last feed was 2 hours, 10 minutes ago, a bottle of formula, 120 ml." While the breastfeeding
    /// timer runs for this baby: how long it's been going, and on which side.
    static func lastFeed(_ baby: Baby) -> String {
        if let timer = FeedingTimer.shared.state, timer.babyID == nil || timer.babyID == baby.uuid?.uuidString {
            let length = QuickLog.spokenDuration(timer.totalSeconds())
            switch (timer.isRunning, timer.side) {
            case (true, .left): return String(localized: "Breastfeeding has been going for \(length), on the left side now.", comment: "Siri. How long, e.g. 12 minutes")
            case (true, .right): return String(localized: "Breastfeeding has been going for \(length), on the right side now.", comment: "Siri. How long, e.g. 12 minutes")
            case (false, .left): return String(localized: "Breastfeeding has been going for \(length), paused on the left side.", comment: "Siri. How long, e.g. 12 minutes")
            case (false, .right): return String(localized: "Breastfeeding has been going for \(length), paused on the right side.", comment: "Siri. How long, e.g. 12 minutes")
            }
        }

        guard let feed = try? context.fetch(baby.entries(Activity.latest(.feeding))).first else {
            return SiriText.sentence(
                for: baby,
                named: { String(localized: "No feeds have been logged yet for \($0).") },
                unnamed: String(localized: "No feeds have been logged yet.")
            )
        }
        let what = describe(feed, unit: SiriText.volumeUnit)
        switch (SiriText.possessiveName(baby), SiriText.ago(feed.startDate)) {
        case let (name?, ago?):
            return String(localized: "\(name)'s last feed was \(ago) ago, \(what).", comment: "Siri. First: the baby's name; second: how long ago, e.g. 2 hours, 10 minutes; third: what it was, e.g. a bottle of formula, 120 ml")
        case let (name?, nil):
            return String(localized: "\(name)'s last feed was just now, \(what).", comment: "Siri. First: the baby's name; second: what it was, e.g. a bottle of formula, 120 ml")
        case let (nil, ago?):
            return String(localized: "The last feed was \(ago) ago, \(what).", comment: "Siri. First: how long ago, e.g. 2 hours, 10 minutes; second: what it was, e.g. a bottle of formula, 120 ml")
        case (nil, nil):
            return String(localized: "The last feed was just now, \(what).", comment: "Siri. What it was, e.g. a bottle of formula, 120 ml")
        }
    }

    /// "a bottle of formula, 120 ml", "breastfeeding, left 10 minutes and right 5 minutes".
    private static func describe(_ feed: Activity, unit: VolumeUnit) -> String {
        switch feed.feedingType {
        case .breast:
            let left = feed.leftMinutes ?? 0
            let right = feed.rightMinutes ?? 0
            guard left > 0 || right > 0 else {
                return String(localized: "breastfeeding", comment: "Siri: what the last feed was, as in: The last feed was 2 hours ago, breastfeeding.")
            }
            let sides = SiriText.breastSides(left: left, right: right)
            return String(localized: "breastfeeding, \(sides)", comment: "Siri: what the last feed was. The sides, e.g. left 10 minutes and right 5 minutes")
        case .formula:
            guard let ml = feed.amountML else {
                return String(localized: "a bottle of formula", comment: "Siri: what the last feed was, as in: The last feed was 2 hours ago, a bottle of formula.")
            }
            let amount = unit.format(ml: ml)
            return String(localized: "a bottle of formula, \(amount)", comment: "Siri: what the last feed was. The amount, e.g. 120 ml")
        case .breastMilkBottle:
            guard let ml = feed.amountML else {
                return String(localized: "a bottle of breast milk", comment: "Siri: what the last feed was, as in: The last feed was 2 hours ago, a bottle of breast milk.")
            }
            let amount = unit.format(ml: ml)
            return String(localized: "a bottle of breast milk, \(amount)", comment: "Siri: what the last feed was. The amount, e.g. 120 ml")
        case .solids:
            let food = feed.foodDescription?.trimmingCharacters(in: .whitespaces) ?? ""
            if food.isEmpty {
                return String(localized: "solids", comment: "Siri: what the last feed was, as in: The last feed was 2 hours ago, solids.")
            }
            return String(localized: "solids: \(food)", comment: "Siri: what the last feed was. What the baby ate, as the parent wrote it")
        case nil:
            return String(localized: "a feeding", comment: "Siri: what the last feed was, when its type isn't known")
        }
    }

    /// "Mavie's last diaper was 40 minutes ago, wet."
    static func lastDiaper(_ baby: Baby) -> String {
        guard let diaper = try? context.fetch(baby.entries(Activity.latest(.diaper))).first else {
            return SiriText.sentence(
                for: baby,
                named: { String(localized: "No diapers have been logged yet for \($0).") },
                unnamed: String(localized: "No diapers have been logged yet.")
            )
        }
        let what: String
        switch diaper.diaperType {
        case .wet: what = String(localized: "wet", comment: "Siri: what the last diaper was, as in: The last diaper was 40 minutes ago, wet.")
        case .dirty: what = String(localized: "dirty", comment: "Siri: what the last diaper was, as in: The last diaper was 40 minutes ago, dirty.")
        case .mixed: what = String(localized: "wet and dirty", comment: "Siri: what the last diaper was, as in: The last diaper was 40 minutes ago, wet and dirty.")
        case .dry: what = String(localized: "dry", comment: "Siri: what the last diaper was, as in: The last diaper was 40 minutes ago, dry.")
        case nil: what = String(localized: "a change", comment: "Siri: what the last diaper was, when its type isn't known")
        }
        switch (SiriText.possessiveName(baby), SiriText.ago(diaper.startDate)) {
        case let (name?, ago?):
            return String(localized: "\(name)'s last diaper was \(ago) ago, \(what).", comment: "Siri. First: the baby's name; second: how long ago, e.g. 40 minutes; third: wet, dirty, wet and dirty, dry or a change")
        case let (name?, nil):
            return String(localized: "\(name)'s last diaper was just now, \(what).", comment: "Siri. First: the baby's name; second: wet, dirty, wet and dirty, dry or a change")
        case let (nil, ago?):
            return String(localized: "The last diaper was \(ago) ago, \(what).", comment: "Siri. First: how long ago, e.g. 40 minutes; second: wet, dirty, wet and dirty, dry or a change")
        case (nil, nil):
            return String(localized: "The last diaper was just now, \(what).", comment: "Siri. Wet, dirty, wet and dirty, dry or a change")
        }
    }

    // MARK: Sleep

    /// "Mavie has been asleep for 1 hour, 20 minutes, since 9:10 PM." or "Mavie is awake. The last sleep
    /// ended 2 hours ago, after 45 minutes."
    static func sleep(_ baby: Baby) -> String {
        let name = SiriText.name(baby)
        if let sleep = QuickLog.ongoingSleep(for: baby) {
            let length = QuickLog.spokenDuration(Date.now.timeIntervalSince(sleep.startDate))
            let time = SiriText.time(sleep.startDate)
            return String(localized: "\(name) has been asleep for \(length), since \(time).", comment: "Siri. First: the baby's name, or The baby; second: how long; third: a time")
        }
        let request = baby.entries(Activity.fetch(
            NSPredicate(format: "kindRaw == %@ AND endDate != nil", ActivityKind.sleep.rawValue),
            limit: 1
        ))
        guard let last = try? context.fetch(request).first, let end = last.endDate else {
            return SiriText.sentence(
                for: baby,
                named: { String(localized: "No sleep has been logged yet for \($0).") },
                unnamed: String(localized: "No sleep has been logged yet.")
            )
        }
        let length = QuickLog.spokenDuration(end.timeIntervalSince(last.startDate))
        guard let ago = SiriText.ago(end) else {
            return String(localized: "\(name) is awake. The last sleep ended just now, after \(length).", comment: "Siri. First: the baby's name, or The baby; second: how long it lasted")
        }
        return String(localized: "\(name) is awake. The last sleep ended \(ago) ago, after \(length).", comment: "Siri. First: the baby's name, or The baby; second: how long ago, e.g. 2 hours; third: how long it lasted")
    }

    // MARK: Today

    /// "So far today, Mavie has had 6 feeds and 7 diapers, 5 wet and 3 dirty, and has slept 9 hours,
    /// 10 minutes." When part of today wasn't logged (`Coverage`), it says the numbers are from what's
    /// logged, since a time nobody logged isn't a time nothing happened.
    static func today(_ baby: Baby, now: Date = .now) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let entries = (try? context.fetch(baby.entries(Activity.since(dayStart)))) ?? []
        let feeds = entries.filter { $0.kind == .feeding }.count
        let diapers = entries.filter { $0.kind == .diaper }
        let wet = diapers.filter(\.isWet).count
        let dirty = diapers.filter(\.isDirty).count

        // Sleeps that reach into today, including one that began last night.
        let sleepRequest = baby.entries(Activity.fetch(NSPredicate(
            format: "kindRaw == %@ AND startDate < %@ AND (endDate == nil OR endDate > %@)",
            ActivityKind.sleep.rawValue, now as NSDate, dayStart as NSDate
        )))
        let sleeps = (try? context.fetch(sleepRequest)) ?? []
        let slept = sleeps.reduce(0.0) { total, sleep in
            let start = max(sleep.startDate, dayStart)
            let end = min(sleep.endDate ?? now, now)
            return total + max(0, end.timeIntervalSince(start))
        }

        let partial = isPartlyUntracked(baby, from: dayStart, now: now, calendar: calendar)
        let name = SiriText.name(baby, capitalized: false)
        let feedText = feeds == 0
            ? String(localized: "no feeds", comment: "Siri, today so far: as in: the baby has had no feeds and 3 diapers")
            : String(localized: "\(feeds) feeds", comment: "Siri, today so far: as in: the baby has had 6 feeds and 7 diapers")
        let diaperText: String
        if diapers.isEmpty {
            diaperText = String(localized: "no diapers", comment: "Siri, today so far: as in: the baby has had 6 feeds and no diapers")
        } else {
            let count = String(localized: "\(diapers.count) diapers", comment: "Siri, today so far: how many diapers")
            let wetText = String(localized: "\(wet) wet", comment: "Siri, today so far: how many of the diapers were wet")
            let dirtyText = String(localized: "\(dirty) dirty", comment: "Siri, today so far: how many of the diapers were dirty")
            diaperText = String(localized: "\(count), \(wetText) and \(dirtyText)", comment: "Siri, today so far: the diapers, e.g. 7 diapers, 5 wet and 3 dirty")
        }
        var text: String
        switch (partial, slept >= 60) {
        case (false, true):
            let sleep = QuickLog.spokenDuration(slept)
            text = String(localized: "So far today, \(name) has had \(feedText) and \(diaperText), and has slept \(sleep).", comment: "Siri. First: the baby's name, or the baby; second: e.g. 6 feeds; third: e.g. 7 diapers, 5 wet and 3 dirty; fourth: how long")
        case (false, false):
            text = String(localized: "So far today, \(name) has had \(feedText) and \(diaperText), and no sleep is logged.", comment: "Siri. First: the baby's name, or the baby; second: e.g. 6 feeds; third: e.g. 7 diapers, 5 wet and 3 dirty")
        case (true, true):
            let sleep = QuickLog.spokenDuration(slept)
            text = String(localized: "From what's logged so far today, \(name) has had \(feedText) and \(diaperText), and has slept \(sleep).", comment: "Siri. First: the baby's name, or the baby; second: e.g. 6 feeds; third: e.g. 7 diapers, 5 wet and 3 dirty; fourth: how long")
        case (true, false):
            text = String(localized: "From what's logged so far today, \(name) has had \(feedText) and \(diaperText), and no sleep is logged.", comment: "Siri. First: the baby's name, or the baby; second: e.g. 6 feeds; third: e.g. 7 diapers, 5 wet and 3 dirty")
        }
        if partial {
            text += " " + String(localized: "Part of today wasn't logged, so there may have been more.")
        }
        return text
    }

    /// Whether any of today so far counts as untracked, from the entries since yesterday and the periods
    /// marked by hand.
    private static func isPartlyUntracked(_ baby: Baby, from dayStart: Date, now: Date, calendar: Calendar) -> Bool {
        guard now > dayStart else { return false }
        let since = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        var activities = (try? context.fetch(baby.entries(Activity.since(since)))) ?? []
        // A sleep that started before yesterday and is still going covers the time too.
        activities += ((try? context.fetch(baby.entries(Activity.ongoingSleep))) ?? []).filter { $0.startDate < since }
        let periods = (try? context.fetch(baby.entries(TrackingPeriod.overlapping(since, now)))) ?? []
        let coverage = Coverage(activities: activities, periods: periods, now: now, calendar: calendar)
        return !coverage.untracked(in: DateInterval(start: dayStart, end: now)).isEmpty
    }

    // MARK: Medicine

    /// "By the dose timing you entered for Mavie: Tylenol, next dose allowed at 4:10 AM. Vitamin D, OK to
    /// give now." Only from the timing the parent entered, in the app's words; it never suggests a dose.
    static func nextDose(_ baby: Baby, now: Date = .now) -> String {
        let schedules = ((try? context.fetch(baby.entries(MedicineSchedule.fetchAll()))) ?? [])
            .filter { !$0.rule.isEmpty }
        guard !schedules.isEmpty else {
            return SiriText.sentence(
                for: baby,
                named: { String(localized: "No dose timing has been entered for \($0). You can add it in MyBaby, from a medicine's Dose timing.") },
                unnamed: String(localized: "No dose timing has been entered. You can add it in MyBaby, from a medicine's Dose timing.")
            )
        }
        var doses: [String: [Date]] = [:]
        for dose in (try? context.fetch(baby.entries(Activity.all(.medication)))) ?? [] {
            doses[MedicineSchedule.key(for: dose.medicationName), default: []].append(dose.startDate)
        }

        // Soonest first; ones it's OK to give now come after the waits.
        let given: [(name: String, next: Date?)] = schedules.compactMap { schedule -> (name: String, next: Date?)? in
            let dates = doses[MedicineSchedule.key(for: schedule.name)] ?? []
            guard !dates.isEmpty else { return nil }
            let name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name: name, next: MedicineTiming.nextAllowed(rule: schedule.rule, doseDates: dates, now: now))
        }
        let lines = given.sorted { ($0.next ?? .distantFuture) < ($1.next ?? .distantFuture) }

        guard !lines.isEmpty else {
            return SiriText.sentence(
                for: baby,
                named: { String(localized: "None of the medicines with dose timing have been given yet for \($0).") },
                unnamed: String(localized: "None of the medicines with dose timing have been given yet.")
            )
        }
        // A sentence for each medicine, read one after the other.
        let spoken = lines.prefix(3).map { line -> String in
            guard let next = line.next else {
                return String(localized: "\(line.name), OK to give now.", comment: "Siri. The medicine's name")
            }
            let text = MedicineTiming.nextDoseText(next, now: now)
            let lowered = text.prefix(1).lowercased() + text.dropFirst()
            return String(localized: "\(line.name), \(lowered).", comment: "Siri. First: the medicine's name; second: e.g. next dose allowed at 4:10 AM")
        }
        let sentences = spoken.joined(separator: " ")
        var text = SiriText.sentence(
            for: baby,
            named: { String(localized: "By the dose timing you entered for \($0): \(sentences)", comment: "Siri. First: the baby's name; second: a sentence for each medicine, e.g. Tylenol, next dose allowed at 4:10 AM.") },
            unnamed: String(localized: "By the dose timing you entered: \(sentences)", comment: "Siri. A sentence for each medicine, e.g. Tylenol, next dose allowed at 4:10 AM.")
        )
        if lines.count > 3 {
            let more = lines.count - 3
            text += " " + String(localized: "And \(more) more in MyBaby.", comment: "Siri: how many more medicines with dose timing there are")
        }
        return text
    }

    // MARK: Night duty

    /// "Maya is on duty now, until 2:00 AM. Then Sam until 7:00 AM." or "Tonight, Maya is on duty from 9:00 PM
    /// to 2:00 AM, then Sam until 7:00 AM."
    static func onDuty(now: Date = .now) -> String {
        let plan = NightPlan.load()
        guard plan.isEnabled else {
            return String(localized: "Night shifts aren't set up. You can plan them in MyBaby, under More, Night shifts.")
        }
        let night = plan.shifts(forNightOf: plan.nightDay(at: now))
        if let shift = plan.shift(at: now) {
            let parent = plan.name(of: shift.parent)
            let until = SiriText.time(shift.end)
            var text = String(localized: "\(parent) is on duty now, until \(until).", comment: "Siri. First: a parent's name; second: a time")
            if let next = night.first(where: { $0.start >= shift.end }) {
                let nextParent = plan.name(of: next.parent)
                let nextUntil = SiriText.time(next.end)
                text += " " + String(localized: "Then \(nextParent) until \(nextUntil).", comment: "Siri: the next night shift. First: a parent's name; second: a time")
            }
            return text
        }
        guard let first = night.first else {
            return String(localized: "There are no night shifts planned.")
        }
        let parent = plan.name(of: first.parent)
        let from = SiriText.time(first.start)
        let to = SiriText.time(first.end)
        if night.count > 1, let last = night.last {
            let lastParent = plan.name(of: last.parent)
            let until = SiriText.time(last.end)
            return String(localized: "Tonight, \(parent) is on duty from \(from) to \(to), then \(lastParent) until \(until).", comment: "Siri. First: a parent's name; second and third: times; fourth: the other parent's name; fifth: a time")
        }
        return String(localized: "Tonight, \(parent) is on duty from \(from) to \(to).", comment: "Siri. First: a parent's name; second and third: times")
    }
}
