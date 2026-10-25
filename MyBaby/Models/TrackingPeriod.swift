import CoreData
import Foundation

/// A stretch of time a parent marked by hand: either *not tracked* (the baby was with a caregiver, at
/// daycare, or nobody logged), *nothing happened* (we were tracking, there was just nothing to log), or
/// *caught up* (the entries were filled in afterwards with Catch up, as approximate ones).
///
/// These override what `Coverage` works out from the entries, so Reports and the PDF can tell "no
/// diapers" apart from "nobody wrote the diapers down". They belong to the baby like every other
/// entry, so they're shared with the partner.
@objc(TrackingPeriod)
final class TrackingPeriod: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var start: Date
    @NSManaged var end: Date
    /// `TrackingPeriodKind`.
    @NSManaged var kindRaw: String
    /// `TrackingPeriodReason`, for a period that wasn't tracked. `nil` when no reason was given.
    @NSManaged var reasonRaw: String?
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    /// A new period for the current baby, saved in the baby's store (so it's shared with the same people).
    @discardableResult
    static func create(
        _ kind: TrackingPeriodKind,
        start: Date,
        end: Date,
        in context: NSManagedObjectContext
    ) -> TrackingPeriod {
        let period = TrackingPeriod(context: context)
        period.uuid = UUID()
        period.kindRaw = kind.rawValue
        period.start = min(start, end)
        period.end = max(start, end)
        period.notes = ""
        Baby.attach(period, in: context) { period.baby = $0 }
        return period
    }

    /// Every period, newest first.
    static func fetchAll() -> NSFetchRequest<TrackingPeriod> {
        let request = NSFetchRequest<TrackingPeriod>(entityName: "TrackingPeriod")
        request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
        return request
    }

    /// Periods that overlap [start, end), newest first.
    static func overlapping(_ start: Date, _ end: Date) -> NSFetchRequest<TrackingPeriod> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "end > %@ AND start < %@", start as NSDate, end as NSDate)
        return request
    }
}

extension TrackingPeriod {
    var kind: TrackingPeriodKind {
        get { TrackingPeriodKind(rawValue: kindRaw) ?? .notTracked }
        set { kindRaw = newValue.rawValue }
    }

    var reason: TrackingPeriodReason? {
        get { reasonRaw.flatMap(TrackingPeriodReason.init(rawValue:)) }
        set { reasonRaw = newValue?.rawValue }
    }

    var interval: DateInterval {
        DateInterval(start: min(start, end), end: max(start, end))
    }

    /// What `Coverage` needs, without Core Data.
    var coveragePeriod: Coverage.Period {
        Coverage.Period(start: start, end: end, isTracked: kind.isTracked)
    }

    /// "with grandma", "at daycare", "forgot to log", or the notes for "Other". Empty when there's nothing to add.
    var reasonPhrase: String {
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .notTracked else { return "" }
        switch reason {
        case .caregiver:
            return note.isEmpty ? "with a caregiver" : "with \(note)"
        case .daycare:
            return "at daycare"
        case .forgot:
            return "forgot to log"
        case .other, nil:
            return note
        }
    }

    /// Whether `reasonPhrase` already shows the notes, so the row doesn't repeat them.
    var reasonUsesNotes: Bool {
        kind == .notTracked && (reason == .caregiver || reason == .other || reason == nil)
    }

    /// "1–5 PM", or "Oct 20, 9 PM – Oct 21, 7 AM" when it runs over midnight.
    func timeRange(calendar: Calendar = .current) -> String {
        let interval = self.interval
        if calendar.isDate(interval.start, inSameDayAs: interval.end) {
            return interval.start.formatted(date: .omitted, time: .shortened)
                + "–" + interval.end.formatted(date: .omitted, time: .shortened)
        }
        let format: Date.FormatStyle = .dateTime.month(.abbreviated).day().hour().minute()
        return "\(interval.start.formatted(format)) – \(interval.end.formatted(format))"
    }

    /// "Not tracked · with grandma · 1–5 PM".
    var summaryLine: String {
        [kind.title, reasonPhrase, timeRange()].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// What a marked period says about the time it covers.
enum TrackingPeriodKind: String, CaseIterable, Identifiable, Codable {
    /// Nobody logged: whatever happened isn't in the app. Reports show these hours as missing.
    case notTracked
    /// We were tracking and there was nothing to log. Counts as tracked.
    case nothingHappened
    /// The entries were added afterwards with Catch up. Counts as tracked; its entries are approximate.
    case caughtUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notTracked: return "Not tracked"
        case .nothingHappened: return "Nothing happened"
        case .caughtUp: return "Caught up"
        }
    }

    /// Whether the time counts as tracked in Reports.
    var isTracked: Bool { self != .notTracked }

    /// SF Symbol for History. Not tracked is slashed, so it isn't told apart by color alone.
    var systemImage: String {
        switch self {
        case .notTracked: return "eye.slash"
        case .nothingHappened: return "checkmark.circle"
        case .caughtUp: return "clock.arrow.circlepath"
        }
    }
}

/// Why a period wasn't tracked.
enum TrackingPeriodReason: String, CaseIterable, Identifiable, Codable {
    case caregiver, daycare, forgot, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caregiver: return "With a caregiver"
        case .daycare: return "At daycare"
        case .forgot: return "Forgot to log"
        case .other: return "Other"
        }
    }
}

// Declared here rather than in Baby.swift, next to the entity it points to.
extension Baby {
    @NSManaged var trackingPeriods: NSSet?
}

// Declared here rather than in Activity.swift, next to Catch up, which sets it.
extension Activity {
    /// Added with Catch up as a rough count rather than logged at the time. Shown with "≈" and
    /// counted in totals like any other entry.
    @NSManaged var isApproximate: Bool
}
