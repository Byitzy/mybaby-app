import Foundation

/// Reads Huckleberry's CSV export (child profile › Export tracking data as CSV).
///
/// Huckleberry doesn't document the file. This follows a real export its owner published
/// (github.com/archiewood/baby-tracker, `sources/huckleberry/events.csv`, about 3,600 rows, checked
/// row by row on 2026-10-25) and the open-source readers that agree with it: jjroth001/LibreBaby
/// (`src/lib/huckleberry.ts`), refsdal/pjokk (`scripts/import-huckleberry.mjs`, `docs/importing.md`)
/// and murphb52/BabyTracker (`HuckleberryCSVParser.swift`). Huckleberry's help article on exporting:
/// https://huckleberry.zendesk.com/hc/en-us/articles/5055945148819
///
/// One file per child, one row per entry, every type sharing the same columns:
/// `Type, Start, End, Duration, Start Condition, Start Location, End Condition, Notes` (newer exports
/// add `Logged By`). Times are the phone's local time with no time zone, "2024-07-16 07:07", so
/// they're read in the zone the parent picks. Each type uses the condition columns its own way:
///
/// | Type   | Start Condition            | Start Location     | End Condition                  | Duration     |
/// |--------|----------------------------|--------------------|--------------------------------|--------------|
/// | Feed   | right side "00:07R", or the bottle's contents "Formula" / "Breast Milk" | "Breast" or "Bottle" | left side "00:06L", or the amount "60ml" / "3oz" | total |
/// | Diaper | consistency                | "Diaper rash"      | "Pee", "Poo", "Both", sizes ("Both, pee:large poo:small") | poo color |
/// | Sleep  | how they fell asleep       | where              | how they woke                  | total        |
/// | Pump   | left amount "100ml"        |                    | right amount "120ml"           | total        |
/// | Meds   | dose "1.5ml"               | name "Tylenol"     |                                |              |
/// | Growth | weight "11.7kg", "25.8lb"  | length "81.28cm", "2.67ft.in" (decimal feet) | head "39.4cm" |   |
/// | Solids | the foods, comma separated |                    |                                |              |
///
/// Imperial weights and lengths ("13.03lbs.oz", "2.67ft.in") are decimal pounds and feet: the
/// published export's checkups only form a smooth growth curve read that way. Tummy time, potty,
/// temperature and other types aren't logged in MyBaby, or aren't documented, so they're skipped and
/// counted, never guessed.
enum HuckleberryImporter {
    static let columns = ["Type", "Start", "End", "Duration", "Start Condition", "Start Location", "End Condition"]

    static func recognizes(_ table: ImportTable) -> Bool {
        columns.allSatisfy { table.column($0) != nil }
    }

