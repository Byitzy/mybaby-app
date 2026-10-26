import CoreData
import Foundation

/// How an import went, for its last screen.
struct ImportSummary: Sendable {
    var added = 0
    /// Already in MyBaby: the same kind of entry within a minute (see `ImportWriter.duplicateWindow`).
    var duplicates = 0
    var wasStopped = false
}

/// Saves an `ImportPlan` into a baby's log, and removes an import again.
///
/// Everything runs on a background context, in batches of `batchSize` saved one at a time, so the
/// screens stay smooth, progress can be shown and Cancel stops between two batches. Each entry is put
/// in the baby's own store (private, or shared when the partner shared the baby), like entries logged
/// in the app, and is tagged with the import's id so "Remove this import" can find it.
///
/// Imported entries count as logged time for `Coverage` like any other, and nothing else is added: no
/// "nothing happened" marks are made for the file's quiet stretches, so a gap in the other app's log
/// stays a gap in MyBaby's, never a run of zeros. Marked times only come in when the file has them
/// (MyBaby's own export).
enum ImportWriter {
    static let batchSize = 400
    /// An entry within this of one already logged, of the same kind, is the same entry.
    static let duplicateWindow: TimeInterval = 60

    // MARK: Duplicates

    /// Sorted start times of what the baby already has, by kind, for spotting duplicates.
    struct ExistingIndex {
        fileprivate var activities: [ActivityKind: [Date]] = [:]
        fileprivate var growth: [Date] = []
        fileprivate var vaccines: [String: [Date]] = [:]
        fileprivate var periods: [TrackingPeriodKind: [Date]] = [:]

        func contains(_ entry: ImportEntry) -> Bool {
            switch entry.kind {
            case .activity(let kind): return Self.has(entry.start, in: activities[kind] ?? [])
            case .growth: return Self.has(entry.start, in: growth)
            case .vaccine: return Self.has(entry.start, in: vaccines[entry.vaccineName.lowercased()] ?? [])
            case .trackingPeriod: return Self.has(entry.start, in: periods[entry.trackingKind ?? .notTracked] ?? [])
            }
        }

        /// Whether a date in the sorted `dates` is within a minute of `date`.
        private static func has(_ date: Date, in dates: [Date]) -> Bool {
            var low = 0, high = dates.count
            let earliest = date.addingTimeInterval(-ImportWriter.duplicateWindow)
            while low < high {
                let middle = (low + high) / 2
                if dates[middle] < earliest { low = middle + 1 } else { high = middle }
            }
            return low < dates.count && dates[low] <= date.addingTimeInterval(ImportWriter.duplicateWindow)
        }
    }

    /// What `baby` already has between `range`'s ends (a minute either side). Call on `context`'s queue.
    static func existingIndex(for baby: Baby, in range: ClosedRange<Date>, context: NSManagedObjectContext) -> ExistingIndex {
        var index = ExistingIndex()
        let from = range.lowerBound.addingTimeInterval(-duplicateWindow) as NSDate
        let to = range.upperBound.addingTimeInterval(duplicateWindow) as NSDate

        let activities = NSFetchRequest<NSDictionary>(entityName: "Activity")
        activities.resultType = .dictionaryResultType
        activities.propertiesToFetch = ["kindRaw", "startDate"]
        activities.predicate = NSPredicate(format: "baby == %@ AND startDate >= %@ AND startDate <= %@", baby, from, to)
        for row in (try? context.fetch(activities)) ?? [] {
            guard let raw = row["kindRaw"] as? String, let kind = ActivityKind(rawValue: raw),
                  let date = row["startDate"] as? Date else { continue }
            index.activities[kind, default: []].append(date)
        }

        let growth = NSFetchRequest<NSDictionary>(entityName: "GrowthEntry")
        growth.resultType = .dictionaryResultType
        growth.propertiesToFetch = ["date"]
        growth.predicate = NSPredicate(format: "baby == %@ AND date >= %@ AND date <= %@", baby, from, to)
        index.growth = ((try? context.fetch(growth)) ?? []).compactMap { $0["date"] as? Date }

        let vaccines = NSFetchRequest<NSDictionary>(entityName: "Vaccine")
        vaccines.resultType = .dictionaryResultType
        vaccines.propertiesToFetch = ["name", "date"]
        vaccines.predicate = NSPredicate(format: "baby == %@ AND date >= %@ AND date <= %@", baby, from, to)
        for row in (try? context.fetch(vaccines)) ?? [] {
            guard let name = row["name"] as? String, let date = row["date"] as? Date else { continue }
            index.vaccines[name.lowercased(), default: []].append(date)
        }

        let periods = NSFetchRequest<NSDictionary>(entityName: "TrackingPeriod")
        periods.resultType = .dictionaryResultType
        periods.propertiesToFetch = ["kindRaw", "start"]
        periods.predicate = NSPredicate(format: "baby == %@ AND start >= %@ AND start <= %@", baby, from, to)
        for row in (try? context.fetch(periods)) ?? [] {
            guard let raw = row["kindRaw"] as? String, let date = row["start"] as? Date else { continue }
            index.periods[TrackingPeriodKind(rawValue: raw) ?? .notTracked, default: []].append(date)
        }

        for key in index.activities.keys { index.activities[key]?.sort() }
        index.growth.sort()
        for key in index.vaccines.keys { index.vaccines[key]?.sort() }
        for key in index.periods.keys { index.periods[key]?.sort() }
        return index
    }

