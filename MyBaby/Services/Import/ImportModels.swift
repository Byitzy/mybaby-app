import Foundation

// The shapes every importer produces, before anything touches Core Data. Parsing a file gives an
// `ImportPlan`: the entries it would add, plus what was skipped and why. The preview shows the plan,
// and `ImportWriter` turns it into entries only once the parent taps Import. Keeping this as plain
// values means a plan can be worked out off the main thread, shown, thrown away and worked out again
// (another time zone, another date order) without anything being saved.

/// Which app a file came from, and so which reader understands it.
enum ImportSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case mybaby, huckleberry, glow, nara, generic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mybaby: return "MyBaby"
        case .huckleberry: return "Huckleberry"
        case .glow: return "Glow Baby"
        case .nara: return "Nara Baby"
        case .generic: return String(localized: "Another app", comment: "Import source: an app MyBaby has no reader of its own for")
        }
    }

    /// How to get the file out of the other app, shown under the source picker.
    var howToExport: String {
        switch self {
        case .mybaby:
            return String(
                localized: "On the other iPhone, go to More › Settings › Export all data (CSV) and send the files to this one, for example with AirDrop or Files. Pick all of them together: the log, growth, vaccines and marked times.",
                comment: "How to export from another app. Menu names are the other app's own, in English"
            )
        case .huckleberry:
            return String(
                localized: "In Huckleberry, open the child's profile and choose Export tracking data as CSV. The link arrives by email; save the file to Files first.",
                comment: "How to export from another app. Menu names are the other app's own, in English"
            )
        case .glow:
            return String(
                localized: "In Glow Baby, choose Export Report › CSV, pick All and the time frame, and export. Glow emails a ZIP of CSV files; save it to Files and pick the ZIP.",
                comment: "How to export from another app. Menu names are the other app's own, in English"
            )
        case .nara:
            return String(
                localized: "In Nara Baby, go to Activity, tap the child's picture, then Export Data. Save the CSV to Files.",
                comment: "How to export from another app. Menu names are the other app's own, in English"
            )
        case .generic:
            return String(
                localized: "Export a CSV from the other app, for example Baby Tracker, Baby Connect, Sprout Baby or Baby Daybook, and match its columns on the next screen.",
                comment: "How to export from another app. Menu names are the other app's own, in English"
            )
        }
    }
}

/// What an imported entry is, for the counts in the preview and the summary.
enum ImportCategory: String, CaseIterable, Identifiable, Sendable {
    case breastfeed, bottle, solids, diaper, sleep, pumping, bath, medicine, temperature, growth, vaccine, markedTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breastfeed: return String(localized: "Breastfeeds", comment: "Import: a kind of entry, counted")
        case .bottle: return String(localized: "Bottles", comment: "Import: a kind of entry, counted")
        case .solids: return String(localized: "Solids", comment: "Import: a kind of entry")
        case .diaper: return String(localized: "Diapers", comment: "Import: a kind of entry, counted")
        case .sleep: return String(localized: "Sleeps", comment: "Import: a kind of entry, counted")
        case .pumping: return String(localized: "Pumping sessions", comment: "Import: a kind of entry, counted")
        case .bath: return String(localized: "Baths", comment: "Import: a kind of entry, counted")
        case .medicine: return String(localized: "Medicine doses", comment: "Import: a kind of entry, counted")
        case .temperature: return String(localized: "Temperatures", comment: "Import: a kind of entry, counted")
        case .growth: return String(localized: "Growth measurements", comment: "Import: a kind of entry, counted")
        case .vaccine: return String(localized: "Vaccines", comment: "Import: a kind of entry, counted")
        case .markedTime: return String(localized: "Marked times", comment: "Import: a kind of entry, counted")
        }
    }

    /// One of them, for the generic importer's "Every row is a…" choice.
    var singularTitle: String {
        switch self {
        case .breastfeed: return String(localized: "Breastfeed", comment: "Import: what every row of a file is")
        case .bottle: return String(localized: "Bottle", comment: "Import: what every row of a file is")
        case .solids: return String(localized: "Solids", comment: "Import: a kind of entry")
        case .diaper: return String(localized: "Diaper", comment: "Import: what every row of a file is")
        case .sleep: return String(localized: "Sleep", comment: "Import: what every row of a file is")
        case .pumping: return String(localized: "Pumping", comment: "Import: what every row of a file is")
        case .bath: return String(localized: "Bath", comment: "Import: what every row of a file is")
        case .medicine: return String(localized: "Medicine", comment: "Import: what every row of a file is")
        case .temperature: return String(localized: "Temperature", comment: "Import: what every row of a file is")
        case .growth: return String(localized: "Growth", comment: "Import: what every row of a file is")
        case .vaccine: return String(localized: "Vaccine", comment: "Import: what every row of a file is")
        case .markedTime: return String(localized: "Marked time", comment: "Import: what every row of a file is")
        }
    }

    var emoji: String {
        switch self {
        case .breastfeed: return FeedingType.breast.emoji
        case .bottle: return FeedingType.formula.emoji
        case .solids: return FeedingType.solids.emoji
        case .diaper: return ActivityKind.diaper.emoji
        case .sleep: return ActivityKind.sleep.emoji
        case .pumping: return ActivityKind.pumping.emoji
        case .bath: return ActivityKind.bath.emoji
        case .medicine: return ActivityKind.medication.emoji
        case .temperature: return ActivityKind.temperature.emoji
        case .growth: return "📏"
        case .vaccine: return "💉"
        case .markedTime: return "🕒"
        }
    }

    /// The kinds a generic CSV row can be mapped to. Vaccines and marked times only come from MyBaby's own export.
    static let genericChoices: [ImportCategory] = [
        .breastfeed, .bottle, .solids, .diaper, .sleep, .pumping, .bath, .medicine, .temperature, .growth,
    ]
}

