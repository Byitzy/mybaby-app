import Foundation

/// A column of a CSV file the parent can point MyBaby at, on the mapping screen.
enum GenericField: String, CaseIterable, Identifiable, Sendable {
    case dateTime, timeOfDay, endTime, type, amount, unit, duration, side, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateTime: return String(localized: "Date and time", comment: "Import: a column to match in a CSV file")
        case .timeOfDay: return String(localized: "Time, if it has its own column", comment: "Import: a column to match in a CSV file")
        case .endTime: return String(localized: "End time", comment: "Import: a column to match in a CSV file")
        case .type: return String(localized: "Type", comment: "Import: a column to match in a CSV file")
        case .amount: return String(localized: "Amount", comment: "Import: a column to match in a CSV file")
        case .unit: return String(localized: "Unit", comment: "Import: a column to match in a CSV file")
        case .duration: return String(localized: "Duration", comment: "Import: a column to match in a CSV file")
        case .side: return String(localized: "Side", comment: "Import: a column to match in a CSV file")
        case .notes: return String(localized: "Notes", comment: "Import: a column to match in a CSV file")
        }
    }

    /// Header words that usually mean this column, most telling first.
    /// Not localized: they're matched against the headers other apps write, which are English.
    fileprivate var keywords: [String] {
        switch self {
        case .dateTime: return ["start time", "start date", "start", "date/time", "datetime", "date and time", "begin time", "begin", "time of feeding", "timestamp", "date", "when", "time"]
        case .timeOfDay: return ["time"]
        case .endTime: return ["end time", "end date", "end", "stop time", "stop", "finish", "until", "woke"]
        case .type: return ["type", "activity", "category", "event", "kind", "entry", "what"]
        case .amount: return ["amount", "volume", "quantity", "qty", "value", "total", "ml", "oz", "reading"]
        case .unit: return ["unit", "units", "unit type"]
        case .duration: return ["total duration", "duration", "minutes", "mins", "length", "total time", "time spent"]
        case .side: return ["side", "start side", "breast side"]
        case .notes: return ["notes", "note", "comments", "comment", "details", "description", "memo"]
        }
    }
}

/// Which column holds what, and how to read values that don't say their unit.
struct GenericMapping: Sendable {
    var columns: [GenericField: Int] = [:]
    /// What every row is, for a file with no type column (one file per kind, like Baby Tracker's).
    var everyRow: ImportCategory?
    /// How dates are written. `nil` until guessed from the file.
    var datePattern: DatePattern?
    var volumeUnit: VolumeUnit = .ml
    var durationUnit: DurationUnit = .minutes

    subscript(field: GenericField) -> Int? {
        get { columns[field] }
        set { columns[field] = newValue }
    }

    /// Columns matched from their headers, so the parent usually only has to check them.
    static func guess(for table: ImportTable, options: ImportOptions) -> GenericMapping {
        var mapping = GenericMapping()
        mapping.volumeUnit = options.volumeUnit
        var used = Set<Int>()
        let keys = table.header.map(ImportTable.key)
        // "Unit type" is a unit, not a type; durations before amounts, so "Total duration" isn't an amount.
        let order: [GenericField] = [.dateTime, .endTime, .unit, .type, .duration, .side, .notes, .amount]
        for field in order {
            if let index = match(field.keywords, in: keys, excluding: used) {
                mapping[field] = index
                used.insert(index)
            }
        }
        // "Date" and "Time" as two columns.
        if let dateColumn = mapping[.dateTime], keys[dateColumn].contains("date"), !keys[dateColumn].contains("time"),
           let time = match(GenericField.timeOfDay.keywords, in: keys, excluding: used, exactOnly: true) {
            mapping[.timeOfDay] = time
        }
        // Amounts that say their unit in the header, "Amount (oz)".
        if let amount = mapping[.amount], let unit = ImportValues.volumeUnit(unitInBrackets(keys[amount]) ?? "") {
            mapping.volumeUnit = unit
        }
        if let duration = mapping[.duration] {
            let header = keys[duration]
            if header.contains("sec") { mapping.durationUnit = .seconds } else if header.contains("hour") || header.contains("(h") { mapping.durationUnit = .hours }
        }
        if mapping[.type] == nil {
            mapping.everyRow = GenericCSVImporter.category(forText: table.name)
        }
        mapping.datePattern = GenericCSVImporter.dateGuess(table, mapping: mapping, options: options)?.pattern
        return mapping
    }