    /// How many of `entries` `baby` already has, for the preview. Runs on a background context.
    static func countDuplicates(_ entries: [ImportEntry], babyID: NSManagedObjectID, container: NSPersistentContainer) async -> Int {
        guard let first = entries.map(\.start).min(), let last = entries.map(\.start).max() else { return 0 }
        let context = container.newBackgroundContext()
        return await context.perform {
            guard let baby = try? context.existingObject(with: babyID) as? Baby else { return 0 }
            let index = Self.existingIndex(for: baby, in: first...last, context: context)
            return entries.reduce(0) { $0 + (index.contains($1) ? 1 : 0) }
        }
    }

    // MARK: Writing

    /// Adds `entries` to the baby with `babyID`, skipping duplicates, in batches. `progress` is called on
    /// the main actor after each batch with how many entries have been looked at. Stops between batches
    /// when the task is cancelled; what's saved by then stays, tagged with `batchID`.
    static func write(
        _ entries: [ImportEntry],
        babyID: NSManagedObjectID,
        batchID: String,
        container: NSPersistentContainer,
        progress: @escaping @MainActor (Int) -> Void
    ) async throws -> ImportSummary {
        var summary = ImportSummary()
        guard let first = entries.map(\.start).min(), let last = entries.map(\.start).max() else { return summary }
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        // Hold on to the index between batches; it's plain values, so it outlives `reset()`.
        let index: ExistingIndex = try await context.perform {
            guard let baby = try context.existingObject(with: babyID) as? Baby else { throw ImportError.cancelled }
            return Self.existingIndex(for: baby, in: first...last, context: context)
        }

        var done = 0
        for start in stride(from: 0, to: entries.count, by: batchSize) {
            if Task.isCancelled {
                summary.wasStopped = true
                break
            }
            let batch = Array(entries[start..<min(start + batchSize, entries.count)])
            let result: (added: Int, duplicates: Int) = try await context.perform {
                guard let baby = try context.existingObject(with: babyID) as? Baby else { throw ImportError.cancelled }
                let store = babyID.persistentStore
                var added = 0, duplicates = 0
                for entry in batch {
                    if index.contains(entry) {
                        duplicates += 1
                        continue
                    }
                    Self.insert(entry, for: baby, store: store, batchID: batchID, in: context)
                    added += 1
                }
                try context.save()
                // Let go of the saved objects, so a long file doesn't build up in memory.
                context.reset()
                return (added, duplicates)
            }
            summary.added += result.added
            summary.duplicates += result.duplicates
            done += batch.count
            await progress(done)
            // A breath between batches, so the screens and iCloud keep up.
            await Task.yield()
        }
        return summary
    }

