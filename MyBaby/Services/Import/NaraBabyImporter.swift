import Foundation

/// Reads Nara Baby's CSV export (Activity › the child's picture › Export Data).
///
/// Nara doesn't document the file. The columns here were confirmed against a real export by
/// github.com/GrekMaR/nara-baby-exporter (`schema/FIELD_MAPPING.md`, "verified against a real,
/// user-provided Nara export", 2026-09-23; header row in `tests/fixtures/sample_export.csv`; checked
/// on 2026-10-25). One flat file per family:
///
/// - Every row: `Type, Profile Name, Start Date/time, Start Date/time (Epoch), Note, Time Zone`, …
/// - `Breastfeed`: `[Breastfeed] Begin Side, End Side, Left Duration (Seconds), Right Duration (Seconds)`
/// - `Sleep`: `[Sleep] Duration (Seconds), End Date/time, End Date/time (Epoch)`
/// - `Diaper`: `[Diaper] Type, Detail, Dirty Color, Dirty Texture`
/// - `Bottle Feed`: `[Bottle Feed] Type, Breast Milk Volume (+ Unit), Formula Name, Formula Volume (+ Unit), Volume (+ Unit)`
/// - `Pump`: `[Pump] Duration (Seconds), End Date/time (+ Epoch), Left/Right/Total Volume (+ Unit)`
/// - `Growth`: `[Growth] Head Size, Height, Weight`, each with a Unit column (CM/IN, KG/LB/G)
/// - `Profile`: the child's `[Profile] Birth Date` and `Sex`
///
/// Nara writes each moment as a timestamp too (the Epoch columns, in milliseconds), which is exact
/// whatever the time zone, so that's what's read; the local time is only used when it's missing, in
/// the row's own Time Zone. Types the source above hasn't confirmed (solids, medicine, milestones…)
/// are skipped and counted, never guessed. A family file can hold several children (Profile Name):
/// the parent picks which one goes into this baby.
enum NaraBabyImporter {
    static func recognizes(_ table: ImportTable) -> Bool {
        table.has("Type", "Profile Name", "Start Date/time")
            || table.header.contains { $0.hasPrefix("[Breastfeed]") || $0.hasPrefix("[Diaper]") }
    }

