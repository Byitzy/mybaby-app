import AppIntents
import CoreData
import Foundation

// More things to log by voice: pumping, a bath or a temperature, and a diary note. Like the other logging
// actions (LoggingIntents.swift), each logs for the baby picked or the baby shown in the app, credits the
// parent on night duty, and says what it did.

// MARK: - Pumping

/// "Log pumping in MyBaby." Like the pumping editor: the amount on one side, or the total when no side is
/// given, and optionally the milk into the stash as one bag.
struct LogPumpingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Pumping"
    static var description = IntentDescription(
        "Logs a pumping session with how much you pumped, in the unit chosen in MyBaby (milliliters or ounces). It can also put the milk in the milk stash."
    )
    static var openAppWhenRun = false

    @Parameter(
        title: "Amount",
        description: "In the unit chosen in MyBaby's Settings, milliliters or ounces.",
        requestValueDialog: IntentDialog("How much did you pump?")
    )
    var amount: Double

    @Parameter(title: "Side", description: "Leave it empty for both sides, or one bottle.")
    var side: BreastSide?

    @Parameter(title: "Add to Milk Stash", default: false)
    var addToStash: Bool

    @Parameter(title: "Store In", default: .fridge)
    var storage: MilkStorage

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) pumped on \(\.$side)") {
            \.$addToStash
            \.$storage
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let unit = SiriText.volumeUnit
        // The editor allows up to its maximum on each side.
        let limit = side == nil ? unit.maxValue * 2 : unit.maxValue
        guard amount > 0, amount <= limit else { throw IntentFailure.invalidAmount }
        let target = try SiriBaby.resolveForLogging(baby)
        let context = QuickLog.context
        let ml = unit.toML(amount)

        let session = try QuickLog.insert(.pumping, for: target) { entry in
            switch side {
            case .left?: entry.pumpLeftML = ml
            case .right?: entry.pumpRightML = ml
            case nil: break
            }
            entry.amountML = ml
        }

        let amountText = unit.format(value: amount)
        guard addToStash else {
            let text: String
            switch side {
            case nil:
                text = SiriText.sentence(
                    for: target,
                    named: { String(localized: "Logged \(amountText) pumped for \($0).", comment: "Siri. First: the amount, e.g. 120 ml; second: the baby's name") },
                    unnamed: String(localized: "Logged \(amountText) pumped.", comment: "Siri. The amount, e.g. 120 ml")
                )
            case .left?:
                text = SiriText.sentence(
                    for: target,
                    named: { String(localized: "Logged \(amountText) pumped on the left for \($0).", comment: "Siri. First: the amount, e.g. 120 ml; second: the baby's name") },
                    unnamed: String(localized: "Logged \(amountText) pumped on the left.", comment: "Siri. The amount, e.g. 120 ml")
                )
            case .right?:
                text = SiriText.sentence(
                    for: target,
                    named: { String(localized: "Logged \(amountText) pumped on the right for \($0).", comment: "Siri. First: the amount, e.g. 120 ml; second: the baby's name") },
                    unnamed: String(localized: "Logged \(amountText) pumped on the right.", comment: "Siri. The amount, e.g. 120 ml")
                )
            }
            return .result(dialog: "\(text)")
        }

        let bag = MilkBag.create(amountML: ml, pumpedDate: session.startDate, storage: storage, in: context)
        // `create` attached the baby shown in the app; this bag may be for the other twin.
        if bag.baby != target {
            if let store = target.objectID.persistentStore {
                context.assign(bag, to: store)
            }
            bag.baby = target
        }
        QuickLog.save()
        CareReminders.refreshMilkStash(context: context)
        // Where it went, as a phrase on its own ("in the fridge"), which each language words its own way.
        let place: String
        switch storage {
        case .room: place = String(localized: "at room temperature", comment: "Siri: where pumped milk was put in the stash, as in: added it to the stash at room temperature")
        case .fridge: place = String(localized: "in the fridge", comment: "Siri: where pumped milk was put in the stash, as in: added it to the stash in the fridge")
        case .freezer: place = String(localized: "in the freezer", comment: "Siri: where pumped milk was put in the stash, as in: added it to the stash in the freezer")
        }
        let text: String
        switch side {
        case nil:
            text = String(localized: "Logged \(amountText) pumped, and added it to the stash \(place).", comment: "Siri. First: the amount, e.g. 120 ml; second: where, e.g. in the fridge")
        case .left?:
            text = String(localized: "Logged \(amountText) pumped on the left, and added it to the stash \(place).", comment: "Siri. First: the amount, e.g. 120 ml; second: where, e.g. in the fridge")
        case .right?:
            text = String(localized: "Logged \(amountText) pumped on the right, and added it to the stash \(place).", comment: "Siri. First: the amount, e.g. 120 ml; second: where, e.g. in the fridge")
        }
        return .result(dialog: "\(text)")
    }
}