/// One entry the file would add, in MyBaby's own terms and units (ml, kg, cm, °C, minutes).
struct ImportEntry: Identifiable, Sendable {
    enum Kind: Sendable, Equatable {
        case activity(ActivityKind)
        case growth
        case vaccine
        case trackingPeriod
    }

    /// The position in the plan, so the preview and the duplicate check can refer to it.
    var id = 0
    var kind: Kind
    var start: Date
    /// When a sleep (or a pumping session, or a marked time) ended.
    var end: Date?
    var notes = ""
    /// The baby the file names for this row, when it has more than one (Nara Baby).
    var sourceBaby: String?

    // Feeding
    var feedingType: FeedingType?
    var amountML: Double?
    var leftMinutes: Int?
    var rightMinutes: Int?
    var foodDescription: String?
    var allergenIDs: Set<String> = []

    // Diaper
    var diaperType: DiaperType?
    var poopColor: PoopColor?
    var poopConsistency: PoopConsistency?

    // Medicine
    var medicationName: String?
    var dosage: String?

    // Pumping
    var pumpLeftML: Double?
    var pumpRightML: Double?
    var durationMinutes: Int?

    // Temperature
    var temperatureC: Double?
    var temperatureMethod: TemperatureMethod?
    var symptoms: [Symptom] = []

    // From MyBaby's own export
    var isApproximate = false
    var caregiver: Parent?

    // Growth
    var weightKg: Double?
    var lengthCm: Double?

    // Vaccine
    var vaccineName = ""
    var vaccineIsGiven = true
    var doseLabel = ""
    var provider = ""
    var lotNumber = ""
    var productName = ""
    var doseAmount: Double?
    var doseUnit = ""
    var expiryDate: Date?

    // Marked time
    var trackingKind: TrackingPeriodKind?
    var trackingReason: TrackingPeriodReason?

    init(_ kind: Kind, start: Date) {
        self.kind = kind
        self.start = start
    }

    var category: ImportCategory {
        switch kind {
        case .activity(let activityKind):
            switch activityKind {
            case .feeding:
                switch feedingType {
                case .breast: return .breastfeed
                case .solids: return .solids
                default: return .bottle
                }
            case .diaper: return .diaper
            case .sleep: return .sleep
            case .bath: return .bath
            case .medication: return .medicine
            case .pumping: return .pumping
            case .temperature: return .temperature
            }
        case .growth: return .growth
        case .vaccine: return .vaccine
        case .trackingPeriod: return .markedTime
        }
    }

    /// Adds a line to the notes, keeping what's already there.
    mutating func addNote(_ text: String?) {
        let line = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        notes = notes.isEmpty ? line : notes + "\n" + line
    }

    /// "Bottle (formula)", "Wet diaper", "Weight and length", for the preview's sample rows.
    var title: String {
        switch kind {
        case .activity(let activityKind):
            switch activityKind {
            case .feeding: return feedingType?.title ?? activityKind.title
            case .diaper: return diaperType.map(Self.diaperTitle) ?? activityKind.title
            case .medication: return medicationName.flatMap { $0.isEmpty ? nil : $0 } ?? activityKind.title
            default: return activityKind.title
            }
        case .growth: return String(localized: "Growth", comment: "Import: what every row of a file is")
        case .vaccine: return vaccineName.isEmpty ? String(localized: "Vaccine", comment: "Import: what every row of a file is") : vaccineName
        case .trackingPeriod: return trackingKind?.title ?? String(localized: "Marked time", comment: "Import: what every row of a file is")
        }
    }