    static func read(_ tables: [ImportTable], options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .huckleberry)
        for table in tables where recognizes(table) {
            plan.merge(read(table, options: options))
        }
        return plan
    }

    private struct Row {
        let type, start, end, duration, startCondition, startLocation, endCondition, notes: String
    }

    static func read(_ table: ImportTable, options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .huckleberry)
        let type = table.column("Type"), start = table.column("Start"), end = table.column("End")
        let duration = table.column("Duration"), startCondition = table.column("Start Condition")
        let startLocation = table.column("Start Location"), endCondition = table.column("End Condition")
        let notes = table.column("Notes")

        let starts = table.rows.map { ImportTable.value($0, start) }
        let guess = ImportDates.guess(
            starts, preferred: ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"], order: options.dateOrder, timeZone: options.timeZone
        )
        let reader = DateReader(pattern: guess?.pattern ?? DatePattern(format: "yyyy-MM-dd HH:mm", order: .yearFirst), timeZone: options.timeZone)
        if let guess {
            plan.dateDescription = ImportDates.describe(guess, timeZone: options.timeZone)
            plan.datesAreAmbiguous = guess.isAmbiguous
        }

        for cells in table.rows {
            let row = Row(
                type: ImportTable.value(cells, type), start: ImportTable.value(cells, start),
                end: ImportTable.value(cells, end), duration: ImportTable.value(cells, duration),
                startCondition: ImportTable.value(cells, startCondition),
                startLocation: ImportTable.value(cells, startLocation),
                endCondition: ImportTable.value(cells, endCondition), notes: ImportTable.value(cells, notes)
            )
            // Some exports repeat the header partway down.
            if row.type.lowercased() == "type" { continue }
            plan.rowCount += 1
            guard let date = reader.date(row.start) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            let endDate = reader.date(row.end)
            switch row.type.lowercased() {
            case "feed":
                readFeed(row, start: date, end: endDate, into: &plan)
            case "diaper":
                readDiaper(row, start: date, reader: reader, into: &plan)
            case "sleep":
                readSleep(row, start: date, end: endDate, into: &plan)
            case "pump":
                readPump(row, start: date, end: endDate, into: &plan)
            case "meds", "medicine", "medication":
                var entry = ImportEntry(.activity(.medication), start: date)
                entry.medicationName = row.startLocation.isEmpty ? "Medicine" : row.startLocation
                entry.dosage = row.startCondition.isEmpty ? nil : row.startCondition
                entry.addNote(row.notes)
                plan.add(entry)
            case "growth":
                readGrowth(row, start: date, into: &plan)
            case "solids":
                var entry = ImportEntry(.activity(.feeding), start: date)
                entry.feedingType = .solids
                let foods = row.startCondition.isEmpty ? row.notes : row.startCondition
                entry.foodDescription = foods.isEmpty ? nil : foods
                if !row.startCondition.isEmpty { entry.addNote(row.notes) }
                plan.add(entry)
            case "bath":
                var entry = ImportEntry(.activity(.bath), start: date)
                entry.addNote(row.notes)
                plan.add(entry)
            case "":
                plan.skip(String(localized: "Rows without a type", comment: "Import preview: why rows were left out"))
            default:
                plan.skip(String(localized: "\(row.type) (not imported from Huckleberry)", comment: "Import preview; a kind of entry, as the file names it"))
            }
        }
        return plan
    }

    private static func readFeed(_ row: Row, start: Date, end: Date?, into plan: inout ImportPlan) {
        let location = row.startLocation.lowercased()
        var entry = ImportEntry(.activity(.feeding), start: start)
        entry.addNote(row.notes)
        if location.contains("breast") {
            var left = 0.0, right = 0.0
            for text in [row.startCondition, row.endCondition] {
                guard let side = ImportValues.sideTime(text) else { continue }
                if side.side == .left { left += side.minutes } else { right += side.minutes }
            }
            guard left + right > 0 else {
                plan.skip(String(localized: "Breastfeeds with no time on either side", comment: "Import preview: why rows were left out"))
                return
            }
            entry.feedingType = .breast
            entry.leftMinutes = left > 0 ? ImportValues.wholeMinutes(left) : nil
            entry.rightMinutes = right > 0 ? ImportValues.wholeMinutes(right) : nil
            plan.add(entry)
        } else if location.contains("bottle") {
            let contents = row.startCondition
            if let type = ImportValues.bottleType(contents) {
                entry.feedingType = type
                if contents.lowercased().contains("mix") { entry.addNote(String(localized: "Mixed bottle", comment: "Import: a note added to an imported entry")) }
            } else {
                // "Mixed", or nothing said: MyBaby needs one of the two, and the notes keep what was written.
                entry.feedingType = .formula
                entry.addNote(contents.isEmpty
                    ? String(localized: "Bottle contents weren't in the file", comment: "Import: a note added to an imported entry")
                    : String(localized: "Bottle: \(contents)", comment: "Import: what was in a bottle, as the file says"))
            }
            entry.amountML = [row.endCondition, row.startCondition, row.duration]
                .lazy.compactMap { ImportValues.milliliters($0) }.first
            plan.add(entry)
        } else {
            plan.skip(String(localized: "Feeds that don't say breast or bottle", comment: "Import preview: why rows were left out"))
        }
    }

    private static func readDiaper(_ row: Row, start: Date, reader: DateReader, into plan: inout ImportPlan) {
        // "Pee", "Poo", "Both", "Dry", with sizes after a comma or colon.
        let kind = row.endCondition.split(whereSeparator: { $0 == "," || $0 == ":" }).first.map(String.init) ?? ""
        guard let type = ImportValues.diaperType(kind) else {
            plan.skip(String(localized: "Diapers that don't say pee or poo", comment: "Import preview: why rows were left out"))
            return
        }
        var entry = ImportEntry(.activity(.diaper), start: start)
        entry.diaperType = type
        let sizes = row.endCondition.dropFirst(kind.count).trimmingCharacters(in: CharacterSet(charactersIn: ", :"))
        if !sizes.isEmpty { entry.addNote(sizes.replacingOccurrences(of: ":", with: " ")) }
        if entry.diaperType == .dirty || entry.diaperType == .mixed {
            // The color is in Duration (in some exports, End). Only one MyBaby knows is set; the notes keep the rest.
            let colorText = !row.duration.isEmpty ? row.duration : (reader.date(row.end) == nil ? row.end : "")
            if let color = ImportValues.poopColor(colorText) {
                entry.poopColor = color
            } else if !colorText.isEmpty {
                let colorNote = colorText.replacingOccurrences(of: "_", with: " ")
                entry.addNote(String(localized: "Color: \(colorNote)", comment: "Import: a poop color, as the file says"))
            }
            if let consistency = ImportValues.poopConsistency(row.startCondition) {
                entry.poopConsistency = consistency
            } else if !row.startCondition.isEmpty {
                entry.addNote(row.startCondition.replacingOccurrences(of: "_", with: " "))
            }
        }
        entry.addNote(row.startLocation)
        entry.addNote(row.notes)
        plan.add(entry)
    }

    private static func readSleep(_ row: Row, start: Date, end: Date?, into plan: inout ImportPlan) {
        guard let ended = end ?? ImportValues.clockMinutes(row.duration).map({ start.addingTimeInterval($0 * 60) }),
              ended > start
        else {
            // A sleep with no end would show as still going.
            plan.skip(String(localized: "Sleeps without an end time", comment: "Import preview: why rows were left out"))
            return
        }
        var entry = ImportEntry(.activity(.sleep), start: start)
        entry.end = ended
        if !row.startCondition.isEmpty {
            let how = row.startCondition.replacingOccurrences(of: "_", with: " ")
            entry.addNote(String(localized: "Falling asleep: \(how)", comment: "Import: how the baby fell asleep, as the file says"))
        }
        if !row.startLocation.isEmpty {
            let place = row.startLocation.replacingOccurrences(of: "_", with: " ")
            entry.addNote(String(localized: "Where: \(place)", comment: "Import: where the baby slept, as the file says"))
        }
        if !row.endCondition.isEmpty {
            let how = row.endCondition.replacingOccurrences(of: "_", with: " ")
            entry.addNote(String(localized: "Waking: \(how)", comment: "Import: how the baby woke up, as the file says"))
        }
        entry.addNote(row.notes)
        plan.add(entry)
    }

    private static func readPump(_ row: Row, start: Date, end: Date?, into plan: inout ImportPlan) {
        var entry = ImportEntry(.activity(.pumping), start: start)
        // Start Condition is the left side and End Condition the right (see the table above).
        entry.pumpLeftML = ImportValues.milliliters(row.startCondition)
        entry.pumpRightML = ImportValues.milliliters(row.endCondition)
        if entry.pumpLeftML != nil || entry.pumpRightML != nil {
            entry.amountML = (entry.pumpLeftML ?? 0) + (entry.pumpRightML ?? 0)
        }
        let minutes = ImportValues.clockMinutes(row.duration) ?? end.map { $0.timeIntervalSince(start) / 60 }
        if let minutes, minutes > 0 { entry.durationMinutes = Int(minutes.rounded()) }
        entry.addNote(row.notes)
        plan.add(entry)
    }

    private static func readGrowth(_ row: Row, start: Date, into plan: inout ImportPlan) {
        var entry = ImportEntry(.growth, start: start)
        entry.weightKg = ImportValues.kilograms(row.startCondition)
        entry.lengthCm = ImportValues.centimeters(row.startLocation)
        if let head = ImportValues.centimeters(row.endCondition) {
            let headText = head.formatted(.number.precision(.fractionLength(0...1)))
            entry.addNote(String(localized: "Head \(headText) cm", comment: "Import: a head circumference added to the notes"))
        }
        guard entry.weightKg != nil || entry.lengthCm != nil else {
            plan.skip(row.endCondition.isEmpty
                ? String(localized: "Growth entries without a readable weight or length", comment: "Import preview: why rows were left out")
                : String(localized: "Head size only (MyBaby keeps head size with checkups)", comment: "Import preview: why rows were left out"))
            return
        }
        entry.addNote(row.notes)
        plan.add(entry)
    }
}
