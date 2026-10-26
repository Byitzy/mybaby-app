import Foundation

/// Reads Glow Baby's CSV export (Export Report › CSV, emailed as a ZIP of CSV files, one per kind).
///
/// Glow doesn't document the files. The columns here are from real exports published with
/// github.com/jiuguangw/Agenoria (`data/zyw/` and `data/zlw/`, exported in 2020 and 2023, checked on
/// 2026-10-25), whose README describes the export steps:
///
/// - Diapers: `Diaper time, In the diaper, Color, Texture`, e.g. "05/21/2020 8:05:19 AM, pee and poo,
///   yellow, Mushy". In the diaper is pee, poo, pee and poo, or clean.
/// - Bottles: `Time of feeding, Milk type, Amount(ml), Amount(oz)`, with Breast milk or Formula.
/// - Solids: `Time of feeding, Ingredients, Amount, Unit type, Baby's reaction`, e.g. 115 g of Oatmeal.
/// - Sleep: `Begin time, End time`.
/// - Growth: `Date, Weight(kg), Weight(lb), Height(cm), Height(in), Head Circ.(cm), Head Circ.(in)`,
///   dated "2020/01/21".
///
/// The files are told apart by their columns, not their names, since parents often rename them.
/// Times are local, with no time zone, so they're read in the zone the parent picks. Glow can also
/// log breastfeeding and pumping, but no published export shows those files, so they aren't read
/// (the generic importer can take them).
enum GlowBabyImporter {
    private enum Kind {
        case diaper, bottle, solids, sleep, growth
    }

    private static func kind(of table: ImportTable) -> Kind? {
        if table.has("Diaper time", "In the diaper") { return .diaper }
        if table.has("Time of feeding", "Milk type") { return .bottle }
        if table.has("Time of feeding", "Ingredients") { return .solids }
        if table.has("Begin time", "End time") && table.header.count <= 4 { return .sleep }
        if table.has("Date") && (table.column("Weight(kg)", "Weight(lb)", "Height(cm)", "Height(in)") != nil) { return .growth }
        return nil
    }

    static func recognizes(_ table: ImportTable) -> Bool {
        kind(of: table) != nil
    }

