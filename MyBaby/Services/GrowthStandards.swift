import Foundation

/// The baby's sex, only used to pick the WHO growth chart (girls and boys grow differently).
enum BabySex: String, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return String(localized: "Girl", comment: "The baby's sex, for the growth charts")
        case .male: return String(localized: "Boy", comment: "The baby's sex, for the growth charts")
        }
    }

    /// The key in `who-growth.json`.
    fileprivate var tableKey: String {
        switch self {
        case .female: return "girls"
        case .male: return "boys"
        }
    }
}

/// What a WHO chart measures against age.
enum GrowthMeasure {
    case weight, length, headCircumference

    fileprivate var tableKey: String {
        switch self {
        case .weight: return "weightForAge"
        case .length: return "lengthForAge"
        case .headCircumference: return "headCircumferenceForAge"
        }
    }
}

/// The WHO's Box-Cox parameters for one age: L (skew), M (median) and S (spread).
/// Weight in kilograms, length and head circumference in centimeters.
struct LMS {
    let l: Double
    let m: Double
    let s: Double

    /// How many standard deviations `value` is from the median. With L near zero the Box-Cox
    /// formula divides by zero, so it falls back to the log form it tends to.
    func zScore(for value: Double) -> Double {
        guard value > 0, m > 0, s > 0 else { return .nan }
        if abs(l) < 1e-7 { return log(value / m) / s }
        return (pow(value / m, l) - 1) / (l * s)
    }

    /// The measurement at `z` standard deviations, for drawing a percentile curve.
    func value(atZ z: Double) -> Double {
        if abs(l) < 1e-7 { return m * exp(s * z) }
        return m * pow(max(1 + l * s * z, 1e-9), 1 / l)
    }
}

/// Where a measurement falls among babies of the same age and sex.
struct GrowthPercentile {
    let z: Double

    /// 0–100, from the normal distribution: Φ(z) = ½·erfc(−z/√2).
    var percentile: Double { 50 * erfc(-z / 2.0.squareRoot()) }

    /// "48th", or "<1st" / ">99th" at the extremes, where a whole number would be misleading.
    var shortText: String {
        let p = percentile
        if p < 1 {
            let first = Self.ordinal(1)
            return String(localized: "<\(first)", comment: "Below the 1st percentile, in a chart label; the ordinal, like 1st")
        }
        if p > 99 {
            let last = Self.ordinal(99)
            return String(localized: ">\(last)", comment: "Above the 99th percentile, in a chart label; the ordinal, like 99th")
        }
        return Self.ordinal(min(max(Int(p.rounded()), 1), 99))
    }

    /// "48th percentile".
    var text: String {
        let rank = shortText
        return String(localized: "\(rank) percentile", comment: "Growth percentile; an ordinal like 48th, <1st or >99th")
    }

    /// What VoiceOver reads, so "<" isn't read out as a symbol.
    var spokenText: String {
        let p = percentile
        if p < 1 { return String(localized: "below the 1st percentile", comment: "VoiceOver, for a growth measurement") }
        if p > 99 { return String(localized: "above the 99th percentile", comment: "VoiceOver, for a growth measurement") }
        return text
    }