    private static func match(_ keywords: [String], in keys: [String], excluding used: Set<Int>, exactOnly: Bool = false) -> Int? {
        for keyword in keywords {
            if let index = keys.indices.first(where: { !used.contains($0) && keys[$0] == keyword }) { return index }
        }
        guard !exactOnly else { return nil }
        for keyword in keywords where keyword.count > 2 {
            if let index = keys.indices.first(where: { !used.contains($0) && keys[$0].contains(keyword) }) { return index }
        }
        return nil
    }

    /// "oz" from "amount (oz)".
    private static func unitInBrackets(_ header: String) -> String? {
        guard let open = header.firstIndex(of: "("), let close = header[open...].firstIndex(of: ")") else { return nil }
        return String(header[header.index(after: open)..<close])
    }
}

/// Reads any CSV with the columns the parent matched on the mapping screen: the importer for apps
/// MyBaby doesn't know (and that don't document their exports, like Baby Tracker, Baby Connect,
/// Sprout Baby and Baby Daybook), and for spreadsheets kept by hand.
///
/// Each row's kind comes from its Type column (or, with none, the "Every row is a…" choice), read from
/// the words people use: "Bottle", "Formula", "Breastfeed", "Nursing", "Wet diaper", "Nap", "Pump",
/// "Vitamin D"… Rows whose kind can't be told are skipped and counted, never guessed.
enum GenericCSVImporter {
    static func read(_ table: ImportTable, mapping: GenericMapping, options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .generic)
        guard mapping[.dateTime] != nil else {
            plan.rowCount = table.rows.count
            plan.skip(String(localized: "No date column was chosen", comment: "Import preview: why rows were left out"), count: table.rows.count)
            return plan
        }
        let guess = dateGuess(table, mapping: mapping, options: options)
        guard let pattern = mapping.datePattern ?? guess?.pattern else {
            plan.rowCount = table.rows.count
            plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"), count: table.rows.count)
            return plan
        }
        if let guess {
            let shown = DateGuess(pattern: pattern, isAmbiguous: guess.isAmbiguous, readCount: guess.readCount, sampleCount: guess.sampleCount, example: guess.example)
            plan.dateDescription = ImportDates.describe(shown, timeZone: options.timeZone)
            plan.datesAreAmbiguous = guess.isAmbiguous && mapping.datePattern == nil
        }
        let reader = DateReader(pattern: pattern, timeZone: options.timeZone)