    static func read(_ tables: [ImportTable], options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .nara)
        for table in tables where recognizes(table) {
            plan.merge(read(table, options: options))
        }
        if plan.babyNames.count <= 1 {
            plan.babyNames = []
        } else {
            // A family file: the profile details could be any child's, so a new baby doesn't take them.
            plan.babyBirthDate = nil
            plan.babySex = nil
        }
        return plan
    }

    static func read(_ table: ImportTable, options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .nara)
        plan.notes.append(String(
            localized: "Nara Baby records the exact moment of each entry, so the times don't depend on the time zone chosen.",
            comment: "Import preview"
        ))
        let local = DateReader(pattern: DatePattern(format: "yyyy-MM-dd HH:mm:ss", order: .yearFirst), timeZone: options.timeZone)
        let localShort = DateReader(pattern: DatePattern(format: "yyyy-MM-dd HH:mm", order: .yearFirst), timeZone: options.timeZone)
        var readersByZone: [String: (DateReader, DateReader)] = [:]

        func text(_ row: [String], _ name: String) -> String {
            ImportTable.value(row, table.column(name))
        }

        /// The moment in `epochColumn`, or the local time in `localColumn` read in the row's time zone.
        func date(_ row: [String], epoch epochColumn: String, local localColumn: String) -> Date? {
            if let exact = DateReader.epochDate(text(row, epochColumn)) { return exact }
            let value = text(row, localColumn)
            guard !value.isEmpty else { return nil }
            let zoneName = text(row, "Time Zone")
            if let zone = TimeZone(identifier: zoneName) {
                let readers = readersByZone[zoneName] ?? (
                    DateReader(pattern: local.pattern, timeZone: zone), DateReader(pattern: localShort.pattern, timeZone: zone)
                )
                readersByZone[zoneName] = readers
                return readers.0.date(value) ?? readers.1.date(value)
            }
            return local.date(value) ?? localShort.date(value)
        }

        func volume(_ row: [String], _ name: String) -> Double? {
            let unit = ImportValues.volumeUnit(text(row, "\(name) Unit")) ?? options.volumeUnit
            guard let value = Double(text(row, name)), value >= 0 else { return nil }
            return unit.toML(value)
        }

        for row in table.rows {
            let type = text(row, "Type")
            let baby = text(row, "Profile Name")
            if type.lowercased() == "profile" {
                // The child's details, not an entry.
                if !baby.isEmpty, !plan.babyNames.contains(baby) { plan.babyNames.append(baby) }
                if plan.babyBirthDate == nil, let birth = ImportDates.guess([text(row, "[Profile] Birth Date")], timeZone: options.timeZone) {
                    plan.babyBirthDate = DateReader(pattern: birth.pattern, timeZone: options.timeZone).date(text(row, "[Profile] Birth Date"))
                }
                if plan.babySex == nil {
                    plan.babySex = BabySex(rawValue: text(row, "[Profile] Sex").lowercased())
                }
                continue
            }
            plan.rowCount += 1
            if !baby.isEmpty, !plan.babyNames.contains(baby) { plan.babyNames.append(baby) }
            guard let start = date(row, epoch: "Start Date/time (Epoch)", local: "Start Date/time") else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            let note = text(row, "Note")

            switch type.lowercased() {
            case "breastfeed":
                let leftSeconds = Double(text(row, "[Breastfeed] Left Duration (Seconds)")) ?? 0
                let rightSeconds = Double(text(row, "[Breastfeed] Right Duration (Seconds)")) ?? 0
                guard leftSeconds + rightSeconds > 0 else {
                    plan.skip(String(localized: "Breastfeeds with no time on either side", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.feeding), start: start)
                entry.feedingType = .breast
                entry.leftMinutes = leftSeconds > 0 ? ImportValues.wholeMinutes(leftSeconds / 60) : nil
                entry.rightMinutes = rightSeconds > 0 ? ImportValues.wholeMinutes(rightSeconds / 60) : nil
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "sleep":
                let seconds = Double(text(row, "[Sleep] Duration (Seconds)"))
                guard let end = date(row, epoch: "[Sleep] End Date/time (Epoch)", local: "[Sleep] End Date/time")
                    ?? seconds.map({ start.addingTimeInterval($0) }),
                    end > start
                else {
                    plan.skip(String(localized: "Sleeps without an end time", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.sleep), start: start)
                entry.end = end
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "diaper":
                let kind = text(row, "[Diaper] Type")
                guard let diaper = ImportValues.diaperType(kind) else {
                    plan.skip(String(localized: "Diapers that don't say wet or dirty", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.diaper), start: start)
                entry.diaperType = diaper
                if diaper == .dirty || diaper == .mixed {
                    let color = text(row, "[Diaper] Dirty Color"), texture = text(row, "[Diaper] Dirty Texture")
                    entry.poopColor = ImportValues.poopColor(color.replacingOccurrences(of: "_", with: " "))
                    if entry.poopColor == nil, !color.isEmpty { entry.addNote(String(localized: "Color: \(color.lowercased())", comment: "Import: a poop color, as the file says")) }
                    entry.poopConsistency = ImportValues.poopConsistency(texture.replacingOccurrences(of: "_", with: " "))
                    if entry.poopConsistency == nil, !texture.isEmpty { entry.addNote(texture.lowercased()) }
                }
                entry.addNote(text(row, "[Diaper] Detail"))
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "bottle feed":
                var entry = ImportEntry(.activity(.feeding), start: start)
                let contents = text(row, "[Bottle Feed] Type")
                entry.feedingType = ImportValues.bottleType(contents) ?? .formula
                if ImportValues.bottleType(contents) == nil {
                    let contentsText = contents.lowercased()
                    entry.addNote(contents.isEmpty
                        ? String(localized: "Bottle contents weren't in the file", comment: "Import: a note added to an imported entry")
                        : String(localized: "Bottle: \(contentsText)", comment: "Import: what was in a bottle, as the file says"))
                }
                entry.amountML = volume(row, "[Bottle Feed] Breast Milk Volume")
                    ?? volume(row, "[Bottle Feed] Formula Volume")
                    ?? volume(row, "[Bottle Feed] Volume")
                let formula = text(row, "[Bottle Feed] Formula Name")
                if !formula.isEmpty { entry.addNote(String(localized: "Formula: \(formula)", comment: "Import: the formula's name, as the file says")) }
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "pump":
                var entry = ImportEntry(.activity(.pumping), start: start)
                entry.pumpLeftML = volume(row, "[Pump] Left Volume")
                entry.pumpRightML = volume(row, "[Pump] Right Volume")
                entry.amountML = volume(row, "[Pump] Total Volume")
                    ?? ((entry.pumpLeftML != nil || entry.pumpRightML != nil) ? (entry.pumpLeftML ?? 0) + (entry.pumpRightML ?? 0) : nil)
                if let seconds = Double(text(row, "[Pump] Duration (Seconds)")), seconds > 0 {
                    entry.durationMinutes = max(1, Int((seconds / 60).rounded()))
                }
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "growth":
                var entry = ImportEntry(.growth, start: start)
                if let weight = Double(text(row, "[Growth] Weight")), weight > 0 {
                    entry.weightKg = ImportValues.kilograms("\(weight) \(text(row, "[Growth] Weight Unit"))", defaultUnit: "kg")
                }
                if let height = Double(text(row, "[Growth] Height")), height > 0 {
                    entry.lengthCm = ImportValues.centimeters("\(height) \(text(row, "[Growth] Height Unit"))", defaultUnit: "cm")
                }
                if let head = Double(text(row, "[Growth] Head Size")), head > 0,
                   let headCm = ImportValues.centimeters("\(head) \(text(row, "[Growth] Head Size Unit"))", defaultUnit: "cm") {
                    let headText = headCm.formatted(.number.precision(.fractionLength(0...1)))
                    entry.addNote(String(localized: "Head \(headText) cm", comment: "Import: a head circumference added to the notes"))
                }
                guard entry.weightKg != nil || entry.lengthCm != nil else {
                    plan.skip(String(localized: "Growth entries without a weight or length", comment: "Import preview: why rows were left out"))
                    continue
                }
                entry.sourceBaby = baby.isEmpty ? nil : baby
                entry.addNote(note)
                plan.add(entry)
            case "":
                plan.skip(String(localized: "Rows without a type", comment: "Import preview: why rows were left out"))
            default:
                plan.skip(String(localized: "\(type) (not something MyBaby imports from Nara Baby yet)", comment: "Import preview; a kind of entry, as the file names it"))
            }
        }
        return plan
    }
}
