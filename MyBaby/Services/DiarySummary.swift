import CoreData
import Foundation

/// What happened in one week or month of the baby's life, worked out on the fly from the log. Nothing
/// here is stored, so it's always up to date with the latest entries, the partner's included.
///
/// Days nobody logged are said honestly: `daysLogged` of `daysSoFar`, using `Coverage` like Reports
/// do, and averages come from fully tracked days (`ReportAverages`), so a missing day is never
/// counted as a day with no feeds.
struct DiarySummary {
    let period: DiaryPeriod
    /// One per day of the period that has started, oldest first, each with its coverage.
    let days: [DaySummary]
    let averages: ReportAverages

    /// Finished days with something tracked (fully or partly).
    let daysLogged: Int
    /// Of those, the ones only partly tracked.
    let daysPartlyLogged: Int
    /// Finished days of the period so far (all of them once it's over).
    let daysSoFar: Int
    /// Whether the period is still going on.
    let isInProgress: Bool

    let feeds: Int
    let diapers: Int
    let wetDiapers: Int
    let dirtyDiapers: Int
    /// Diapers a day, from the same days as `averages` (a mixed diaper counts once). `nil` without any.
    let diapersPerDay: Double?
    let sleepSeconds: TimeInterval
    /// The longest single sleep that started in the period.
    let longestSleep: TimeInterval?
    let baths: Int

    /// Measurements taken in the period, oldest first.
    let growth: [GrowthEntry]
    /// The last measurement before the period, to show the change from.
    let growthBefore: GrowthEntry?
    let milestones: [Milestone]
    let vaccines: [Vaccine]
    let appointments: [Appointment]
    /// Diary entries dated in the period, newest first, letters included (they're shown sealed).
    let entries: [DiaryEntry]
    /// The parents' notes about this period, oldest first.
    let notes: [DiaryEntry]
    /// Photos from the period's diary entries and milestones.
    let photoCount: Int

    /// Nothing at all was tracked: no feeds, diapers or sleep to speak of.
    var hasNoLog: Bool { daysLogged == 0 && !days.contains { $0.hasData } }

    /// "Logged 5 of 7 days", "Logged all 30 days", "Logged 3 of 4 days so far".
    var coverageText: String {
        if daysSoFar == 0 { return isInProgress ? "Just started" : "Nothing logged" }
        let soFar = isInProgress ? " so far" : ""
        if daysLogged == 0 { return "No days logged\(soFar)" }
        if daysLogged == daysSoFar, daysPartlyLogged == 0 {
            return daysSoFar == 1 ? "Logged the whole day\(soFar)" : "Logged all \(daysSoFar) days\(soFar)"
        }
        var text = "Logged \(daysLogged) of \(Format.plural(daysSoFar, "day"))\(soFar)"
        if daysPartlyLogged > 0 {
            text += " (\(daysPartlyLogged) only partly)"
        }
        return text
    }

    /// Under the numbers when some days weren't logged, so totals aren't read as the whole story.
    var coverageNote: String? {
        guard daysLogged > 0, daysLogged < daysSoFar || daysPartlyLogged > 0 else { return nil }
        return "Totals only count what was logged. Days that weren't logged aren't counted as zero, and averages use fully logged days."
    }
}

