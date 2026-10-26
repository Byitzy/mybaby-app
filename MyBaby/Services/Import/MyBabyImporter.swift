import Foundation

/// Reads MyBaby's own CSV export (Settings › Your data › Export all data), so a parent can move the
/// log to another iPhone without iCloud: export on one, AirDrop or save the files, import on the other.
///
/// The columns are the ones `Exporter` writes, so this is a round trip:
/// - `MyBaby-log.csv`: every feed, diaper, sleep, bath, medicine, pumping session and temperature.
/// - `MyBaby-growth.csv`, `MyBaby-vaccines.csv`: measurements and vaccines.
/// - `MyBaby-tracking.csv`: times marked as not tracked, nothing happened or caught up. These matter as
///   much as the entries: without them, a stretch the other iPhone knew wasn't tracked would read as
///   nothing happening.
///
/// Times are written in the exporting iPhone's time zone without saying which ("2026-10-25 14:05"),
/// so they're read in the zone the parent picks, this iPhone's by default. Appointments, the diary,
/// allergies and reactions are in the export too, but aren't brought back by an import yet: their
/// rows are counted as skipped, with the reason.
enum MyBabyImporter {
    private enum Kind {
        case log, growth, vaccines, tracking, appointments, diary, allergies, reactions
    }

    private static func kind(of table: ImportTable) -> Kind? {
        if table.has("Category", "Start", "End", "Type", "Amount (ml)") { return .log }
        if table.has("Date", "Weight (kg)", "Length (cm)") { return .growth }
        if table.has("Vaccine", "Date", "Status", "Lot number") { return .vaccines }
        if table.has("Start", "End", "Kind", "Reason") { return .tracking }
        if table.has("Appointment", "Date", "Questions") { return .appointments }
        if table.has("Date", "Kind", "Title", "Text", "Written by") { return .diary }
        if table.has("Allergen", "Status", "Severity") { return .allergies }
        if table.has("Date", "What they had", "Symptoms") { return .reactions }
        return nil
    }

    static func recognizes(_ table: ImportTable) -> Bool {
        kind(of: table) != nil
    }

    static func read(_ tables: [ImportTable], options: ImportOptions, plan nightPlan: NightPlan = .load()) -> ImportPlan {
        var plan = ImportPlan(source: .mybaby)
        // Exactly what `Exporter` writes, in any time zone the parent picks.
        let reader = DateReader(pattern: DatePattern(format: "yyyy-MM-dd HH:mm", order: .yearFirst), timeZone: options.timeZone)
        let zone = options.timeZone.localizedName(for: .generic, locale: .current) ?? options.timeZone.identifier
        plan.dateDescription = String(localized: "Times are read in \(zone), as MyBaby exports them.", comment: "Import preview; a time zone's name")
        for table in tables {
            guard let tableKind = kind(of: table) else { continue }
            var part = ImportPlan(source: .mybaby)
            switch tableKind {
            case .log: readLog(table, reader: reader, nightPlan: nightPlan, into: &part)
            case .growth: readGrowth(table, reader: reader, into: &part)
            case .vaccines: readVaccines(table, reader: reader, into: &part)
            case .tracking: readTracking(table, reader: reader, into: &part)
            case .appointments:
                part.rowCount = table.rows.count
                part.skip(String(localized: "Appointments (not brought over by an import yet)", comment: "Import preview: why rows were left out"), count: table.rows.count)
            case .diary:
                part.rowCount = table.rows.count
                part.skip(String(localized: "Diary entries (not brought over by an import yet)", comment: "Import preview: why rows were left out"), count: table.rows.count)
            case .allergies:
                part.rowCount = table.rows.count
                part.skip(String(localized: "Allergies (not brought over by an import yet)", comment: "Import preview: why rows were left out"), count: table.rows.count)
            case .reactions:
                part.rowCount = table.rows.count
                part.skip(String(localized: "Reactions (not brought over by an import yet)", comment: "Import preview: why rows were left out"), count: table.rows.count)
            }
            plan.merge(part)
        }
        return plan
    }

    // MARK: The log

    // Not localized: `Exporter` writes each value's `exportName` (its English title) into the CSV, so a
    // file reads back on any iPhone whatever its language. The localized `title` is accepted too, for a
    // file from an older build or one edited by hand in the parent's language.

