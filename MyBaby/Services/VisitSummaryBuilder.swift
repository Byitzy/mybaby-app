import CoreData
import Foundation

/// What's happened since the last checkup, to bring to the next one: feeds, diapers, sleep,
/// growth, temperatures, medicine and vaccines, plus the questions to ask.
struct VisitSummary {
    let babyName: String
    let birthDate: Date?
    /// Shows the time of birth next to the date, when it was entered (for the record only).
    let hasBirthTime: Bool
    let appointmentTitle: String
    let appointmentDate: Date
    let provider: String

    /// The period covered: from the previous appointment (or 30 days back) to this one, or to now
    /// while it's still ahead.
    let start: Date
    let end: Date
    /// The title of the appointment the period starts from (empty when it has none), if there was one.
    let previousAppointment: String?

    let summaries: [DaySummary]
    let averages: ReportAverages
    let longestSleep: TimeInterval?
    /// Dirty diapers with a color pediatricians commonly ask about.
    let flaggedDiapers: [FlaggedDiaper]
    let weight: GrowthChange?
    let length: GrowthChange?
    /// Entries of the temperature kind, when the app has one.
    let temperatures: [Activity]
    let medicines: [MedicineGiven]
    let vaccinesGiven: [Vaccine]
    let vaccinesDue: [Vaccine]
    let questions: [VisitQuestion]
    /// What the doctor said at the previous appointment (its "How did it go?" recap), if anything.
    var lastVisitNotes: String = ""
    /// Every allergy on the list, confirmed first (see `sortedForDisplay()`).
    var allergies: [Allergy] = []
    /// Reactions logged in the period, newest first.
    var reactions: [AllergyReaction] = []
    /// The latest head circumference, like `weight` and `length`.
    var headCircumference: GrowthChange? = nil
    /// Where the visit is: "Maple Street Pediatrics, 12 Main Street, Springfield". Empty when no
    /// location was entered; just the name for a place that was typed in.
    var place: String = ""

    var days: Int { summaries.count }

    struct FlaggedDiaper: Identifiable {
        let date: Date
        let color: PoopColor
        var id: Date { date }
    }

    /// The latest weight or length (kg or cm), the change since the one before the period, and
    /// where it falls on the WHO chart.
    struct GrowthChange {
        let value: Double
        let date: Date
        let previousValue: Double?
        let previousDate: Date?
        let percentile: GrowthPercentile?

        var change: Double? { previousValue.map { value - $0 } }
    }

    /// Doses of one medicine in the period.
    struct MedicineGiven: Identifiable {
        let name: String
        let doses: Int
        let lastGiven: Date
        let lastDose: String
        var id: String { name }
    }

    /// "Since the 2-month checkup on Aug 12" or "Last 30 days".
    var periodTitle: String {
        if let previousAppointment {
            let day = start.formatted(.dateTime.month(.abbreviated).day())
            return previousAppointment.isEmpty
                ? String(localized: "Since the last appointment on \(day)", comment: "Visit summary period; a day like Aug 12")
                : String(
                    localized: "Since the \(previousAppointment) on \(day)",
                    comment: "Visit summary period; the previous appointment's title, like 2-month checkup, then a day like Aug 12"
                )
        }
        return days == 1
            ? String(localized: "Last 1 day", comment: "Visit summary period")
            : String(localized: "Last \(days) days", comment: "Visit summary period; a number of days")
    }
}

enum VisitSummaryBuilder {
    /// How far back to look when there's no earlier appointment.
    static let defaultDays = 30

    /// The summary for `appointment`. `questions` overrides the saved ones, e.g. while they're
    /// being edited. `nil` when the appointment has no baby (it's being deleted).
    static func summary(
        for appointment: Appointment,
        questions: [VisitQuestion]? = nil,
        in context: NSManagedObjectContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> VisitSummary? {
        guard let baby = appointment.baby else { return nil }

        let end = min(appointment.date, now)
        let appointments = (try? context.fetch(baby.entries(Appointment.fetchAll()))) ?? []
        // A cancelled visit didn't happen, so the period runs from the last one that did.
        let previous = appointments.last { $0.date < end && $0 != appointment && !$0.isCancelled }
        let start = previous?.date ?? ReportBuilder.startDay(days: defaultDays, now: end, calendar: calendar)

        let firstDay = calendar.startOfDay(for: start)
        let days = max(1, (calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: end)).day ?? 0) + 1)
        // A day early, so a sleep that began the evening before is counted.
        let fetchFrom = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        let request = baby.entries(Activity.fetch(
            NSPredicate(format: "startDate >= %@ AND startDate <= %@", fetchFrom as NSDate, end as NSDate),
            newestFirst: false
        ))
        let activities = (try? context.fetch(request)) ?? []
        let inPeriod = activities.filter { $0.startDate >= start }

