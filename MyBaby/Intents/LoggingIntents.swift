import AppIntents
import Foundation

// Siri and Shortcuts actions for logging without opening the app. They work the same from the Shortcuts
// app, the Action button, Spotlight and an Apple Watch's Siri, with no extra setup. Each one logs for the
// baby picked (`baby`), or the baby shown in the app when none is, credits the parent on night duty, and
// says what it did. The phrases Siri knows are in MyBabyShortcuts.swift.

/// "Log a wet diaper in MyBaby."
struct LogDiaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Diaper"
    static var description = IntentDescription(
        "Logs a wet, dirty, or wet and dirty diaper. Without a baby, it's for the baby shown in MyBaby."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Diaper", requestValueDialog: IntentDialog("Wet, dirty or both?"))
    var type: DiaperChoice

    @Parameter(
        title: "Baby",
        description: "Leave it empty for the baby shown in MyBaby.",
        requestValueDialog: IntentDialog("Which baby?")
    )
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$type) diaper for \(\.$baby)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        try QuickLog.logDiaper(type.diaperType, for: target)
        let what = type == .both ? "wet and dirty" : type.rawValue
        return .result(dialog: "Logged a \(what) diaper\(SiriText.forBaby(target)).")
    }
}

/// Breast milk or formula, for Siri.
enum BottleChoice: String, CaseIterable, AppEnum {
    case breastMilk, formula

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle"
    static var caseDisplayRepresentations: [BottleChoice: DisplayRepresentation] = [
        .breastMilk: DisplayRepresentation(title: "Breast milk", synonyms: ["breastmilk"]),
        .formula: "Formula",
    ]

    var feedingType: FeedingType {
        self == .breastMilk ? .breastMilkBottle : .formula
    }
}

/// "Log a bottle in MyBaby."
struct LogBottleIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Bottle"
    static var description = IntentDescription(
        "Logs a bottle of breast milk or formula, with the amount if you give one. Without a type, it's the same as the last bottle."
    )
    static var openAppWhenRun = false

    /// When not given, the same as the last bottle.
    @Parameter(title: "Type")
    var type: BottleChoice?

    @Parameter(
        title: "Amount",
        description: "In the unit chosen in MyBaby's Settings, milliliters or ounces."
    )
    var amount: Double?

    @Parameter(
        title: "Baby",
        description: "Leave it empty for the baby shown in MyBaby.",
        requestValueDialog: IntentDialog("Which baby?")
    )
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$type) bottle of \(\.$amount)") {
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let unit = SiriText.volumeUnit
        if let amount, amount <= 0 || amount > unit.maxValue {
            throw IntentFailure.invalidAmount
        }
        let target = try SiriBaby.resolveForLogging(baby)
        let feedingType = type?.feedingType ?? lastBottleType(for: target) ?? .formula
        try QuickLog.insert(.feeding, for: target) { feed in
            feed.feedingType = feedingType
            feed.amountML = amount.map(unit.toML)
        }

        let what = feedingType == .formula ? "formula" : "breast milk"
        let whose = SiriText.forBaby(target)
        if let amount {
            return .result(dialog: "Logged \(unit.format(value: amount)) of \(what)\(whose).")
        }
        return .result(dialog: "Logged a bottle of \(what)\(whose).")
    }

    @MainActor
    private func lastBottleType(for baby: Baby) -> FeedingType? {
        let request = baby.entries(Activity.fetch(
            NSPredicate(
                format: "kindRaw == %@ AND feedingTypeRaw IN %@",
                ActivityKind.feeding.rawValue,
                [FeedingType.breastMilkBottle.rawValue, FeedingType.formula.rawValue] as NSArray
            ),
            limit: 1
        ))
        return (try? QuickLog.context.fetch(request).first)?.feedingType
    }
}

// MARK: - Sleep

/// Asleep or awake, for "MyBaby, the baby's asleep" and "The baby woke up in MyBaby". The synonyms are
/// other words Siri understands.
enum SleepChange: String, CaseIterable, AppEnum {
    case asleep, awake

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Asleep or Awake"
    static var caseDisplayRepresentations: [SleepChange: DisplayRepresentation] = [
        .asleep: DisplayRepresentation(
            title: "Asleep",
            synonyms: ["fell asleep", "sleeping", "went to sleep", "napping", "down for a nap"]
        ),
        .awake: DisplayRepresentation(title: "Awake", synonyms: ["woke up", "up", "awake now"]),
    ]
}

/// "MyBaby, the baby's asleep" / "The baby woke up in MyBaby": starts or ends the sleep timer. Starting
/// one also starts the sleep Live Activity, which is why it's a `LiveActivityIntent`.
struct SleepOrWakeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Asleep or Awake"
    static var description = IntentDescription(
        "Starts the sleep timer when your baby falls asleep, and stops it when they wake up."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Asleep or Awake", requestValueDialog: IntentDialog("Is the baby asleep or awake?"))
    var change: SleepChange

    @Parameter(
        title: "Baby",
        description: "Leave it empty for the baby shown in MyBaby.",
        requestValueDialog: IntentDialog("Which baby?")
    )
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$baby) as \(\.$change)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        let dialog: String
        if change == .asleep {
            dialog = try SleepDialogs.start(for: target)
        } else {
            dialog = SleepDialogs.end(for: target)
        }
        return .result(dialog: "\(dialog)")
    }
}