    private static func readLog(_ table: ImportTable, reader: DateReader, nightPlan: NightPlan, into plan: inout ImportPlan) {
        func column(_ name: String) -> Int? { table.column(name) }
        let category = column("Category"), start = column("Start"), end = column("End"), type = column("Type")
        let amount = column("Amount (ml)"), left = column("Left breast (min)"), right = column("Right breast (min)")
        let food = column("Food"), color = column("Poop color"), consistency = column("Poop consistency")
        let medicine = column("Medicine"), dose = column("Dose"), handledBy = column("Handled by"), notes = column("Notes")
        let pumpLeft = column("Pumped left (ml)"), pumpRight = column("Pumped right (ml)"), duration = column("Duration (min)")
        let temperature = column("Temperature (°C)"), method = column("Temperature method"), symptoms = column("Symptoms")
        let approximate = column("Approximate"), allergens = column("Allergens")

        for row in table.rows {
            plan.rowCount += 1
            let value = { (column: Int?) in ImportTable.value(row, column) }
            let categoryText = value(category)
            guard let kind = ActivityKind.allCases.first(where: { $0.exportName == categoryText || $0.title == categoryText }) else {
                plan.skip(categoryText.isEmpty
                    ? String(localized: "Rows without a category", comment: "Import preview: why rows were left out")
                    : String(localized: "\(categoryText) (not a kind MyBaby knows)", comment: "Import preview; a kind of entry, as the file names it"))
                continue
            }
            guard let date = reader.date(value(start)) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            var entry = ImportEntry(.activity(kind), start: date)
            entry.end = reader.date(value(end))
            entry.notes = value(notes)
            // Not localized: the export writes "Yes" in English.
            entry.isApproximate = value(approximate).lowercased() == "yes"
            let handler = value(handledBy)
            entry.caregiver = Parent.allCases.first { !handler.isEmpty && (nightPlan.exportName(of: $0) == handler || nightPlan.name(of: $0) == handler) }
            let typeText = value(type)
            switch kind {
            case .feeding:
                guard let feeding = FeedingType.allCases.first(where: { $0.exportName == typeText || $0.title == typeText }) else {
                    plan.skip(String(localized: "Feeds without a type", comment: "Import preview: why rows were left out"))
                    continue
                }
                entry.feedingType = feeding
                entry.amountML = Double(value(amount))
                entry.leftMinutes = Int(value(left))
                entry.rightMinutes = Int(value(right))
                let foodText = value(food)
                entry.foodDescription = foodText.isEmpty ? nil : foodText
                entry.allergenIDs = Set(value(allergens).split(separator: ";").compactMap {
                    Self.allergen(named: $0.trimmingCharacters(in: .whitespaces))?.id
                })
            case .diaper:
                guard let diaper = DiaperType.allCases.first(where: { $0.exportName == typeText || $0.title == typeText }) else {
                    plan.skip(String(localized: "Diapers without a type", comment: "Import preview: why rows were left out"))
                    continue
                }
                entry.diaperType = diaper
                entry.poopColor = PoopColor(rawValue: value(color).lowercased())
                entry.poopConsistency = PoopConsistency(rawValue: value(consistency).lowercased())
            case .sleep:
                // A sleep exported while it was still going has no end; importing it would start a
                // sleep that never ends on this iPhone.
                guard let ended = entry.end, ended > date else {
                    plan.skip(String(localized: "Sleeps without an end time", comment: "Import preview: why rows were left out"))
                    continue
                }
            case .medication:
                entry.medicationName = value(medicine)
                entry.dosage = value(dose)
            case .pumping:
                entry.amountML = Double(value(amount))
                entry.pumpLeftML = Double(value(pumpLeft))
                entry.pumpRightML = Double(value(pumpRight))
                entry.durationMinutes = Int(value(duration))
            case .temperature:
                guard let celsius = Double(value(temperature)) else {
                    plan.skip(String(localized: "Temperatures without a reading", comment: "Import preview: why rows were left out"))
                    continue
                }
                entry.temperatureC = celsius
                let methodText = value(method)
                entry.temperatureMethod = TemperatureMethod.allCases.first { $0.exportName == methodText || $0.title == methodText }
                let listed = Set(value(symptoms).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) })
                entry.symptoms = Symptom.allCases.filter { listed.contains($0.exportName) || listed.contains($0.title) }
            case .bath:
                break
            }
            if kind != .sleep { entry.end = nil }
            plan.add(entry)
        }
    }

    // MARK: Growth, vaccines and marked times

    private static func readGrowth(_ table: ImportTable, reader: DateReader, into plan: inout ImportPlan) {
        for row in table.rows {
            plan.rowCount += 1
            guard let date = reader.date(ImportTable.value(row, table.column("Date"))) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            var entry = ImportEntry(.growth, start: date)
            entry.weightKg = Double(ImportTable.value(row, table.column("Weight (kg)")))
            entry.lengthCm = Double(ImportTable.value(row, table.column("Length (cm)")))
            entry.notes = ImportTable.value(row, table.column("Notes"))
            guard entry.weightKg != nil || entry.lengthCm != nil else {
                plan.skip(String(localized: "Growth entries without a weight or length", comment: "Import preview: why rows were left out"))
                continue
            }
            plan.add(entry)
        }
    }

    private static func readVaccines(_ table: ImportTable, reader: DateReader, into plan: inout ImportPlan) {
        for row in table.rows {
            plan.rowCount += 1
            let name = ImportTable.value(row, table.column("Vaccine"))
            guard let date = reader.date(ImportTable.value(row, table.column("Date"))) else {
                plan.skip(String(localized: "Rows with a date MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            guard !name.isEmpty else {
                plan.skip(String(localized: "Vaccines without a name", comment: "Import preview: why rows were left out"))
                continue
            }
            var entry = ImportEntry(.vaccine, start: date)
            entry.vaccineName = name
            // Not localized: the export writes "Given" or "Due" in English.
            entry.vaccineIsGiven = ImportTable.value(row, table.column("Status")) != "Due"
            entry.doseLabel = ImportTable.value(row, table.column("Dose"))
            entry.provider = ImportTable.value(row, table.column("Provider"))
            entry.lotNumber = ImportTable.value(row, table.column("Lot number"))
            entry.notes = ImportTable.value(row, table.column("Notes"))
            // Columns added later; empty in older exports.
            entry.productName = ImportTable.value(row, table.column("Product"))
            entry.doseAmount = Double(ImportTable.value(row, table.column("Dose amount")))
            entry.doseUnit = ImportTable.value(row, table.column("Dose unit"))
            entry.expiryDate = reader.date(ImportTable.value(row, table.column("Expiry date")))
            plan.add(entry)
        }
    }

    private static func readTracking(_ table: ImportTable, reader: DateReader, into plan: inout ImportPlan) {
        for row in table.rows {
            plan.rowCount += 1
            guard let start = reader.date(ImportTable.value(row, table.column("Start"))),
                  let end = reader.date(ImportTable.value(row, table.column("End"))), end > start
            else {
                plan.skip(String(localized: "Marked times MyBaby couldn't read", comment: "Import preview: why rows were left out"))
                continue
            }
            let kindText = ImportTable.value(row, table.column("Kind"))
            guard let kind = TrackingPeriodKind.allCases.first(where: { $0.exportName == kindText || $0.title == kindText }) else {
                plan.skip(String(localized: "Marked times of an unknown kind", comment: "Import preview: why rows were left out"))
                continue
            }
            var entry = ImportEntry(.trackingPeriod, start: start)
            entry.end = end
            entry.trackingKind = kind
            let reasonText = ImportTable.value(row, table.column("Reason"))
            entry.trackingReason = TrackingPeriodReason.allCases.first { $0.exportName == reasonText || $0.title == reasonText }
            entry.notes = ImportTable.value(row, table.column("Notes"))
            plan.add(entry)
        }
    }

    /// A common allergen by the name the export wrote. The export writes the English name ("Tree nuts"),
    /// which matches the allergen's id once the spaces are taken out, whatever language the app is in now.
    private static func allergen(named name: String) -> CommonAllergen? {
        let key = name.replacingOccurrences(of: " ", with: "").lowercased()
        return CommonAllergen.named(name) ?? CommonAllergen.all.first { $0.id.lowercased() == key }
    }
}