        // How much of each day was tracked, so untracked days don't pull the averages down.
        let periods = (try? context.fetch(baby.entries(TrackingPeriod.overlapping(fetchFrom, end)))) ?? []
        let coverage = Coverage(activities: activities, periods: periods, now: end, calendar: calendar)
        let summaries = ReportBuilder.summaries(for: activities, days: days, now: end, calendar: calendar, coverage: coverage)

        let longestSleep = inPeriod
            .filter { $0.kind == .sleep && $0.endDate != nil }
            .compactMap { $0.duration(now: end) }
            .filter { $0 > 0 && $0 <= PatternFinder.maxSleep }
            .max()

        let flagged = inPeriod.compactMap { activity -> VisitSummary.FlaggedDiaper? in
            guard activity.kind == .diaper, activity.isDirty,
                  let color = activity.poopColor, color.needsAttention
            else { return nil }
            return VisitSummary.FlaggedDiaper(date: activity.startDate, color: color)
        }

        // By its stored name so this works whether or not the app has a temperature kind yet.
        let temperatures = inPeriod.filter { $0.kindRaw == "temperature" }

        let growthEntries = (try? context.fetch(baby.entries(GrowthEntry.fetchAll()))) ?? []
        let growth = GrowthReading.all(entries: growthEntries, appointments: appointments)
        let vaccines = (try? context.fetch(baby.entries(Vaccine.fetchAll()))) ?? []

        return VisitSummary(
            babyName: baby.displayName,
            birthDate: baby.birthDate,
            hasBirthTime: baby.hasBirthTime,
            appointmentTitle: appointment.title.isEmpty
                ? String(localized: "Appointment", comment: "Shown for an appointment with no title")
                : appointment.title,
            appointmentDate: appointment.date,
            provider: appointment.provider,
            start: start,
            end: end,
            previousAppointment: previous.map(\.title),
            summaries: summaries,
            averages: ReportAverages(summaries, calendar: calendar),
            longestSleep: longestSleep,
            flaggedDiapers: flagged,
            weight: growthChange(growth, baby: baby, measure: .weight, from: start, to: end),
            length: growthChange(growth, baby: baby, measure: .length, from: start, to: end),
            temperatures: temperatures,
            medicines: medicines(inPeriod),
            vaccinesGiven: vaccines.filter { $0.isGiven && $0.date >= start && $0.date <= end },
            vaccinesDue: vaccines.filter { !$0.isGiven },
            questions: questions ?? appointment.questionList,
            lastVisitNotes: (previous?.visitNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            allergies: baby.allergyList(),
            reactions: baby.allergyReactionList(since: start).filter { $0.date <= end },
            headCircumference: growthChange(growth, baby: baby, measure: .headCircumference, from: start, to: end),
            place: appointment.placeLine
        )
    }

    /// The latest measurement up to `end`, compared with the last one before the period (or the
    /// first one in it).
    private static func growthChange(
        _ growth: [GrowthReading], baby: Baby, measure: GrowthMeasure, from start: Date, to end: Date
    ) -> VisitSummary.GrowthChange? {
        let readings = growth.compactMap { reading -> (date: Date, value: Double)? in
            guard let value = reading.value(measure), reading.date <= end else { return nil }
            return (date: reading.date, value: value)
        }
        guard let latest = readings.last else { return nil }
        let earlier = readings.dropLast()
        let previous = earlier.last { $0.date < start } ?? earlier.first
        return VisitSummary.GrowthChange(
            value: latest.value,
            date: latest.date,
            previousValue: previous?.value,
            previousDate: previous?.date,
            percentile: baby.growthPercentile(measure, value: latest.value, on: latest.date)
        )
    }

    /// Each medicine given in the period with how many doses, most recent first.
    private static func medicines(_ activities: [Activity]) -> [VisitSummary.MedicineGiven] {
        let doses = activities.filter { $0.kind == .medication }
        let byName = Dictionary(grouping: doses) { $0.title }
        return byName.compactMap { name, doses -> VisitSummary.MedicineGiven? in
            guard let last = doses.max(by: { $0.startDate < $1.startDate }) else { return nil }
            return VisitSummary.MedicineGiven(
                name: name,
                doses: doses.count,
                lastGiven: last.startDate,
                lastDose: last.dosage ?? ""
            )
        }
        .sorted { $0.lastGiven > $1.lastGiven }
    }
}
