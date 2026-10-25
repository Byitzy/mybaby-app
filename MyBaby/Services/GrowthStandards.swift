import Foundation

/// The baby's sex, only used to pick the WHO growth chart (girls and boys grow differently).
enum BabySex: String, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "Girl"
        case .male: return "Boy"
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
    case weight, length

    fileprivate var tableKey: String {
        switch self {
        case .weight: return "weightForAge"
        case .length: return "lengthForAge"
        }
    }
}

/// The WHO's Box-Cox parameters for one age: L (skew), M (median) and S (spread).
/// Weight in kilograms, length in centimeters.
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
        if p < 1 { return "<1st" }
        if p > 99 { return ">99th" }
        return Self.ordinal(min(max(Int(p.rounded()), 1), 99))
    }

    /// "48th percentile".
    var text: String { "\(shortText) percentile" }

    /// What VoiceOver reads, so "<" isn't read out as a symbol.
    var spokenText: String {
        let p = percentile
        if p < 1 { return "below the 1st percentile" }
        if p > 99 { return "above the 99th percentile" }
        return text
    }

    /// "1st", "2nd", "3rd", "11th", "22nd"…
    static func ordinal(_ number: Int) -> String {
        let lastTwo = number % 100
        let suffix: String
        if (11...13).contains(lastTwo) {
            suffix = "th"
        } else {
            switch number % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }
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

/// The WHO Child Growth Standards (weight-for-age and length/height-for-age, girls and boys),
/// read once from the bundled `who-growth.json`.
///
/// The file holds the WHO's own daily LMS values, from birth to 1856 days (about 5 years), copied
/// from the WHO's expanded tables (see README.md for the source and download date). From day 731
/// the length table is standing height, as in the WHO standard.
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
    }

    /// Keyed by "weightForAge.girls" and so on.
    private let tables: [String: Table]

    init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        var tables: [String: Table] = [:]
        for (key, table) in file.weightForAge { tables["weightForAge.\(key)"] = table }
        for (key, table) in file.lengthForAge { tables["lengthForAge.\(key)"] = table }
        self.tables = tables
    }

    private func table(_ measure: GrowthMeasure, _ sex: BabySex) -> Table? {
        tables["\(measure.tableKey).\(sex.tableKey)"]
    }

    /// The parameters for an age in completed days, or `nil` outside birth to about 5 years.
    func lms(_ measure: GrowthMeasure, sex: BabySex, ageDays: Int) -> LMS? {
        guard let table = table(measure, sex), ageDays >= 0,
              ageDays < table.m.count, ageDays < table.l.count, ageDays < table.s.count
        else { return nil }
        return LMS(l: table.l[ageDays], m: table.m[ageDays], s: table.s[ageDays])
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
        guard let sex, let birthDate, let standards = GrowthStandards.who,
              let days = GrowthStandards.ageDays(birthDate: birthDate, at: date)
        else { return nil }
        return standards.percentile(measure, sex: sex, ageDays: days, value: value)
    }

    /// Whether percentiles can be shown: the WHO charts depend on both sex and age.
    var canShowGrowthPercentiles: Bool {
        sex != nil && birthDate != nil && GrowthStandards.who != nil
    }
}