    /// One entry, in the baby's store. Call on `context`'s queue.
    private static func insert(_ entry: ImportEntry, for baby: Baby, store: NSPersistentStore?, batchID: String, in context: NSManagedObjectContext) {
        // Entries must live in the same store as their baby, assigned before they're linked (see `Baby.attach`).
        func placed<Object: NSManagedObject>(_ object: Object) -> Object {
            if let store { context.assign(object, to: store) }
            return object
        }
        switch entry.kind {
        case .activity(let kind):
            let activity = placed(Activity(context: context))
            activity.uuid = UUID()
            activity.kindRaw = kind.rawValue
            activity.startDate = entry.start
            activity.endDate = kind == .sleep ? entry.end : nil
            activity.notes = entry.notes
            activity.feedingType = entry.feedingType
            activity.amountML = entry.amountML
            activity.leftMinutes = entry.leftMinutes
            activity.rightMinutes = entry.rightMinutes
            activity.foodDescription = entry.foodDescription
            if !entry.allergenIDs.isEmpty { activity.allergenIDs = entry.allergenIDs }
            activity.diaperType = entry.diaperType
            activity.poopColor = entry.poopColor
            activity.poopConsistency = entry.poopConsistency
            activity.medicationName = entry.medicationName
            activity.dosage = entry.dosage
            activity.pumpLeftML = entry.pumpLeftML
            activity.pumpRightML = entry.pumpRightML
            activity.durationMinutes = entry.durationMinutes
            activity.temperatureC = entry.temperatureC
            activity.temperatureMethod = entry.temperatureMethod
            if !entry.symptoms.isEmpty { activity.symptoms = entry.symptoms }
            activity.isApproximate = entry.isApproximate
            activity.caregiver = entry.caregiver
            activity.importBatchID = batchID
            activity.baby = baby
        case .growth:
            let growth = placed(GrowthEntry(context: context))
            growth.uuid = UUID()
            growth.date = entry.start
            growth.weightKg = entry.weightKg
            growth.lengthCm = entry.lengthCm
            growth.notes = entry.notes
            growth.importBatchID = batchID
            growth.baby = baby
        case .vaccine:
            let vaccine = placed(Vaccine(context: context))
            vaccine.uuid = UUID()
            vaccine.name = entry.vaccineName
            vaccine.date = entry.start
            vaccine.isGiven = entry.vaccineIsGiven
            vaccine.doseLabel = entry.doseLabel
            vaccine.provider = entry.provider
            vaccine.lotNumber = entry.lotNumber
            vaccine.notes = entry.notes
            vaccine.productName = entry.productName.isEmpty ? nil : entry.productName
            vaccine.doseAmount = entry.doseAmount
            vaccine.doseUnit = VaccineDoseUnit(rawValue: entry.doseUnit)?.rawValue
            vaccine.expiryDate = entry.expiryDate
            vaccine.importBatchID = batchID
            vaccine.baby = baby
        case .trackingPeriod:
            let period = placed(TrackingPeriod(context: context))
            period.uuid = UUID()
            let end = entry.end ?? entry.start
            period.start = min(entry.start, end)
            period.end = max(entry.start, end)
            period.kind = entry.trackingKind ?? .notTracked
            period.reason = entry.trackingReason
            period.notes = entry.notes
            period.importBatchID = batchID
            period.baby = baby
        }
    }

    // MARK: Removing

    /// Deletes everything import `batchID` added, in batches on a background context. Returns how many.
    static func remove(batchID: String, container: NSPersistentContainer) async throws -> Int {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return try await context.perform {
            var removed = 0
            for entity in ["Activity", "GrowthEntry", "Vaccine", "TrackingPeriod"] {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
                request.resultType = .managedObjectIDResultType
                request.predicate = NSPredicate(format: "importBatchID == %@", batchID)
                let ids = try context.fetch(request)
                for chunk in stride(from: 0, to: ids.count, by: batchSize) {
                    for id in ids[chunk..<min(chunk + batchSize, ids.count)] {
                        context.delete(context.object(with: id))
                    }
                    try context.save()
                    context.reset()
                }
                removed += ids.count
            }
            return removed
        }
    }

    /// How many entries import `batchID` still has in the log, for Settings.
    static func count(batchID: String, in context: NSManagedObjectContext) -> Int {
        ["Activity", "GrowthEntry", "Vaccine", "TrackingPeriod"].reduce(0) { total, entity in
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "importBatchID == %@", batchID)
            return total + ((try? context.count(for: request)) ?? 0)
        }
    }
}
