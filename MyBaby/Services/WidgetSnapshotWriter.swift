import CoreData
import UIKit
import WidgetKit

/// Keeps the widgets' `WidgetSnapshot` (Shared/WidgetSnapshot.swift) up to date, and the sleep Live
/// Activity in step with the log. Also hands each snapshot to `WatchBridge` for the Apple Watch.
///
/// Started once at launch (`MyBabyApp.init`). It's the one place that watches for changes:
/// - saves in this app (`didSaveObjectsNotification`), from any screen, Siri or a widget button;
/// - changes from the partner's phone or iCloud (`NSPersistentStoreRemoteChange`);
/// - settings changes, such as switching babies, ml/oz or the night plan (`UserDefaults.didChangeNotification`);
/// - the app opening, to catch up on anything that couldn't be done in the background.
/// Then it rebuilds the snapshot, and only if anything changed, writes it and reloads the widgets.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// What was last written, so unchanged snapshots don't reload the widgets.
    private var lastWritten: WidgetSnapshot?
    private var hasWritten = false

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSManagedObjectContext.didSaveObjectsNotification,
            .NSPersistentStoreRemoteChange,
            UserDefaults.didChangeNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                FeedingTimer.shared.reload()
                self?.refreshNow(force: true)
            }
        })
        refreshNow(force: true)
    }

    /// Refreshes shortly, so a burst of changes (e.g. an iCloud import) writes once.
    func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    /// Rebuilds the snapshot right away. Intents call this before they return, since the app may be
    /// suspended as soon as they finish. `force` writes and reloads even if nothing seems to have changed.
    func refreshNow(force: Bool = false) {
        pending?.cancel()
        pending = nil
        // While iCloud is switched on or off the stores are being reopened and look empty.
        guard CloudStatus.shared.reloadingMessage == nil else { return }

        let context = PersistenceController.shared.viewContext
        let snapshot = WidgetSnapshot.make(context: context)
        LiveActivities.syncSleep(
            start: snapshot?.sleepStart,
            sleepID: snapshot?.sleepID,
            babyName: snapshot?.babyName ?? "Baby"
        )
        // The Apple Watch gets the same summary, plus a few things of its own (see `WatchBridge`).
        WatchBridge.shared.send(snapshot, force: force)
        // "Haven't logged in a while" counts from the latest entry, so it moves with every change.
        GapReminder.refresh(context: context)
        // Only the next "month birthday" diary reminder is pending, so keep it rolling forward.
        DiaryReminder.refresh(context: context)

        if !force, hasWritten {
            switch (snapshot, lastWritten) {
            case (nil, nil): return
            case let (new?, old?) where new.hasSameContent(as: old): return
            default: break
            }
        }
        WidgetSnapshot.save(snapshot)
        lastWritten = snapshot
        hasWritten = true
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WidgetSnapshot {
    /// The snapshot: every baby's part (`babies`), with the baby shown in the app in the top-level
    /// fields too. `nil` before there's a baby. On the main actor because it reads `FeedingTimer.shared`.
    @MainActor
    static func make(context: NSManagedObjectContext, now: Date = .now) -> WidgetSnapshot? {
        let babies = (try? context.fetch(Baby.fetchAll())) ?? []
        guard let selected = Baby.preferred(from: babies) else { return nil }
        let defaults = UserDefaults.shared
        let unit = VolumeUnit(rawValue: defaults.string(forKey: SettingsKey.volumeUnit) ?? "") ?? .ml
        let parts = WidgetBabyParts(babies: babies, context: context, unit: unit, now: now)

        var snapshot = WidgetSnapshot(babyName: selected.displayName, babyID: selected.uuid?.uuidString)
        snapshot.babyCount = babies.count
        snapshot.babies = babies.map { baby in
            var part = parts.snapshot(for: baby)
            part.nextFeedExpected = CarePredictions.nextFeedForWidget(baby: baby, context: context, now: now)
            return part
        }

        let shown = parts.snapshot(for: selected)
        snapshot.lastFeed = shown.lastFeed
        snapshot.lastDiaper = shown.lastDiaper
        snapshot.sleepStart = shown.sleepStart
        snapshot.sleepID = shown.sleepID
        snapshot.lastWake = shown.lastWake

        let plan = NightPlan.load()
        if plan.isEnabled {
            snapshot.shifts = plan.upcomingNights(from: now, count: 2).joined().map { shift in
                Shift(
                    parentName: plan.name(of: shift.parent),
                    isParent1: shift.parent == .parent1,
                    start: shift.start,
                    end: shift.end
                )
            }
        }
        snapshot.feedingTimer = FeedingTimer.shared.state
        return snapshot
    }
}

/// What the widgets show for each baby, read with one fetch per kind of entry for all the babies
/// together and grouped by baby, so twins cost about the same as one baby.
@MainActor
private struct WidgetBabyParts {
    typealias Part = WidgetSnapshot.BabySnapshot
    typealias Key = NSManagedObjectID

    let unit: VolumeUnit
    let now: Date
    /// Midnight today, where the "today" counts start.
    let dayStart: Date

    var lastFeed: [Key: Activity] = [:]
    var lastDiaper: [Key: Activity] = [:]
    var ongoingSleep: [Key: Activity] = [:]
    var lastSleep: [Key: Activity] = [:]
    var lastPumping: [Key: Activity] = [:]
    var lastBottle: [Key: Activity] = [:]
    var feedsToday: [Key: Int] = [:]
    var diapersToday: [Key: Int] = [:]
    /// The latest dose of any medicine.
    var lastMedicine: [Key: Activity] = [:]
    /// When each medicine was given, by `MedicineSchedule.key(for:)`.
    var doseDates: [Key: [String: [Date]]] = [:]
    /// Medicines with dose timing entered.
    var schedules: [Key: [MedicineSchedule]] = [:]
    var stash: [Key: (ml: Double, count: Int)] = [:]

    init(babies: [Baby], context: NSManagedObjectContext, unit: VolumeUnit, now: Date) {
        self.unit = unit
        self.now = now
        dayStart = Calendar.current.startOfDay(for: now)
        let count = babies.count

        lastFeed = Self.newest(Activity.all(.feeding), babyCount: count, in: context)
        lastDiaper = Self.newest(Activity.all(.diaper), babyCount: count, in: context)
        lastSleep = Self.newest(Activity.all(.sleep), babyCount: count, in: context)
        lastPumping = Self.newest(Activity.all(.pumping), babyCount: count, in: context)
        ongoingSleep = Self.newest(
            Activity.fetch(NSPredicate(format: "kindRaw == %@ AND endDate == nil", ActivityKind.sleep.rawValue)),
            babyCount: count,
            in: context
        )
        lastBottle = Self.newest(
            Activity.fetch(NSPredicate(
                format: "kindRaw == %@ AND feedingTypeRaw IN %@",
                ActivityKind.feeding.rawValue,
                [FeedingType.breastMilkBottle.rawValue, FeedingType.formula.rawValue] as NSArray
            )),
            babyCount: count,
            in: context
        )

        let today = Activity.fetch(NSPredicate(
            format: "startDate >= %@ AND kindRaw IN %@",
            dayStart as NSDate,
            [ActivityKind.feeding.rawValue, ActivityKind.diaper.rawValue] as NSArray
        ))
        for entry in (try? context.fetch(today)) ?? [] {
            guard let key = entry.baby?.objectID else { continue }
            if entry.kind == .feeding {
                feedsToday[key, default: 0] += 1
            } else {
                diapersToday[key, default: 0] += 1
            }
        }

        // Newest first, so the first dose seen for a baby is their latest.
        for dose in (try? context.fetch(Activity.all(.medication))) ?? [] {
            guard let key = dose.baby?.objectID else { continue }
            let medicine = MedicineSchedule.key(for: dose.medicationName)
            guard !medicine.isEmpty else { continue }
            if lastMedicine[key] == nil { lastMedicine[key] = dose }
            doseDates[key, default: [:]][medicine, default: []].append(dose.startDate)
        }
        for schedule in (try? context.fetch(MedicineSchedule.fetchAll())) ?? [] where !schedule.rule.isEmpty {
            guard let key = schedule.baby?.objectID else { continue }
            schedules[key, default: []].append(schedule)
        }

        for bag in (try? context.fetch(MilkBag.inStash())) ?? [] {
            guard let key = bag.baby?.objectID else { continue }
            let sum = stash[key] ?? (ml: 0, count: 0)
            stash[key] = (ml: sum.ml + (bag.amountML ?? 0), count: sum.count + 1)
        }
    }

    /// The newest entry from `request` (newest first) for each baby. It reads in small batches and
    /// stops as soon as every baby has one, so it usually reads only the last few entries.
    private static func newest(
        _ request: NSFetchRequest<Activity>,
        babyCount: Int,
        in context: NSManagedObjectContext
    ) -> [Key: Activity] {
        var found: [Key: Activity] = [:]
        guard babyCount > 0 else { return found }
        request.fetchBatchSize = 20
        for entry in (try? context.fetch(request)) ?? [] {
            guard let key = entry.baby?.objectID, found[key] == nil else { continue }
            found[key] = entry
            if found.count == babyCount { break }
        }
        return found
    }

    func snapshot(for baby: Baby) -> Part {
        let key = baby.objectID
        var part = Part(id: baby.uuid?.uuidString ?? "", name: baby.displayName, countedDay: dayStart)

        if let feed = lastFeed[key] {
            part.lastFeed = WidgetSnapshot.Feed(
                date: feed.startDate,
                title: feed.title,
                shortTitle: feed.feedingType?.shortTitle ?? "Feeding",
                emoji: feed.emoji,
                detail: feed.detail(unit: unit, now: now)
            )
        }
        if let diaper = lastDiaper[key] {
            part.lastDiaper = WidgetSnapshot.Diaper(
                date: diaper.startDate,
                title: diaper.diaperType?.quickTitle ?? "Diaper",
                emoji: diaper.emoji
            )
        }
        if let sleep = ongoingSleep[key] {
            part.sleepStart = sleep.startDate
            part.sleepID = sleep.uuid?.uuidString
        } else if let sleep = lastSleep[key] {
            part.lastWake = sleep.endDate
        }
        part.feedsToday = feedsToday[key] ?? 0
        part.diapersToday = diapersToday[key] ?? 0

        if let pumping = lastPumping[key] {
            let total = pumping.pumpedTotalML ?? 0
            part.lastPumping = Part.Pumping(
                date: pumping.startDate,
                amountText: total > 0 ? unit.format(ml: total) : ""
            )
        }
        if let bags = stash[key] {
            part.stash = Part.Stash(totalText: bags.ml > 0 ? unit.format(ml: bags.ml) : "", bagCount: bags.count)
        }
        if let bottle = lastBottle[key] {
            let ml = bottle.amountML
            part.usualBottle = Part.Bottle(
                isFormula: bottle.feedingType == .formula,
                ml: ml,
                amountText: ml.map { unit.format(ml: $0) } ?? ""
            )
        }

        let doses = doseDates[key] ?? [:]
        let timed = schedules[key] ?? []
        if let dose = lastMedicine[key] {
            let name = dose.medicationName?.trimmingCharacters(in: .whitespaces) ?? ""
            var next: Date?
            if let rule = timed.matching(name)?.rule {
                next = MedicineTiming.nextAllowed(rule: rule, doseDates: doses[MedicineSchedule.key(for: name)] ?? [], now: now)
            }
            part.lastMedicine = Part.Medicine(name: name, dosage: dose.dosage ?? "", nextAllowed: next)
        }
        part.nextDose = nextDose(schedules: timed, doses: doses)
        return part
    }

    /// The medicine whose next dose the entered timing allows soonest, or, when every one is allowed
    /// now, the one given most recently. Medicines never given are left out.
    private func nextDose(schedules: [MedicineSchedule], doses: [String: [Date]]) -> Part.NextDose? {
        var soonest: (name: String, date: Date)?
        var latest: (name: String, given: Date)?
        for schedule in schedules {
            let dates = doses[MedicineSchedule.key(for: schedule.name)] ?? []
            guard let given = dates.max() else { continue }
            let name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let next = MedicineTiming.nextAllowed(rule: schedule.rule, doseDates: dates, now: now) {
                if soonest.map({ next < $0.date }) ?? true { soonest = (name, next) }
            } else if latest.map({ given > $0.given }) ?? true {
                latest = (name, given)
            }
        }
        if let soonest { return Part.NextDose(name: soonest.name, date: soonest.date) }
        if let latest { return Part.NextDose(name: latest.name, date: nil) }
        return nil
    }
}
