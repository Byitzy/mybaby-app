import CoreData
import Foundation

/// A single logged event: a feeding, diaper change, sleep, bath or medicine dose.
///
/// One entity covers every time-based event so the timeline, history and reports can
/// work over a single fetch. Fields that only apply to one kind are optional.
/// Stored with Core Data so it can sync and be shared between parents through iCloud.
@objc(Activity)
final class Activity: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var kindRaw: String
    @NSManaged var startDate: Date
    /// When a sleep ended. `nil` on a sleep means the baby is still asleep.
    @NSManaged var endDate: Date?
    @NSManaged var notes: String

    // Feeding
    @NSManaged var feedingTypeRaw: String?
    @NSManaged var amountMLNumber: NSNumber?
    @NSManaged var leftMinutesNumber: NSNumber?
    @NSManaged var rightMinutesNumber: NSNumber?
    @NSManaged var foodDescription: String?

    // Diaper
    @NSManaged var diaperTypeRaw: String?
    @NSManaged var poopColorRaw: String?
    @NSManaged var poopConsistencyRaw: String?

    // Medication
    @NSManaged var medicationName: String?
    @NSManaged var dosage: String?

    /// Which parent took care of it, when the night plan is on.
    @NSManaged var caregiverRaw: String?

    @NSManaged var baby: Baby?

    /// A new activity for the current baby, saved in the same place (and so shared with the same people) as the baby.
    @discardableResult
    static func create(_ kind: ActivityKind, startDate: Date = .now, in context: NSManagedObjectContext) -> Activity {
        let activity = Activity(context: context)
        activity.uuid = UUID()
        activity.kindRaw = kind.rawValue
        activity.startDate = startDate
        activity.notes = ""
        Baby.attach(activity, in: context) { activity.baby = $0 }
        return activity
    }

    var amountML: Double? {
        get { amountMLNumber?.doubleValue }
        set { amountMLNumber = newValue.map { NSNumber(value: $0) } }
    }

    var leftMinutes: Int? {
        get { leftMinutesNumber?.intValue }
        set { leftMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }

    var rightMinutes: Int? {
        get { rightMinutesNumber?.intValue }
        set { rightMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }
}

extension Activity {
    var kind: ActivityKind {
        ActivityKind(rawValue: kindRaw) ?? .feeding
    }

    var feedingType: FeedingType? {
        get { feedingTypeRaw.flatMap(FeedingType.init(rawValue:)) }
        set { feedingTypeRaw = newValue?.rawValue }
    }

    var diaperType: DiaperType? {
        get { diaperTypeRaw.flatMap(DiaperType.init(rawValue:)) }
        set { diaperTypeRaw = newValue?.rawValue }
    }

    var poopColor: PoopColor? {
        get { poopColorRaw.flatMap(PoopColor.init(rawValue:)) }
        set { poopColorRaw = newValue?.rawValue }
    }

    var poopConsistency: PoopConsistency? {
        get { poopConsistencyRaw.flatMap(PoopConsistency.init(rawValue:)) }
        set { poopConsistencyRaw = newValue?.rawValue }
    }

    var caregiver: Parent? {
        get { caregiverRaw.flatMap(Parent.init(rawValue:)) }
        set { caregiverRaw = newValue?.rawValue }
    }

    var isOngoing: Bool {
        kind == .sleep && endDate == nil
    }

    /// Length of a sleep, counting up to `now` while it is still going.
    func duration(now: Date = .now) -> TimeInterval? {
        guard kind == .sleep else { return nil }
        return (endDate ?? now).timeIntervalSince(startDate)
    }

    var breastMinutes: Int {
        (leftMinutes ?? 0) + (rightMinutes ?? 0)
    }

    var isWet: Bool {
        diaperType == .wet || diaperType == .mixed
    }

    var isDirty: Bool {
        diaperType == .dirty || diaperType == .mixed
    }

    var emoji: String {
        switch kind {
        case .feeding: return feedingType?.emoji ?? kind.emoji
        case .diaper: return diaperType?.emoji ?? kind.emoji
        default: return kind.emoji
        }
    }

    var title: String {
        switch kind {
        case .feeding:
            return feedingType?.title ?? kind.title
        case .diaper:
            return diaperType.map { "\($0.title) diaper" } ?? kind.title
        case .medication:
            let name = medicationName?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? kind.title : name
        default:
            return kind.title
        }
    }

    func detail(unit: VolumeUnit, now: Date = .now) -> String {
        var parts: [String] = []
        switch kind {
        case .feeding:
            switch feedingType {
            case .breast:
                if let left = leftMinutes, left > 0 { parts.append("Left \(left)m") }
                if let right = rightMinutes, right > 0 { parts.append("Right \(right)m") }
            case .solids:
                if let food = foodDescription, !food.isEmpty { parts.append(food) }
                if !allergens.isEmpty { parts.append("Allergens: \(allergens.map(\.name).joined(separator: ", "))") }
                if let amountML { parts.append(unit.format(ml: amountML)) }
            default:
                if let amountML { parts.append(unit.format(ml: amountML)) }
            }
        case .diaper:
            if isDirty {
                if let poopColor { parts.append("\(poopColor.emoji) \(poopColor.title)") }
                if let poopConsistency { parts.append(poopConsistency.title) }
            }
        case .sleep:
            if let duration = duration(now: now) {
                parts.append(isOngoing ? "Sleeping · \(Format.duration(duration))" : Format.duration(duration))
            }
        case .medication:
            if let dosage, !dosage.isEmpty { parts.append(dosage) }
        case .bath:
            break
        case .pumping:
            parts += pumpingDetailParts(unit: unit)
        case .temperature:
            parts += temperatureDetailParts()
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Common fetches

extension Activity {
    static func fetch(
        _ predicate: NSPredicate? = nil,
        newestFirst: Bool = true,
        limit: Int = 0
    ) -> NSFetchRequest<Activity> {
        let request = NSFetchRequest<Activity>(entityName: "Activity")
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: !newestFirst)]
        request.fetchLimit = limit
        return request
    }

    /// The most recent activity of a kind.
    static func latest(_ kind: ActivityKind) -> NSFetchRequest<Activity> {
        fetch(NSPredicate(format: "kindRaw == %@", kind.rawValue), limit: 1)
    }

    /// A sleep that has been started but not ended.
    static var ongoingSleep: NSFetchRequest<Activity> {
        fetch(NSPredicate(format: "kindRaw == %@ AND endDate == nil", ActivityKind.sleep.rawValue), limit: 1)
    }

    static func all(_ kind: ActivityKind) -> NSFetchRequest<Activity> {
        fetch(NSPredicate(format: "kindRaw == %@", kind.rawValue))
    }

    /// Everything that started at or after `date`, oldest first.
    static func since(_ date: Date) -> NSFetchRequest<Activity> {
        fetch(NSPredicate(format: "startDate >= %@", date as NSDate), newestFirst: false)
    }

    /// Everything that started within [start, end), newest first.
    static func between(_ start: Date, _ end: Date) -> NSFetchRequest<Activity> {
        fetch(NSPredicate(format: "startDate >= %@ AND startDate < %@", start as NSDate, end as NSDate))
    }
}
