import AppIntents
import CoreData
import Foundation

/// Logging without opening the app: shared by Siri and Shortcuts (MyBaby/Intents) and the widget and
/// Live Activity buttons (Shared/ButtonIntents.swift). It does what Today's quick log does: the entry is
/// for the baby shown in the app, credited to the parent on night duty, and saved right away.
///
/// Functions that take a `Baby?` log for that baby instead, e.g. the one a widget was set to in Edit
/// Widget; `nil` means the baby shown in the app.
@MainActor
enum QuickLog {
    static var context: NSManagedObjectContext { PersistenceController.shared.viewContext }

    /// The baby shown in the app.
    static func currentBaby() throws -> Baby {
        guard let baby = Baby.current(in: context) else { throw IntentFailure.noBaby }
        return baby
    }

    /// The baby whose `Baby.uuid` is `id`, or the baby shown in the app when `id` is `nil` or no baby has
    /// it (any more). `nil` only before a baby has been added.
    static func baby(withID id: String?) -> Baby? {
        let babies = (try? context.fetch(Baby.fetchAll())) ?? []
        if let id, let match = babies.first(where: { $0.uuid?.uuidString == id }) {
            return match
        }
        return Baby.preferred(from: babies)
    }

    /// Adds an entry of `kind` for `baby` (the baby shown in the app when `nil`) at `date`, set up by
    /// `configure`, and saves it.
    @discardableResult
    static func insert(
        _ kind: ActivityKind,
        for baby: Baby? = nil,
        at date: Date = .now,
        configure: (Activity) -> Void = { _ in }
    ) throws -> Activity {
        let target = try baby ?? currentBaby()
        let activity = Activity.create(kind, startDate: date, in: context)
        // `create` attached the baby shown in the app; this entry may be for the other twin.
        if activity.baby != target {
            if let store = target.objectID.persistentStore {
                context.assign(activity, to: store)
            }
            activity.baby = target
        }
        configure(activity)
        activity.caregiver = NightPlan.load().shift(at: activity.startDate)?.parent
        save(refreshingFeedingReminder: kind == .feeding)
        return activity
    }

    /// Saves, re-times the feeding reminder if needed, and updates the widgets before the app is
    /// suspended again.
    static func save(refreshingFeedingReminder: Bool = false) {
        context.saveIfChanged()
        if refreshingFeedingReminder {
            NotificationManager.refreshFeedingReminder(context: context)
        }
        WidgetSnapshotWriter.shared.refreshNow()
    }

    // MARK: Diapers

    static func logDiaper(_ type: DiaperType, for baby: Baby? = nil, at date: Date = .now) throws {
        try insert(.diaper, for: baby, at: date) { $0.diaperType = type }
    }

    // MARK: Bottles

    /// Logs a bottle for `baby`: formula or breast milk, with `ml` when known.
    static func logBottle(formula: Bool, ml: Double?, for baby: Baby? = nil, at date: Date = .now) throws {
        // Same bounds as the Apple Watch's bottle buttons.
        let amount = ml.flatMap { $0 > 0 && $0 <= 1000 ? $0 : nil }
        try insert(.feeding, for: baby, at: date) { feed in
            feed.feedingType = formula ? .formula : .breastMilkBottle
            feed.amountML = amount
        }
    }

    // MARK: Breastfeeding

    /// Starts the breastfeeding timer for `baby`, on the side MyBaby suggests from the last feed. Does
    /// nothing while a timer is already going (there's one timer, for one baby at a time): a widget
    /// shows Switch instead, so this only happens when it was out of date.
    static func startBreastfeeding(for baby: Baby? = nil) {
        guard let baby = baby ?? Baby.current(in: context) else { return }
        let timer = FeedingTimer.shared
        guard timer.state == nil else { return }
        let side = FeedingTimer.suggestion(for: baby, in: context)?.side ?? .left
        timer.start(side, baby: baby)
    }

    // MARK: Sleep

    /// `baby`'s sleep that hasn't ended (the shown baby's when `nil`).
    static func ongoingSleep(for baby: Baby? = nil) -> Activity? {
        guard let baby = baby ?? Baby.current(in: context) else { return nil }
        return try? context.fetch(baby.entries(Activity.ongoingSleep)).first
    }

    /// Starts a sleep for `baby`, unless one is already going on. Returns the sleep going on now and
    /// whether it's new.
    static func startSleep(for baby: Baby? = nil) throws -> (sleep: Activity, isNew: Bool) {
        if let sleep = ongoingSleep(for: baby) { return (sleep, false) }
        let sleep = try insert(.sleep, for: baby)
        return (sleep, true)
    }