    private static func diaperTitle(_ type: DiaperType) -> String {
        switch type {
        case .wet: return String(localized: "Wet diaper", comment: "Import preview: a sample row")
        case .dirty: return String(localized: "Dirty diaper", comment: "Import preview: a sample row")
        case .mixed: return String(localized: "Wet + dirty diaper", comment: "Import preview: a sample row")
        case .dry: return String(localized: "Dry diaper", comment: "Import preview: a sample row")
        }
    }

    /// "120 ml", "Left 10m · Right 5m", "1 h 20 min", in the units the app shows.
    func detail(unit: VolumeUnit, growthUnits: GrowthUnits, temperatureUnit: TemperatureUnit) -> String {
        var parts: [String] = []
        switch kind {
        case .activity(let activityKind):
            switch activityKind {
            case .feeding:
                if let leftMinutes, leftMinutes > 0 {
                    parts.append(String(localized: "Left \(leftMinutes)m", comment: "Import preview: minutes on the left breast"))
                }
                if let rightMinutes, rightMinutes > 0 {
                    parts.append(String(localized: "Right \(rightMinutes)m", comment: "Import preview: minutes on the right breast"))
                }
                if let foodDescription, !foodDescription.isEmpty { parts.append(foodDescription) }
                if let amountML { parts.append(unit.format(ml: amountML)) }
            case .diaper:
                if let poopColor { parts.append(poopColor.title) }
                if let poopConsistency { parts.append(poopConsistency.title) }
            case .sleep:
                if let end { parts.append(Format.duration(end.timeIntervalSince(start))) }
            case .medication:
                if let dosage, !dosage.isEmpty { parts.append(dosage) }
            case .pumping:
                let total = (pumpLeftML == nil && pumpRightML == nil) ? amountML : (pumpLeftML ?? 0) + (pumpRightML ?? 0)
                if let total, total > 0 {
                    let amount = unit.format(ml: total)
                    parts.append(String(localized: "Total \(amount)", comment: "Import preview: milk pumped from both sides, like 120 ml"))
                }
                if let durationMinutes, durationMinutes > 0 {
                    parts.append(String(localized: "\(durationMinutes) min", comment: "Import preview: how long a pumping session took"))
                }
            case .temperature:
                if let temperatureC { parts.append(temperatureUnit.format(celsius: temperatureC)) }
            case .bath:
                break
            }
        case .growth:
            if let weightKg { parts.append(growthUnits.formatWeight(kg: weightKg)) }
            if let lengthCm { parts.append(growthUnits.formatLength(cm: lengthCm)) }
        case .vaccine:
            parts.append(vaccineIsGiven
                ? String(localized: "Given", comment: "Import preview: a vaccine that was given")
                : String(localized: "Due", comment: "Import preview: a vaccine still to give"))
            if !doseLabel.isEmpty { parts.append(doseLabel) }
        case .trackingPeriod:
            if let end { parts.append(Format.duration(end.timeIntervalSince(start))) }
            if let trackingReason { parts.append(trackingReason.title) }
        }
        return parts.joined(separator: " · ")
    }
}

/// What reading a file would add, and what it would leave out.
struct ImportPlan: Sendable {
    var source: ImportSource
    var entries: [ImportEntry] = []
    /// Rows left out, by reason ("Tummy time (not something MyBaby logs)": 19).
    var skipped: [String: Int] = [:]
    /// Rows read, not counting headers and blank lines.
    var rowCount = 0
    /// How the dates were read, e.g. "Month/day/year, like 05/21/2020 8:05 PM".
    var dateDescription: String?
    /// Whether the dates could be read day first or month first, so the parent should check.
    var datesAreAmbiguous = false
    /// Things to know about this file, shown in the preview.
    var notes: [String] = []
    /// The babies named in the file, when it names more than one (Nara Baby).
    var babyNames: [String] = []
    /// The baby's details, when the file has them (Nara Baby's profile row).
    var babyBirthDate: Date?
    var babySex: BabySex?

    init(source: ImportSource) {
        self.source = source
    }

    mutating func skip(_ reason: String, count: Int = 1) {
        skipped[reason, default: 0] += count
    }

    mutating func add(_ entry: ImportEntry) {
        var entry = entry
        entry.id = entries.count
        entries.append(entry)
    }

    var skippedCount: Int { skipped.values.reduce(0, +) }

    /// The earliest and latest moment in the plan.
    var dateRange: ClosedRange<Date>? {
        guard let first = entries.min(by: { $0.start < $1.start })?.start else { return nil }
        let last = entries.map { $0.end ?? $0.start }.max() ?? first
        return first...max(first, last)
    }

    /// How many of each kind, in the order the preview lists them.
    var counts: [ImportCount] {
        var counts: [ImportCategory: Int] = [:]
        for entry in entries { counts[entry.category, default: 0] += 1 }
        return ImportCategory.allCases.compactMap { category in
            counts[category].map { ImportCount(category: category, count: $0) }
        }
    }