    /// "1st", "2nd", "3rd", "11th", "22nd"… in the iPhone's language ("1er", "2e" in French).
    static func ordinal(_ number: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

/// One faint reference line on a growth chart, e.g. the 50th percentile, in kg or cm.
struct GrowthCurve: Identifiable {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let percentile: Int
    let points: [Point]
    var id: Int { percentile }

    var label: String { GrowthPercentile.ordinal(percentile) }
}

/// The WHO Child Growth Standards (weight-for-age, length/height-for-age and head
/// circumference-for-age, girls and boys), read once from the bundled `who-growth.json`.
///
/// The file holds the WHO's own daily LMS values, from birth to 1856 days (about 5 years), copied
/// from the WHO's expanded tables (see README.md for the source and download date). From day 731
/// the length table is standing height, as in the WHO standard.
///
/// Head circumference-for-age comes from the WHO's `hcfa-boys-zscore-expanded-tables.xlsx` and
/// `hcfa-girls-zscore-expanded-tables.xlsx` (WHO Child Growth Standards, 2007,
/// https://www.who.int/tools/child-growth-standards/standards/head-circumference-for-age),
/// downloaded on 2026-10-25 and checked against the CDC's copies of the WHO monthly tables
/// (https://www.cdc.gov/growthcharts/who-data-files.htm). Its L is 1 throughout, so the
/// percentiles there are a plain normal distribution around the median.
final class GrowthStandards {
    /// `nil` only if the JSON is missing from the app bundle.
    static let who: GrowthStandards? = {
        guard let url = Bundle.main.url(forResource: "who-growth", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return GrowthStandards(data: data)
    }()

    /// The percentiles drawn behind the baby's measurements.
    static let chartPercentiles = [3, 15, 50, 85, 97]

    private struct Table: Decodable {
        let l: [Double]
        let m: [Double]
        let s: [Double]

        enum CodingKeys: String, CodingKey {
            case l = "L", m = "M", s = "S"
        }
    }

    private struct File: Decodable {
        let weightForAge: [String: Table]
        let lengthForAge: [String: Table]
        /// Optional, so a file without it still gives weight and length.
        let headCircumferenceForAge: [String: Table]?
    }

    /// Keyed by "weightForAge.girls" and so on.
    private let tables: [String: Table]

    init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        var tables: [String: Table] = [:]
        for (key, table) in file.weightForAge { tables["weightForAge.\(key)"] = table }
        for (key, table) in file.lengthForAge { tables["lengthForAge.\(key)"] = table }
        for (key, table) in file.headCircumferenceForAge ?? [:] { tables["headCircumferenceForAge.\(key)"] = table }
        self.tables = tables
    }

    private func table(_ measure: GrowthMeasure, _ sex: BabySex) -> Table? {
        tables["\(measure.tableKey).\(sex.tableKey)"]
    }

    /// The parameters for an age in completed days, or `nil` outside birth to about 5 years.
    func lms(_ measure: GrowthMeasure, sex: BabySex, ageDays: Int) -> LMS? {
        guard let table = table(measure, sex), ageDays >= 0,
              ageDays < table.m.count, ageDays < table.s.count,
              table.l.count == 1 || ageDays < table.l.count
        else { return nil }
        // An L that's the same every day (length and head circumference) is stored once.
        let l = table.l.count == 1 ? table.l[0] : table.l[ageDays]
        return LMS(l: l, m: table.m[ageDays], s: table.s[ageDays])
    }

    /// Where `value` (kg or cm) falls for a baby `ageDays` old.
    ///
    /// The WHO adjusts weight z-scores beyond ±3 for its own reports; that only changes values far
    /// past the 1st and 99th percentiles, which are shown as "<1st" and ">99th" anyway.
    func percentile(_ measure: GrowthMeasure, sex: BabySex, ageDays: Int, value: Double) -> GrowthPercentile? {
        guard let params = self.lms(measure, sex: sex, ageDays: ageDays) else { return nil }
        let z = params.zScore(for: value)
        return z.isFinite ? GrowthPercentile(z: z) : nil
    }

    /// The reference curves between two dates (clamped to the ages the tables cover), sampled
    /// often enough to look smooth.
    func curves(
        _ measure: GrowthMeasure,
        sex: BabySex,
        birthDate: Date,
        from start: Date,
        to end: Date,
        percentiles: [Int] = GrowthStandards.chartPercentiles,
        calendar: Calendar = .current
    ) -> [GrowthCurve] {
        guard let first = Self.ageDays(birthDate: birthDate, at: max(start, birthDate), calendar: calendar),
              let last = Self.ageDays(birthDate: birthDate, at: end, calendar: calendar),
              let count = table(measure, sex)?.m.count
        else { return [] }
        let lastDay = min(last, count - 1)
        guard lastDay > first else { return [] }

        let step = max(1, (lastDay - first) / 60)
        var days = Array(stride(from: first, to: lastDay, by: step))
        days.append(lastDay)
        let birthDay = calendar.startOfDay(for: birthDate)

        return percentiles.map { percentile -> GrowthCurve in
            let z = Self.zScore(forPercentile: percentile)
            let points = days.compactMap { day -> GrowthCurve.Point? in
                guard let params = self.lms(measure, sex: sex, ageDays: day),
                      let date = calendar.date(byAdding: .day, value: day, to: birthDay)
                else { return nil }
                return GrowthCurve.Point(date: date, value: params.value(atZ: z))
            }
            return GrowthCurve(percentile: percentile, points: points)
        }
    }

    /// Under 37 weeks counts as born early; a full-term pregnancy is 40 weeks (280 days).
    static let pretermBeforeDays = 37 * 7
    static let fullTermDays = 40 * 7
    /// Corrected age is used until the second birthday, counted from the real birthday.
    static let correctedAgeUntilDays = 730

    static func dueDate(birthDate: Date, gestationDays: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: fullTermDays - gestationDays, to: calendar.startOfDay(for: birthDate))
    }

    /// The birthday, or the due date while corrected age applies (see `Baby.growthAgeStart`).
    static func ageStart(birthDate: Date?, dueDate: Date?, on date: Date) -> Date? {
        guard let birthDate else { return nil }
        guard let dueDate, let realAge = ageDays(birthDate: birthDate, at: date),
              realAge < correctedAgeUntilDays
        else { return birthDate }
        return dueDate
    }

    /// Age in completed days, as the WHO tables count it. `nil` before birth.
    static func ageDays(birthDate: Date, at date: Date, calendar: Calendar = .current) -> Int? {
        guard let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: birthDate), to: calendar.startOfDay(for: date)
        ).day, days >= 0 else { return nil }
        return days
    }

    /// The z-score of a percentile (the inverse of the normal distribution), for the chart lines.
    static func zScore(forPercentile percentile: Int) -> Double {
        switch percentile {
        case 3: return -1.880793608151251
        case 15: return -1.036433389493789
        case 50: return 0
        case 85: return 1.036433389493789
        case 97: return 1.880793608151251
        default: return inverseNormal(Double(percentile) / 100)
        }
    }

    /// Φ⁻¹(p) by bisection on `erfc`; only used for percentiles other than the chart's own.
    private static func inverseNormal(_ p: Double) -> Double {
        var low = -8.0
        var high = 8.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if 0.5 * erfc(-mid / 2.0.squareRoot()) < p { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}

extension Baby {
    /// Where a measurement taken on `date` falls on the WHO chart, or `nil` without a sex and
    /// birthday, or outside birth to 5 years.
    func growthPercentile(_ measure: GrowthMeasure, value: Double, on date: Date) -> GrowthPercentile? {
        guard let sex, let start = growthAgeStart(on: date), let standards = GrowthStandards.who,
              let days = GrowthStandards.ageDays(birthDate: start, at: date)
        else { return nil }
        return standards.percentile(measure, sex: sex, ageDays: days, value: value)
    }

    /// Days of pregnancy at birth (34 weeks + 2 days is 240), or `nil` when not entered.
    var gestationDays: Int? {
        gestationWeeksNumber.map { $0.intValue * 7 + (gestationDaysNumber?.intValue ?? 0) }
    }

    /// Born before 37 weeks.
    var isPreterm: Bool {
        guard let gestationDays else { return false }
        return gestationDays < GrowthStandards.pretermBeforeDays
    }

    /// The day the baby was due: the birthday plus the weeks they came early. Only for a baby born
    /// before 37 weeks.
    var dueDate: Date? {
        guard isPreterm, let birthDate, let gestationDays else { return nil }
        return GrowthStandards.dueDate(birthDate: birthDate, gestationDays: gestationDays)
    }

    /// Where age is counted from on the growth charts for a measurement on `date`: the due date for a
    /// baby born before 37 weeks until their second birthday (corrected age, as pediatricians use),
    /// otherwise the birthday.
    func growthAgeStart(on date: Date) -> Date? {
        GrowthStandards.ageStart(birthDate: birthDate, dueDate: dueDate, on: date)
    }

    /// "October 20, 2026 at 3:42 AM", or just the day when no time of birth was entered. For the
    /// record only: ages are always counted in whole days.
    func birthText(dateStyle: Date.FormatStyle.DateStyle = .long) -> String? {
        guard let birthDate else { return nil }
        return birthDate.formatted(date: dateStyle, time: hasBirthTime ? .shortened : .omitted)
    }

    /// "Born at 34 weeks + 2 days", for footers.
    var gestationText: String? {
        guard let weeks = gestationWeeksNumber?.intValue else { return nil }
        let days = gestationDaysNumber?.intValue ?? 0
        if days == 0 {
            return String(localized: "\(weeks) weeks", comment: "Weeks of pregnancy at birth")
        }
        return days == 1
            ? String(localized: "\(weeks) weeks + 1 day", comment: "Weeks of pregnancy at birth, plus one day")
            : String(localized: "\(weeks) weeks + \(days) days", comment: "Weeks of pregnancy at birth, plus days")
    }

    /// Whether percentiles can be shown: the WHO charts depend on both sex and age.
    var canShowGrowthPercentiles: Bool {
        sex != nil && birthDate != nil && GrowthStandards.who != nil
    }
}