// MARK: - Bath or temperature

/// A bath or a temperature, for "Log a bath in MyBaby" and "Log a temperature in MyBaby".
enum CareLogChoice: String, CaseIterable, AppEnum {
    case bath, temperature

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bath or Temperature"
    static var caseDisplayRepresentations: [CareLogChoice: DisplayRepresentation] = [
        .bath: DisplayRepresentation(title: "Bath", synonyms: ["bath time"]),
        .temperature: DisplayRepresentation(title: "Temperature", synonyms: ["temp", "fever"]),
    ]
}

/// Celsius or Fahrenheit, when the reading isn't in the unit chosen in MyBaby.
enum TemperatureScale: String, CaseIterable, AppEnum {
    case celsius, fahrenheit

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static var caseDisplayRepresentations: [TemperatureScale: DisplayRepresentation] = [
        .celsius: "Celsius (°C)",
        .fahrenheit: "Fahrenheit (°F)",
    ]

    var unit: TemperatureUnit { self == .celsius ? .celsius : .fahrenheit }
}

/// "Log a bath in MyBaby" or "Log a temperature in MyBaby". One action for both, so they share one of
/// MyBaby's 10 Siri phrases.
///
/// A temperature is in °C or °F as set in MyBaby. The ranges don't overlap (34–43 °C is 93–109 °F), so a
/// reading that only makes sense in the other unit is taken in that one. A fever is flagged the way the
/// temperature editor flags it, with the same words (`FeverGuide.caution`), and nothing more.
struct LogBathOrTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Bath or Temperature"
    static var description = IntentDescription(
        "Logs a bath, or a temperature in °C or °F as set in MyBaby. A fever is flagged the way the app flags it, from the American Academy of Pediatrics' guidance. MyBaby isn't medical advice."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Entry", requestValueDialog: IntentDialog("A bath or a temperature?"))
    var entry: CareLogChoice

    @Parameter(
        title: "Temperature",
        description: "For a temperature: the reading, in °C or °F as set in MyBaby.",
        requestValueDialog: IntentDialog("What was the temperature?")
    )
    var temperature: Double?

    @Parameter(title: "Unit", description: "Leave it empty for the unit chosen in MyBaby.")
    var scale: TemperatureScale?

    @Parameter(title: "Taken", description: "Leave it empty for the way it was taken last time.")
    var method: TemperatureMethod?

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$entry) for \(\.$baby)") {
            \.$temperature
            \.$scale
            \.$method
        }
    }

    /// The wheel's range in the temperature editor.
    private static let celsiusRange = 34.0...43.0

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = try SiriBaby.resolveForLogging(baby)
        guard entry == .temperature else {
            try QuickLog.insert(.bath, for: target)
            let text = SiriText.sentence(
                for: target,
                named: { String(localized: "Logged a bath for \($0).") },
                unnamed: String(localized: "Logged a bath.")
            )
            return .result(dialog: "\(text)")
        }

        guard let reading = temperature else {
            throw $temperature.needsValueError("What was the temperature?")
        }
        guard let unit = Self.unit(for: reading, chosen: scale?.unit) else {
            throw IntentFailure.invalidTemperature
        }
        let celsius = unit.toCelsius(reading)
        let taken = method ?? lastMethod(for: target) ?? .rectal
        try QuickLog.insert(.temperature, for: target) { entry in
            entry.temperatureC = celsius
            entry.temperatureMethod = taken
        }

        let shown = TemperatureUnit.current
        var said = unit.format(celsius: celsius)
        if unit != shown {
            said += " (\(shown.format(celsius: celsius)))"
        }
        var text = SiriText.sentence(
            for: target,
            named: { String(localized: "Logged \(said) for \($0).", comment: "Siri. First: a temperature, e.g. 38.4 °C; second: the baby's name") },
            unnamed: String(localized: "Logged \(said).", comment: "Siri. A temperature, e.g. 38.4 °C")
        )
        if FeverGuide.isFever(celsius: celsius, method: taken) {
            let caution = FeverGuide.caution(
                underThreeMonths: FeverGuide.isUnderThreeMonths(birthDate: target.birthDate, on: .now)
            )
            text += " \(caution.title). \(caution.message)"
        }
        return .result(dialog: "\(text)")
    }

    /// The unit `reading` is in: the one chosen, or MyBaby's, or the other one when only that makes sense.
    /// `nil` when it isn't a body temperature in either.
    private static func unit(for reading: Double, chosen: TemperatureUnit?) -> TemperatureUnit? {
        func fits(_ unit: TemperatureUnit) -> Bool { Self.celsiusRange.contains(unit.toCelsius(reading)) }
        if let chosen { return fits(chosen) ? chosen : nil }
        let preferred = TemperatureUnit.current
        let other: TemperatureUnit = preferred == .celsius ? .fahrenheit : .celsius
        if fits(preferred) { return preferred }
        return fits(other) ? other : nil
    }

    /// How the last temperature was taken, as the editor starts a new one.
    @MainActor
    private func lastMethod(for baby: Baby) -> TemperatureMethod? {
        (try? QuickLog.context.fetch(baby.entries(Activity.latest(.temperature))).first)?.temperatureMethod
    }
}