    /// The reasons rows were left out, the most common first.
    var skippedReasons: [ImportSkip] {
        skipped.map { ImportSkip(reason: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.reason < $1.reason : $0.count > $1.count }
    }

    /// Joins plans read from several files of one export (a ZIP, or MyBaby's set of CSVs).
    mutating func merge(_ other: ImportPlan) {
        for entry in other.entries { add(entry) }
        for (reason, count) in other.skipped { skip(reason, count: count) }
        rowCount += other.rowCount
        dateDescription = dateDescription ?? other.dateDescription
        datesAreAmbiguous = datesAreAmbiguous || other.datesAreAmbiguous
        for note in other.notes where !notes.contains(note) { notes.append(note) }
        for name in other.babyNames where !babyNames.contains(name) { babyNames.append(name) }
        babyBirthDate = babyBirthDate ?? other.babyBirthDate
        babySex = babySex ?? other.babySex
    }

    /// Only the rows for one of the babies the file names (nil keeps them all).
    func only(baby name: String?) -> ImportPlan {
        guard let name else { return self }
        var plan = self
        plan.entries = []
        for entry in entries where entry.sourceBaby == nil || entry.sourceBaby == name {
            plan.add(entry)
        }
        let others = entries.count - plan.entries.count
        if others > 0 { plan.skip(String(localized: "For another baby in the file", comment: "Import preview: why rows were left out"), count: others) }
        return plan
    }
}

/// How many entries of one kind a plan has.
struct ImportCount: Identifiable, Sendable {
    let category: ImportCategory
    let count: Int
    var id: ImportCategory { category }
}

/// Why some rows were left out, and how many.
struct ImportSkip: Identifiable, Sendable {
    let reason: String
    let count: Int
    var id: String { reason }
}

/// Choices that change how a file is read, from the first screen and the preview.
struct ImportOptions: Sendable {
    /// The time zone the file's times are read in. The phone's own zone unless the parent picks another.
    var timeZone: TimeZone = .current
    /// Day first or month first, for dates like 03/04/2026 that could be either.
    var dateOrder: DateOrder = .automatic
    /// The unit for amounts that don't say, in files that don't say either.
    var volumeUnit: VolumeUnit = .ml
}

/// Which comes first in a date like 03/04/2026.
enum DateOrder: String, CaseIterable, Identifiable, Sendable {
    case automatic, monthFirst, dayFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic", comment: "Import: how dates are read")
        case .monthFirst: return String(localized: "Month first (03/04 is March 4)", comment: "Import: how dates like 03/04 are read")
        case .dayFirst: return String(localized: "Day first (03/04 is 3 April)", comment: "Import: how dates like 03/04 are read")
        }
    }
}

/// A file's contents as rows of text, read on the iPhone.
struct ImportTable: Sendable {
    /// The file name, or its name inside the ZIP, for messages ("Couldn't read Sleep.csv").
    var name: String
    var header: [String]
    var rows: [[String]]

    /// The column whose header is one of `names`, ignoring case, spaces at either end and a BOM.
    func column(_ names: String...) -> Int? {
        column(in: names)
    }

    func column(in names: [String]) -> Int? {
        let wanted = names.map(ImportTable.key)
        return header.firstIndex { wanted.contains(ImportTable.key($0)) }
    }

    /// Whether every one of `names` is a column.
    func has(_ names: String...) -> Bool {
        names.allSatisfy { column($0) != nil }
    }

    static func key(_ header: String) -> String {
        header.replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// The trimmed text in `column` of `row`, or "" when the row is shorter or there's no such column.
    static func value(_ row: [String], _ column: Int?) -> String {
        guard let column, column >= 0, column < row.count else { return "" }
        return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Why a file couldn't be read at all. Each says what to do, calmly.
enum ImportError: LocalizedError {
    case unreadable(String)
    case empty
    case tooLarge
    case notRecognized(ImportSource)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return String(
                localized: "MyBaby couldn't read \(name). Check that it's a CSV, TXT or ZIP file exported from the other app.",
                comment: "Import error; a file name"
            )
        case .empty:
            return String(localized: "There's nothing to import in this file.", comment: "Import error")
        case .tooLarge:
            return String(localized: "This file is too large to import (over 50 MB). Try exporting a shorter time frame.", comment: "Import error")
        case .notRecognized(let source):
            let app = source.title
            return String(
                localized: "This doesn't look like a \(app) export. Choose Another app to match the columns yourself.",
                comment: "Import error; an app's name, like Huckleberry. “Another app” is a choice on the same screen"
            )
        case .cancelled:
            return String(localized: "The import was stopped.", comment: "Import error")
        }
    }
}