    /// Ends the sleep with `id` (any baby's), or else `baby`'s (the shown baby's when `nil`), at `date`.
    /// Returns how long it lasted, or `nil` if there was no sleep going on.
    @discardableResult
    static func endSleep(id: String? = nil, for baby: Baby? = nil, at date: Date = .now) -> TimeInterval? {
        let found: Activity?
        if let id, let uuid = UUID(uuidString: id) {
            let request = Activity.fetch(
                NSPredicate(format: "uuid == %@ AND endDate == nil", uuid as NSUUID),
                limit: 1
            )
            found = try? context.fetch(request).first
        } else {
            found = ongoingSleep(for: baby)
        }
        guard let sleep = found else { return nil }
        let end = max(date, sleep.startDate)
        sleep.endDate = end
        save()
        return end.timeIntervalSince(sleep.startDate)
    }

    // MARK: Medicine

    /// Medicine names given to `baby` (the shown baby when `nil`) before, most recent first, without
    /// repeats, each with the dose logged last time.
    static func recentMedicines(for baby: Baby? = nil, limit: Int = 10) -> [(name: String, dosage: String)] {
        guard let baby = baby ?? Baby.current(in: context),
              let doses = try? context.fetch(baby.entries(Activity.all(.medication)))
        else { return [] }
        var seen = Set<String>()
        var result: [(name: String, dosage: String)] = []
        for dose in doses {
            guard let name = dose.medicationName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  seen.insert(name.lowercased()).inserted
            else { continue }
            result.append((name, dose.dosage ?? ""))
            if result.count == limit { break }
        }
        return result
    }

    /// Logs `name` again for `baby`, with the spelling and dose logged last time, as the Apple Watch's
    /// Medicine button does. It never suggests a dose.
    ///
    /// Returns false without logging while the dose timing the parent entered for it doesn't allow
    /// another dose yet, or when it matches a medicine allergy on the baby's list. The widget's button
    /// only shows when neither is so, so this only catches a widget that was out of date; the dose can
    /// still be logged in the app, which says why first.
    @discardableResult
    static func logMedicineAgain(_ name: String, for baby: Baby? = nil, at date: Date = .now) throws -> Bool {
        let target = try baby ?? currentBaby()
        let key = MedicineSchedule.key(for: name)
        guard !key.isEmpty, medicineAllergy(matching: name, for: target) == nil else { return false }
        let doses = ((try? context.fetch(target.entries(Activity.all(.medication)))) ?? [])
            .filter { MedicineSchedule.key(for: $0.medicationName) == key }
        let schedules = (try? context.fetch(target.entries(MedicineSchedule.fetchAll()))) ?? []
        if let rule = schedules.matching(name)?.rule,
           MedicineTiming.nextAllowed(rule: rule, doseDates: doses.map(\.startDate), now: date) != nil {
            return false
        }
        let previous = doses.first
        let spelling = previous?.medicationName?.trimmingCharacters(in: .whitespaces) ?? ""
        try insert(.medication, for: target, at: date) { entry in
            entry.medicationName = spelling.isEmpty ? name.trimmingCharacters(in: .whitespaces) : spelling
            entry.dosage = previous?.dosage ?? ""
        }
        // The "next dose allowed" notification moves with the new dose.
        CareReminders.refreshMedicine(context: context)
        return true
    }

    /// The confirmed or suspected medicine allergy on `baby`'s list that `name` matches, the same
    /// match as the app's warning (`AllergyMatch.medicineMatches`), confirmed ones first. Siri asks
    /// before logging such a medicine, and the widget's button doesn't log it at all.
    static func medicineAllergy(matching name: String, for baby: Baby) -> Allergy? {
        baby.medicineAllergies(matching: name).first
    }

    // MARK: Spoken text

    /// "2 hours, 10 minutes" for Siri to read out.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? Format.duration(seconds)
    }

    /// How many babies there are, so Siri says whose log it is with twins ("Emma's last feed").
    static var babyCount: Int {
        (try? context.count(for: Baby.fetchAll())) ?? 1
    }
}

/// Why an intent couldn't do what was asked, in words Siri can say.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case noBaby
    case invalidAmount
    /// The baby picked in Shortcuts (or said to Siri) isn't in MyBaby any more.
    case babyNotFound
    /// Someone invited to the log as view only (`PersistenceController.canEdit`).
    case viewOnly
    case invalidTemperature
    /// The microphone didn't start, e.g. because MyBaby isn't allowed to use it.
    case cryAlertsDidNotStart

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noBaby: return "Open MyBaby and add your baby first."
        case .invalidAmount: return "That amount doesn't look right. Try again with the amount in milliliters or ounces, as set in MyBaby."
        case .babyNotFound: return "That baby isn't in MyBaby any more. Try again with another name."
        case .viewOnly: return "This log is view only on this iPhone."
        case .invalidTemperature: return "That temperature doesn't look right. Try again in degrees Celsius or Fahrenheit, like 37.5 or 99.5."
        case .cryAlertsDidNotStart: return "Cry alerts couldn't start. Open MyBaby and go to Cry alerts to see why."
        }
    }
}

extension DiaperChoice {
    var diaperType: DiaperType {
        switch self {
        case .wet: return .wet
        case .dirty: return .dirty
        case .both: return .mixed
        }
    }
}