    static func read(_ tables: [ImportTable], options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .glow)
        for table in tables {
            guard let tableKind = kind(of: table) else { continue }
            plan.merge(read(table, kind: tableKind, options: options))
        }
        return plan
    }

    private static func read(_ table: ImportTable, kind: Kind, options: ImportOptions) -> ImportPlan {
        var plan = ImportPlan(source: .glow)
        let timeColumn: Int?
        switch kind {
        case .diaper: timeColumn = table.column("Diaper time")
        case .bottle, .solids: timeColumn = table.column("Time of feeding")
        case .sleep: timeColumn = table.column("Begin time")
        case .growth: timeColumn = table.column("Date")
        }
        let found = ImportDates.guess(
            table.rows.map { ImportTable.value($0, timeColumn) },
            preferred: ["M/d/yyyy h:mm:ss a", "M/d/yyyy h:mm a", "yyyy/MM/dd"],
            order: options.dateOrder, timeZone: options.timeZone
        )
        guard let guess = found else {
            plan.rowCount = table.rows.count
            plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"), count: table.rows.count)
            return plan
        }
        plan.dateDescription = ImportDates.describe(guess, timeZone: options.timeZone)
        plan.datesAreAmbiguous = guess.isAmbiguous
        let reader = DateReader(pattern: guess.pattern, timeZone: options.timeZone)

        for row in table.rows {
            plan.rowCount += 1
            guard let date = reader.date(ImportTable.value(row, timeColumn)) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            switch kind {
            case .diaper:
                readDiaper(row, table: table, date: date, into: &plan)
            case .bottle:
                var entry = ImportEntry(.activity(.feeding), start: date)
                let milk = ImportTable.value(row, table.column("Milk type"))
                entry.feedingType = ImportValues.bottleType(milk) ?? .formula
                if ImportValues.bottleType(milk) == nil {
                    entry.addNote(milk.isEmpty
                        ? String(localized: "Bottle contents weren't in the file", comment: "Import: a note added to an imported entry")
                        : String(localized: "Bottle: \(milk)", comment: "Import: what was in a bottle, as the file says"))
                }
                // Glow writes both; the ml column is what was entered or the more precise of the two.
                let ml = Double(ImportTable.value(row, table.column("Amount(ml)")))
                let oz = Double(ImportTable.value(row, table.column("Amount(oz)")))
                entry.amountML = ml ?? oz.map { VolumeUnit.oz.toML($0) }
                plan.add(entry)
            case .solids:
                var entry = ImportEntry(.activity(.feeding), start: date)
                entry.feedingType = .solids
                let food = ImportTable.value(row, table.column("Ingredients"))
                let amount = ImportTable.value(row, table.column("Amount"))
                let unit = ImportTable.value(row, table.column("Unit type"))
                entry.foodDescription = food.isEmpty ? nil : food
                // Solids are weighed (grams), and MyBaby's amount is a volume, so the amount goes in the notes.
                if !amount.isEmpty {
                    entry.addNote(unit.isEmpty
                        ? String(localized: "Amount: \(amount)", comment: "Import: an amount of food, as the file says")
                        : String(localized: "Amount: \(amount) \(unit)", comment: "Import: an amount of food and its unit, as the file says"))
                }
                let reaction = ImportTable.value(row, table.column("Baby's reaction"))
                if !reaction.isEmpty { entry.addNote(String(localized: "Reaction: \(reaction)", comment: "Import: the baby's reaction to a food, as the file says")) }
                plan.add(entry)
            case .sleep:
                guard let end = reader.date(ImportTable.value(row, table.column("End time"))), end > date else {
                    plan.skip(String(localized: "Sleeps without an end time", comment: "Import preview: why rows were left out"))
                    continue
                }
                var entry = ImportEntry(.activity(.sleep), start: date)
                entry.end = end
                plan.add(entry)
            case .growth:
                readGrowth(row, table: table, date: date, into: &plan)
            }
        }
        return plan
    }

    private static func readDiaper(_ row: [String], table: ImportTable, date: Date, into plan: inout ImportPlan) {
        let contents = ImportTable.value(row, table.column("In the diaper"))
        guard let type = ImportValues.diaperType(contents) else {
            plan.skip(String(localized: "Diapers that don't say pee or poo", comment: "Import preview: why rows were left out"))
            return
        }
        var entry = ImportEntry(.activity(.diaper), start: date)
        entry.diaperType = type
        if type == .dirty || type == .mixed {
            let color = ImportTable.value(row, table.column("Color"))
            let texture = ImportTable.value(row, table.column("Texture"))
            entry.poopColor = ImportValues.poopColor(color)
            if entry.poopColor == nil, !color.isEmpty { entry.addNote(String(localized: "Color: \(color)", comment: "Import: a poop color, as the file says")) }
            entry.poopConsistency = ImportValues.poopConsistency(texture)
            if entry.poopConsistency == nil, !texture.isEmpty { entry.addNote(texture) }
        }
        plan.add(entry)
    }

    private static func readGrowth(_ row: [String], table: ImportTable, date: Date, into plan: inout ImportPlan) {
        var entry = ImportEntry(.growth, start: date)
        let kg = Double(ImportTable.value(row, table.column("Weight(kg)")))
        let lb = Double(ImportTable.value(row, table.column("Weight(lb)")))
        let cm = Double(ImportTable.value(row, table.column("Height(cm)")))
        let inches = Double(ImportTable.value(row, table.column("Height(in)")))
        entry.weightKg = kg ?? lb.map { $0 * GrowthUnits.kgPerPound }
        entry.lengthCm = cm ?? inches.map { $0 * GrowthUnits.cmPerInch }
        if let head = Double(ImportTable.value(row, table.column("Head Circ.(cm)"))) {
            let headText = head.formatted(.number.precision(.fractionLength(0...1)))
            entry.addNote(String(localized: "Head \(headText) cm", comment: "Import: a head circumference added to the notes"))
        }
        guard entry.weightKg.map({ $0 > 0 }) == true || entry.lengthCm.map({ $0 > 0 }) == true else {
            plan.skip(String(localized: "Growth entries without a weight or length", comment: "Import preview: why rows were left out"))
            return
        }
        if entry.weightKg.map({ $0 <= 0 }) == true { entry.weightKg = nil }
        if entry.lengthCm.map({ $0 <= 0 }) == true { entry.lengthCm = nil }
        plan.add(entry)
    }
}
