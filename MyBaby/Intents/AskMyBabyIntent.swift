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
            let side = timer.side.title.lowercased()
            let now = timer.isRunning ? "on the \(side) side now" : "paused on the \(side) side"
            return "Breastfeeding has been going for \(length), \(now)."
        }

        guard let feed = try? context.fetch(baby.entries(Activity.latest(.feeding))).first else {
            return "No feeds have been logged yet\(SiriText.forBaby(baby))."
        }
        return "\(SiriText.subject(baby, "last feed")) was \(SiriText.ago(feed.startDate)), \(describe(feed, unit: SiriText.volumeUnit))."
    }

    /// "a bottle of formula, 120 ml", "breastfeeding, left 10 minutes and right 5 minutes".
    private static func describe(_ feed: Activity, unit: VolumeUnit) -> String {
        switch feed.feedingType {
        case .breast:
            let sides = [("left", feed.leftMinutes ?? 0), ("right", feed.rightMinutes ?? 0)]
                .filter { $0.1 > 0 }
                .map { "\($0.0) \(Format.plural($0.1, "minute"))" }
            return sides.isEmpty ? "breastfeeding" : "breastfeeding, \(sides.joined(separator: " and "))"
        case .breastMilkBottle, .formula:
            let what = feed.feedingType == .formula ? "formula" : "breast milk"
            guard let ml = feed.amountML else { return "a bottle of \(what)" }
            return "a bottle of \(what), \(unit.format(ml: ml))"
        case .solids:
            let food = feed.foodDescription?.trimmingCharacters(in: .whitespaces) ?? ""
            return food.isEmpty ? "solids" : "solids: \(food)"
        case nil:
            return "a feeding"
        }
    }

    /// "Mavie's last diaper was 40 minutes ago, wet."
    static func lastDiaper(_ baby: Baby) -> String {
        guard let diaper = try? context.fetch(baby.entries(Activity.latest(.diaper))).first else {
            return "No diapers have been logged yet\(SiriText.forBaby(baby))."
        }
        let what: String
        switch diaper.diaperType {
        case .wet: what = "wet"
        case .dirty: what = "dirty"
        case .mixed: what = "wet and dirty"
        case .dry: what = "dry"
        case nil: what = "a change"
        }
        return "\(SiriText.subject(baby, "last diaper")) was \(SiriText.ago(diaper.startDate)), \(what)."
    }

    // MARK: Sleep

    /// "Mavie has been asleep for 1 hour, 20 minutes, since 9:10 PM." or "Mavie is awake. The last sleep
    /// ended 2 hours ago, after 45 minutes."
    static func sleep(_ baby: Baby) -> String {
        let name = SiriText.name(baby)
        if let sleep = QuickLog.ongoingSleep(for: baby) {
            let length = QuickLog.spokenDuration(Date.now.timeIntervalSince(sleep.startDate))
            return "\(name) has been asleep for \(length), since \(SiriText.time(sleep.startDate))."
        }
        let request = baby.entries(Activity.fetch(
            NSPredicate(format: "kindRaw == %@ AND endDate != nil", ActivityKind.sleep.rawValue),
            limit: 1
        ))
        guard let last = try? context.fetch(request).first, let end = last.endDate else {
            return "No sleep has been logged yet\(SiriText.forBaby(baby))."
        }
        let length = QuickLog.spokenDuration(end.timeIntervalSince(last.startDate))
        return "\(name) is awake. The last sleep ended \(SiriText.ago(end)), after \(length)."
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
        let feedText = feeds == 0 ? "no feeds" : Format.plural(feeds, "feed")
        let diaperText: String
        if diapers.isEmpty {
            diaperText = "no diapers"
        } else {
            diaperText = "\(Format.plural(diapers.count, "diaper")), \(wet) wet and \(dirty) dirty"
        }
        let start = partial ? "From what's logged so far today" : "So far today"
        var text = "\(start), \(name) has had \(feedText) and \(diaperText)"
        text += slept >= 60 ? ", and has slept \(QuickLog.spokenDuration(slept))." : ", and no sleep is logged."
        if partial {
            text += " Part of today wasn't logged, so there may have been more."
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
            return "No dose timing has been entered\(SiriText.forBaby(baby)). You can add it in MyBaby, from a medicine's Dose timing."
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
            return "None of the medicines with dose timing have been given yet\(SiriText.forBaby(baby))."
        }
        let spoken = lines.prefix(3).map { line -> String in
            guard let next = line.next else { return "\(line.name), OK to give now." }
            let text = MedicineTiming.nextDoseText(next, now: now)
            return "\(line.name), \(text.prefix(1).lowercased() + text.dropFirst())."
        }
        var text = "By the dose timing you entered\(SiriText.forBaby(baby)): \(spoken.joined(separator: " "))"
        if lines.count > 3 {
            text += " And \(lines.count - 3) more in MyBaby."
        }
        return text
    }

    // MARK: Night duty

    /// "Maya is on duty now, until 2:00 AM. Then Sam until 7:00 AM." or "Tonight, Maya is on duty from 9:00 PM
    /// to 2:00 AM, then Sam until 7:00 AM."
    static func onDuty(now: Date = .now) -> String {
        let plan = NightPlan.load()
        guard plan.isEnabled else {
            return "Night shifts aren't set up. You can plan them in MyBaby, under More, Night shifts."
        }
        let night = plan.shifts(forNightOf: plan.nightDay(at: now))
        if let shift = plan.shift(at: now) {
            var text = "\(plan.name(of: shift.parent)) is on duty now, until \(SiriText.time(shift.end))."
            if let next = night.first(where: { $0.start >= shift.end }) {
                text += " Then \(plan.name(of: next.parent)) until \(SiriText.time(next.end))."
            }
            return text
        }
        guard let first = night.first else {
            return "There are no night shifts planned."
        }
        var text = "Tonight, \(plan.name(of: first.parent)) is on duty from \(SiriText.time(first.start))"
        if night.count > 1, let last = night.last {
            text += " to \(SiriText.time(first.end)), then \(plan.name(of: last.parent)) until \(SiriText.time(last.end))."
        } else {
            text += " to \(SiriText.time(first.end))."
        }
        return text
    }
}