// MARK: - Diary

/// The kinds of diary entry, for "Write a letter in MyBaby's diary". The synonyms are other words Siri
/// understands.
extension DiaryKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static var caseDisplayRepresentations: [DiaryKind: DisplayRepresentation] = [
        .moment: DisplayRepresentation(title: "Moment", synonyms: ["a moment", "a note"]),
        .learned: DisplayRepresentation(title: "Learned something new", synonyms: ["something new", "something new they learned"]),
        .first: DisplayRepresentation(title: "A first", synonyms: ["a first time"]),
        .funny: DisplayRepresentation(title: "Funny", synonyms: ["something funny", "a funny moment"]),
        .letter: DisplayRepresentation(title: "Letter for later", synonyms: ["a letter", "a letter for later"]),
    ]
}

/// "Add a note in MyBaby": a diary entry with the words said, written by this iPhone's parent, as the diary
/// editor fills in "Written by". A letter for later is to open at 18, as the editor starts one.
///
/// The diary is behind Face ID in the app. Adding to it doesn't need unlocking, and Siri never reads
/// anything back from it, not even the note just added.
struct AddDiaryNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Diary Note"
    static var description = IntentDescription(
        "Adds a note to your baby's diary: a moment, something new they learned, a first, something funny, or a letter for later. The diary is never read aloud."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: IntentDialog("What would you like to write?"))
    var text: String

    @Parameter(title: "Kind", description: "A moment, unless you choose another.")
    var kind: DiaryKind?

    @Parameter(title: "Baby", description: "Leave it empty for the baby shown in MyBaby.")
    var baby: BabyEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to the diary") {
            \.$kind
            \.$baby
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            throw $text.needsValueError("What would you like to write?")
        }
        let target = try SiriBaby.resolveForLogging(baby)
        let context = QuickLog.context
        let chosen = kind ?? .moment

        let note = DiaryEntry.create(chosen, in: context)
        // `create` attached the baby shown in the app; this note may be for the other twin.
        if note.baby != target {
            if let store = target.objectID.persistentStore {
                context.assign(note, to: store)
            }
            note.baby = target
        }
        note.text = words
        note.authorName = Self.defaultAuthor
        if chosen == .letter {
            note.openAtAge = 18
        }
        QuickLog.save()

        if chosen == .letter {
            let text = SiriText.sentence(
                for: target,
                named: { String(localized: "Sealed a letter for \($0), to open at 18.") },
                unnamed: String(localized: "Sealed a letter, to open at 18.")
            )
            return .result(dialog: "\(text)")
        }
        if let name = SiriText.possessiveName(target) {
            return .result(dialog: "Saved to \(name)'s diary.")
        }
        return .result(dialog: "Saved to the diary.")
    }

    /// Like the editor's "Written by": this iPhone's parent (Settings › Parents), or on a shared iPhone
    /// the name last written here.
    @MainActor
    private static var defaultAuthor: String {
        let plan = NightPlan.load()
        switch plan.alarmOwner {
        case .parent1: return plan.name(of: .parent1)
        case .parent2: return plan.name(of: .parent2)
        case .both: return UserDefaults.standard.string(forKey: SettingsKey.diaryAuthor) ?? ""
        }
    }
}