/// "Start sleep" in Shortcuts. Siri's phrases use `SleepOrWakeIntent`; this one is kept for shortcuts made
/// with it, and as a plain action in the Shortcuts app.
struct StartSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Sleep"
    static var description = IntentDescription("Starts the sleep timer. Use End Sleep when your baby wakes up.")
    static var openAppWhenRun = false

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start sleep for \(\.$baby)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        let dialog = try SleepDialogs.start(for: target)
        return .result(dialog: "\(dialog)")
    }
}

/// "End sleep" in Shortcuts, like `StartSleepIntent`.
struct EndSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Sleep"
    static var description = IntentDescription("Stops the sleep timer when your baby wakes up.")
    static var openAppWhenRun = false

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("End sleep for \(\.$baby)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        return .result(dialog: "\(SleepDialogs.end(for: target))")
    }
}

/// Starting and ending a sleep, and what Siri says, for the sleep actions above.
@MainActor
private enum SleepDialogs {
    static func start(for baby: Baby) throws -> String {
        let (sleep, isNew) = try QuickLog.startSleep(for: baby)
        if isNew {
            return "Sleep timer started\(SiriText.forBaby(baby)). Sweet dreams."
        }
        return "\(SiriText.name(baby)) has been asleep since \(SiriText.time(sleep.startDate))."
    }

    static func end(for baby: Baby) -> String {
        guard let duration = QuickLog.endSleep(for: baby) else {
            return "There's no sleep timer running\(SiriText.forBaby(baby))."
        }
        return "Got it. \(SiriText.name(baby)) slept \(QuickLog.spokenDuration(duration))."
    }
}

// MARK: - Medicine

/// Medicine names given before, for picking in Siri and Shortcuts.
struct RecentMedicineOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        QuickLog.recentMedicines().map(\.name)
    }
}

/// "Log medicine in MyBaby." Records a dose; it doesn't suggest one.
struct LogMedicineIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Medicine"
    static var description = IntentDescription(
        "Records a medicine your baby was given. Without a dose, it uses the dose you logged last time for that medicine. Always follow your pediatrician's dosing instructions."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Medicine", optionsProvider: RecentMedicineOptions())
    var name: String

    @Parameter(title: "Dose", description: "As written on the label, e.g. \"1 drop\" or \"2.5 ml\".")
    var dosage: String?

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$name)") {
            \.$dosage
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let medicine = name.trimmingCharacters(in: .whitespaces)
        guard !medicine.isEmpty else {
            throw $name.needsValueError("Which medicine?")
        }
        let target = try SiriBaby.resolveForLogging(baby)
        let context = QuickLog.context
        // The spelling and dose used before, so the log reads the same as when it was entered by hand.
        let previous = QuickLog.recentMedicines(for: target, limit: 50)
            .first { $0.name.lowercased() == medicine.lowercased() }
        let dose = dosage?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? previous?.dosage.nilIfEmpty
        let logged = previous?.name ?? medicine

        // Like the app, it never blocks a dose; it only says when the timing the parent entered didn't allow one yet.
        let key = MedicineSchedule.key(for: logged)
        let earlier = ((try? context.fetch(target.entries(Activity.all(.medication)))) ?? [])
            .filter { MedicineSchedule.key(for: $0.medicationName) == key }
            .map(\.startDate)
        let schedules = (try? context.fetch(target.entries(MedicineSchedule.fetchAll()))) ?? []
        let tooSoon = schedules.matching(logged).map {
            MedicineTiming.nextAllowed(rule: $0.rule, doseDates: earlier) != nil
        } ?? false

        try QuickLog.insert(.medication, for: target) { entry in
            entry.medicationName = logged
            entry.dosage = dose ?? ""
        }
        // The "next dose allowed" notification moves with the new dose.
        CareReminders.refreshMedicine(context: context)

        var text = dose.map { "Logged \(logged), \($0)" } ?? "Logged \(logged)"
        text += SiriText.forBaby(target) + "."
        if tooSoon {
            text += " That's sooner than the dose timing you entered for it."
        }
        return .result(dialog: "\(text)")
    }
}

// MARK: - Last feed

/// "When did my baby last eat?" Kept for shortcuts made with it; Siri's phrases now go to
/// `AskMyBabyIntent`, which answers the same, and more.
struct LastFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "When Did Baby Last Eat?"
    static var description = IntentDescription("Tells you how long ago the last feed was, and what it was.")
    static var openAppWhenRun = false

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("When did \(\.$baby) last eat?")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolve(baby)
        return .result(dialog: "\(BabyAnswers.lastFeed(target))")
    }
}

extension String {
    /// `nil` for an empty string.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