enum DiarySummaryBuilder {
    /// The summary of `period` for `baby`, fetched from `context`.
    @MainActor
    static func summary(
        for period: DiaryPeriod,
        baby: Baby,
        context: NSManagedObjectContext,
        now: Date = .now,
        plan: NightPlan = .load(),
        calendar: Calendar = .current
    ) -> DiarySummary {
        // A day early, so a sleep that began the night before (and the gap before the first entry) is seen.
        let fetchStart = calendar.date(byAdding: .day, value: -1, to: period.start) ?? period.start
        let activities = fetch(baby.entries(Activity.between(fetchStart, period.end)), in: context)
        let periods = fetch(baby.entries(TrackingPeriod.overlapping(fetchStart, period.end)), in: context)
        let growthAll = fetch(baby.entries(GrowthEntry.fetchAll()), in: context)
        let milestones = fetch(baby.entries(Milestone.fetchAll()), in: context)
            .filter { period.contains($0.date) }
            .reversed()
        let vaccines = fetch(baby.entries(Vaccine.fetchAll()), in: context)
            .filter { $0.isGiven && period.contains($0.date) }
        let appointments = fetch(baby.entries(Appointment.fetchAll()), in: context)
            .filter { period.contains($0.date) }
        let entries = fetch(baby.entries(DiaryEntry.between(period.start, period.end)), in: context)
        let notes = fetch(baby.entries(DiaryEntry.periodNotes()), in: context)
            .filter { $0.periodID == period.id }
            .sorted { $0.createdAt < $1.createdAt }

        let isInProgress = !period.isFinished(now: now)
        let today = calendar.startOfDay(for: now)
        // Days that have started: all of them once it's over.
        let lastStarted = min(period.lastDay(calendar: calendar), today)
        let dayCount = lastStarted < period.start
            ? 0
            : (calendar.dateComponents([.day], from: period.start, to: lastStarted).day ?? 0) + 1

        let coverage = Coverage(activities: activities, periods: periods, now: now, plan: plan, calendar: calendar)
        // `ReportBuilder` counts back from its `now`; ending at the last started day gives exactly the
        // period's days. Sleep still going on is counted up to the real now.
        let reportNow = isInProgress ? now : period.end.addingTimeInterval(-1)
        let days = dayCount > 0
            ? ReportBuilder.summaries(for: activities, days: dayCount, now: reportNow, calendar: calendar, coverage: coverage)
            : []
        let finishedDays = days.filter { $0.coverage != .inProgress }
        let logged = finishedDays.filter { $0.coverage == .full || $0.coverage == .partial }

        let sleeps = activities.filter { $0.kind == .sleep && period.contains($0.startDate) }
        let longest = sleeps
            .map { min($0.endDate ?? now, now).timeIntervalSince($0.startDate) }
            .filter { $0 > 0 }
            .max()

        // The same days `ReportAverages` uses: fully tracked ones, else partly tracked, else today so far.
        let full = finishedDays.filter { $0.hasData && $0.coverage == .full }
        let partial = finishedDays.filter { $0.hasData && $0.coverage == .partial }
        var basisDays = full.isEmpty ? partial : full
        if basisDays.isEmpty {
            basisDays = days.filter { $0.hasData && $0.coverage != .none }
        }
        let diapersPerDay: Double? = basisDays.isEmpty
            ? nil
            : Double(basisDays.reduce(0) { $0 + $1.diapers }) / Double(basisDays.count)

        let growth = growthAll.filter { period.contains($0.date) }
        let before = growthAll.last { $0.date < period.start }

        let milestonePhotos = milestones.reduce(0) { $0 + $1.photoIDSet.count }
        let entryPhotos = entries.reduce(0) { $0 + $1.photoIDSet.count }

        return DiarySummary(
            period: period,
            days: days,
            averages: ReportAverages(days, calendar: calendar),
            daysLogged: logged.count,
            daysPartlyLogged: logged.filter { $0.coverage == .partial }.count,
            daysSoFar: finishedDays.count,
            isInProgress: isInProgress,
            feeds: days.reduce(0) { $0 + $1.feedings },
            diapers: days.reduce(0) { $0 + $1.diapers },
            wetDiapers: days.reduce(0) { $0 + $1.wet },
            dirtyDiapers: days.reduce(0) { $0 + $1.dirty },
            diapersPerDay: diapersPerDay,
            sleepSeconds: days.reduce(0) { $0 + $1.sleepSeconds },
            longestSleep: longest,
            baths: days.reduce(0) { $0 + $1.baths },
            growth: growth,
            growthBefore: before,
            milestones: Array(milestones),
            vaccines: vaccines,
            appointments: appointments,
            entries: entries,
            notes: notes,
            photoCount: milestonePhotos + entryPhotos
        )
    }

    /// The results without entries deleted here or on the partner's phone a moment ago.
    private static func fetch<Entry: NSManagedObject>(_ request: NSFetchRequest<Entry>, in context: NSManagedObjectContext) -> [Entry] {
        ((try? context.fetch(request)) ?? []).filter { !$0.isDeleted && $0.managedObjectContext != nil }
    }
}

// MARK: - Growth wording

extension DiarySummary {
    /// "5.2 kg (+600 g since Oct 3) · 48th percentile", for the last weight measured in the period.
    func weightLine(units: GrowthUnits, baby: Baby) -> String? {
        guard let latest = growth.last(where: { $0.weightKg != nil }), let kg = latest.weightKg else { return nil }
        var line = units.formatWeight(kg: kg)
        if let change = change(\.weightKg, latest: latest) {
            line += " (\(units.formatWeightChange(kg: change.amount)) since \(change.since.formatted(.dateTime.month(.abbreviated).day())))"
        }
        if let percentile = baby.growthPercentile(.weight, value: kg, on: latest.date) {
            line += " · \(percentile.text)"
        }
        return line
    }

    /// The same for length.
    func lengthLine(units: GrowthUnits, baby: Baby) -> String? {
        guard let latest = growth.last(where: { $0.lengthCm != nil }), let cm = latest.lengthCm else { return nil }
        var line = units.formatLength(cm: cm)
        if let change = change(\.lengthCm, latest: latest) {
            line += " (\(units.formatLengthChange(cm: change.amount)) since \(change.since.formatted(.dateTime.month(.abbreviated).day())))"
        }
        if let percentile = baby.growthPercentile(.length, value: cm, on: latest.date) {
            line += " · \(percentile.text)"
        }
        return line
    }

    /// The change from the measurement before: the previous one in the period, or the last one before it.
    private func change(_ value: KeyPath<GrowthEntry, Double?>, latest: GrowthEntry) -> (amount: Double, since: Date)? {
        guard let current = latest[keyPath: value] else { return nil }
        let earlier = (growthBefore.map { [$0] } ?? []) + growth
        guard let previous = earlier.last(where: { $0 !== latest && $0.date < latest.date && $0[keyPath: value] != nil }),
              let old = previous[keyPath: value]
        else { return nil }
        return (current - old, previous.date)
    }
}