        for row in table.rows {
            plan.rowCount += 1
            let value = { (field: GenericField) in ImportTable.value(row, mapping[field]) }
            guard let start = reader.date(dateText(row, mapping: mapping)) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            let typeText = value(.type)
            let amountText = value(.amount)
            let unitText = value(.unit)
            let durationText = value(.duration)
            let notes = value(.notes)
            let end = Self.end(reader.date(endText(row, mapping: mapping)), after: start, timeOnly: mapping[.timeOfDay] != nil)
            let minutes = ImportValues.minutes(durationText, defaultUnit: mapping.durationUnit)
                ?? end.map { $0.timeIntervalSince(start) / 60 }
            let measured = [amountText, unitText].filter { !$0.isEmpty }.joined(separator: " ")

            let found: ImportCategory?
            if let everyRow = mapping.everyRow, mapping[.type] == nil {
                found = everyRow
            } else if let fromText = Self.category(forText: typeText) {
                found = fromText
            } else if typeText.lowercased().contains("feed") {
                // A plain "Feed": a bottle when it has an amount, a breastfeed when it has a duration.
                found = !amountText.isEmpty ? .bottle : (minutes != nil ? .breastfeed : nil)
            } else {
                found = nil
            }
            guard let category = found else {
                plan.skip(typeText.isEmpty
                    ? String(localized: "Rows without a type", comment: "Import preview: why rows were left out")
                    : String(localized: "\(typeText) (MyBaby couldn't tell what this is)", comment: "Import preview; a kind of entry, as the file names it"))
                continue
            }

            switch category {
            case .breastfeed:
                guard let minutes, minutes > 0 else {
                    plan.skip(String(localized: "Breastfeeds without a duration", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.feeding), start: start)
                entry.feedingType = .breast
                let side = ImportedSide(word: value(.side)) ?? ImportedSide(word: typeText)
                switch side {
                case .left?:
                    entry.leftMinutes = ImportValues.wholeMinutes(minutes)
                case .right?:
                    entry.rightMinutes = ImportValues.wholeMinutes(minutes)
                case .both?, nil:
                    // MyBaby keeps minutes per side; with only a total, it's split evenly and the notes say so.
                    entry.leftMinutes = ImportValues.wholeMinutes(minutes / 2)
                    entry.rightMinutes = ImportValues.wholeMinutes(minutes / 2)
                    entry.addNote(side == nil
                        ? String(localized: "Side not in the file; the time is split evenly", comment: "Import: a note added to an imported entry")
                        : String(localized: "Both sides; the time is split evenly", comment: "Import: a note added to an imported entry"))
                }
                entry.addNote(notes)
                plan.add(entry)
            case .bottle:
                var entry = ImportEntry(.activity(.feeding), start: start)
                let contents = [typeText, value(.side), notes].joined(separator: " ")
                entry.feedingType = ImportValues.bottleType(contents) ?? .formula
                if ImportValues.bottleType(contents) == nil { entry.addNote(String(localized: "Bottle contents weren't in the file", comment: "Import: a note added to an imported entry")) }
                entry.amountML = ImportValues.milliliters(measured, defaultUnit: mapping.volumeUnit)
                entry.addNote(notes)
                plan.add(entry)
            case .solids:
                var entry = ImportEntry(.activity(.feeding), start: start)
                entry.feedingType = .solids
                let named = Self.category(forText: typeText) == .solids && !["solids", "solid", "solid food", "food"].contains(typeText.lowercased())
                entry.foodDescription = named ? typeText : (notes.isEmpty ? nil : notes)
                if named { entry.addNote(notes) }
                if !measured.isEmpty { entry.addNote(String(localized: "Amount: \(measured)", comment: "Import: an amount of food, as the file says")) }
                plan.add(entry)
            case .diaper:
                guard let diaper = ImportValues.diaperType(typeText) ?? ImportValues.diaperType(amountText)
                    ?? ImportValues.diaperType(value(.side)) ?? ImportValues.diaperType(notes)
                else {
                    plan.skip(String(localized: "Diapers that don't say wet or dirty", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.diaper), start: start)
                entry.diaperType = diaper
                entry.addNote(notes)
                plan.add(entry)
            case .sleep:
                guard let ended = end ?? minutes.flatMap({ $0 > 0 ? start.addingTimeInterval($0 * 60) : nil }) else {
                    plan.skip(String(localized: "Sleeps without an end time or duration", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.sleep), start: start)
                entry.end = ended
                entry.addNote(notes)
                plan.add(entry)
            case .pumping:
                var entry = ImportEntry(.activity(.pumping), start: start)
                let total = ImportValues.milliliters(measured, defaultUnit: mapping.volumeUnit)
                switch ImportedSide(word: value(.side)) {
                case .left?: entry.pumpLeftML = total
                case .right?: entry.pumpRightML = total
                default: break
                }
                entry.amountML = total
                if let minutes, minutes > 0 { entry.durationMinutes = Int(minutes.rounded()) }
                entry.addNote(notes)
                plan.add(entry)
            case .bath:
                var entry = ImportEntry(.activity(.bath), start: start)
                entry.addNote(notes)
                plan.add(entry)
            case .medicine:
                var entry = ImportEntry(.activity(.medication), start: start)
                let generic = ["medicine", "medication", "meds", "med", "medicines"].contains(typeText.lowercased())
                if !typeText.isEmpty, !generic {
                    entry.medicationName = typeText
                    entry.addNote(notes)
                } else {
                    entry.medicationName = notes.isEmpty ? String(localized: "Medicine", comment: "Import: the name given to a dose when the file has none") : notes
                }
                entry.dosage = measured.isEmpty ? nil : measured
                plan.add(entry)
            case .temperature:
                let unit: TemperatureUnit? = unitText.lowercased().contains("f") ? .fahrenheit : (unitText.lowercased().contains("c") ? .celsius : nil)
                guard let celsius = ImportValues.celsius(amountText.isEmpty ? typeText : amountText, defaultUnit: unit) else {
                    plan.skip(String(localized: "Temperatures without a reading", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.temperature), start: start)
                entry.temperatureC = celsius
                entry.addNote(notes)
                plan.add(entry)
            case .growth:
                var entry = ImportEntry(.growth, start: start)
                let kind = typeText.lowercased()
                let lengthLike = kind.contains("height") || kind.contains("length")
                if lengthLike {
                    entry.lengthCm = ImportValues.centimeters(measured)
                } else {
                    entry.weightKg = ImportValues.kilograms(measured)
                    if entry.weightKg == nil, !kind.contains("weight") { entry.lengthCm = ImportValues.centimeters(measured) }
                }
                guard entry.weightKg != nil || entry.lengthCm != nil else {
                    plan.skip(String(localized: "Weights and lengths without a unit MyBaby knows", comment: "Import preview: why rows were left out"))
                    continue
                }
                entry.addNote(notes)
                plan.add(entry)
            case .vaccine, .markedTime:
                let kind = category.title
                plan.skip(String(localized: "\(kind) (only read from MyBaby's own export)", comment: "Import preview; a kind of entry, like Vaccines"))
            }
        }
        return plan
    }

    // MARK: Reading the row

    /// The end, when it's after the start. An end that's only a time, before the start's time, is the next
    /// morning (a sleep from 10 PM to 6 AM).
    private static func end(_ end: Date?, after start: Date, timeOnly: Bool) -> Date? {
        guard let end else { return nil }
        if end > start { return end }
        if timeOnly, end > start.addingTimeInterval(-86_400) {
            return Calendar.current.date(byAdding: .day, value: 1, to: end)
        }
        return nil
    }

    static func dateText(_ row: [String], mapping: GenericMapping) -> String {
        let date = ImportTable.value(row, mapping[.dateTime])
        let time = ImportTable.value(row, mapping[.timeOfDay])
        return time.isEmpty ? date : "\(date) \(time)"
    }

    /// The end, which may be only a time on the start's day, when the date and time have their own columns.
    private static func endText(_ row: [String], mapping: GenericMapping) -> String {
        let end = ImportTable.value(row, mapping[.endTime])
        guard !end.isEmpty, mapping[.timeOfDay] != nil, !end.contains("/"), !end.contains("-"), !end.contains(".") else { return end }
        return "\(ImportTable.value(row, mapping[.dateTime])) \(end)"
    }

    /// How the date column is written, guessed from its values.
    static func dateGuess(_ table: ImportTable, mapping: GenericMapping, options: ImportOptions) -> DateGuess? {
        guard mapping[.dateTime] != nil else { return nil }
        let samples = table.rows.prefix(400).map { dateText($0, mapping: mapping) }
        return ImportDates.guess(samples, order: options.dateOrder, timeZone: options.timeZone)
    }

    // MARK: Words

    /// The kind of entry a type (or file name) names, from the words other apps use. `nil` when it doesn't say.
    static func category(forText text: String) -> ImportCategory? {
        let words = text.lowercased()
        guard !words.isEmpty else { return nil }
        func has(_ options: [String]) -> Bool { options.contains { words.contains($0) } }
        // Pumped milk given in a bottle ("Pumped", Baby Tracker's name for it) is a bottle, not a pumping session.
        if has(["pumped", "bottle", "formula", "expressed", "breast milk", "breastmilk"]) { return .bottle }
        if has(["pump"]) { return .pumping }
        if has(["breast", "nurs", "left", "right"]) { return .breastfeed }
        if has(["solid", "food", "meal", "puree", "purée", "snack", "supplement"]) { return .solids }
        if has(["diaper", "nappy", "nappies", "pee", "poo", "wet", "dirty", "stool"]) { return .diaper }
        if has(["sleep", "nap"]) { return .sleep }
        if has(["bath"]) { return .bath }
        if has(["temp", "fever"]) { return .temperature }
        if has(["medic", "meds", "vitamin", "drops", "dose", "tylenol", "paracetamol", "ibuprofen", "acetaminophen", "motrin", "calpol"]) { return .medicine }
        if has(["weight", "height", "length", "growth"]) { return .growth }
        return nil
    }
}
