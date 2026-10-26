import Foundation

/// One way of writing a date and time, tried against a column's values.
struct DatePattern: Identifiable, Hashable, Sendable {
    enum Order: Sendable {
        case yearFirst, monthFirst, dayFirst, words
    }

    /// A `DateFormatter` format, or `epoch` / `iso8601` for those.
    let format: String
    let order: Order
    var id: String { format }

    static let epoch = DatePattern(format: "epoch", order: .yearFirst)
    static let iso8601 = DatePattern(format: "iso8601", order: .yearFirst)

    var hasTime: Bool {
        self == .epoch || self == .iso8601 || format.contains("H") || format.contains("h")
    }

    /// "Month/day/year, with the time", for the mapping screen's picker.
    var title: String {
        if self == .epoch { return String(localized: "Seconds since 1970 (a timestamp)", comment: "Import: how a file writes its dates") }
        if self == .iso8601 { return String(localized: "ISO 8601, with its time zone", comment: "Import: how a file writes its dates") }
        let order: String
        switch self.order {
        case .yearFirst: order = String(localized: "Year-month-day", comment: "Import: how a file writes its dates")
        case .monthFirst: order = String(localized: "Month/day/year", comment: "Import: how a file writes its dates")
        case .dayFirst: order = String(localized: "Day/month/year", comment: "Import: how a file writes its dates")
        case .words: order = String(localized: "Month in words", comment: "Import: how a file writes its dates")
        }
        // Not localized: the pattern itself, as the file writes it ("M/d/yyyy h:mm a").
        let pattern = format.replacingOccurrences(of: "'", with: "")
        if !hasTime {
            return String(localized: "\(order), no time (\(pattern))", comment: "Import: the date order, like Month/day/year, then a date pattern")
        } else if format.contains("a") {
            return String(localized: "\(order), 12-hour time (\(pattern))", comment: "Import: the date order, like Month/day/year, then a date pattern")
        } else {
            return String(localized: "\(order), 24-hour time (\(pattern))", comment: "Import: the date order, like Month/day/year, then a date pattern")
        }
    }
}

/// The dates in a column, and how they're written.
struct DateGuess: Sendable {
    let pattern: DatePattern
    /// Day first and month first both read every value (no day after the 12th), so the parent should check.
    let isAmbiguous: Bool
    /// How many of the samples it read.
    let readCount: Int
    let sampleCount: Int
    /// A value from the file, to show how it's read.
    let example: String?
}

/// Reading dates from other apps' files, in the time zone the parent picks.
///
/// Files rarely say how their dates are written, so `guess` tries every common pattern on the column's
/// values and keeps the one that reads the most. When day first and month first both fit (no day past
/// the 12th), the parent's choice, or the iPhone's region, decides, and the preview asks to check.
enum ImportDates {
    /// Dates outside these years are a misread (a two-digit year read as year 20), not a baby's log.
    static let plausibleYears = 1990...2100

    /// Not localized: `DateFormatter` patterns, read with the POSIX locale.
    static let patterns: [DatePattern] = {
        let yearFirst = [
            "yyyy-MM-dd h:mm:ss a", "yyyy-MM-dd h:mm a", "yyyy/MM/dd h:mm:ss a", "yyyy/MM/dd h:mm a",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd, HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm:ss", "yyyy.MM.dd HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd",
        ].map { DatePattern(format: $0, order: .yearFirst) }
        let monthFirst = [
            "M/d/yyyy h:mm:ss a", "M/d/yyyy h:mm a", "M/d/yyyy, h:mm:ss a", "M/d/yyyy, h:mm a",
            "M/d/yyyy HH:mm:ss", "M/d/yyyy HH:mm", "M/d/yyyy, HH:mm",
            "M/d/yy h:mm:ss a", "M/d/yy h:mm a", "M/d/yy, h:mm a", "M/d/yy HH:mm", "M/d/yy, HH:mm",
            "M-d-yyyy h:mm a", "M-d-yyyy HH:mm",
            "M/d/yyyy", "M/d/yy", "M-d-yyyy",
        ].map { DatePattern(format: $0, order: .monthFirst) }
        let dayFirst = [
            "d/M/yyyy h:mm:ss a", "d/M/yyyy h:mm a", "d/M/yy h:mm a",
            "d/M/yyyy HH:mm:ss", "d/M/yyyy HH:mm", "d/M/yyyy, HH:mm", "d/M/yy HH:mm", "d/M/yy, HH:mm",
            "d.M.yyyy HH:mm:ss", "d.M.yyyy HH:mm", "d.M.yyyy, HH:mm", "d.M.yy HH:mm",
            "d-M-yyyy HH:mm:ss", "d-M-yyyy HH:mm",
            "d/M/yyyy", "d/M/yy", "d.M.yyyy", "d-M-yyyy",
        ].map { DatePattern(format: $0, order: .dayFirst) }
        let words = [
            "MMM d, yyyy h:mm a", "MMM d, yyyy 'at' h:mm a", "MMM d, yyyy HH:mm", "MMMM d, yyyy h:mm a",
            "d MMM yyyy HH:mm", "d MMM yyyy h:mm a", "d MMMM yyyy HH:mm", "EEE, MMM d, yyyy h:mm a",
            "MMM d, yyyy", "MMMM d, yyyy", "d MMM yyyy", "d MMMM yyyy",
        ].map { DatePattern(format: $0, order: .words) }
        return [.iso8601] + yearFirst + monthFirst + dayFirst + words + [.epoch]
    }()

    /// The pattern that reads the most of `samples`. `preferred` formats win ties (a source's known
    /// format), then `order` (or, when automatic, the iPhone's region) settles day first or month first.
    static func guess(
        _ samples: [String],
        preferred: [String] = [],
        order: DateOrder = .automatic,
        timeZone: TimeZone = .current
    ) -> DateGuess? {
        let values = samples.map(normalized).filter { !$0.isEmpty }
        let sample = Array(values.prefix(150))
        guard !sample.isEmpty else { return nil }
        var scored: [(pattern: DatePattern, count: Int)] = []
        for pattern in patterns {
            let reader = DateReader(pattern: pattern, timeZone: timeZone)
            let count = sample.reduce(0) { $0 + (reader.date($1) == nil ? 0 : 1) }
            if count > 0 { scored.append((pattern, count)) }
        }
        guard let best = scored.map({ $0.count }).max() else { return nil }
        let top = scored.filter { $0.count == best }.map { $0.pattern }
        let hasMonthFirst = top.contains { $0.order == .monthFirst }
        let hasDayFirst = top.contains { $0.order == .dayFirst }
        let ambiguous = hasMonthFirst && hasDayFirst
        let wantsDayFirst: Bool
        switch order {
        case .dayFirst: wantsDayFirst = true
        case .monthFirst: wantsDayFirst = false
        case .automatic: wantsDayFirst = regionPutsDayFirst
        }
        let chosen = top.first { preferred.contains($0.format) && (!ambiguous || ($0.order == .dayFirst) == wantsDayFirst) }
            ?? top.first { !ambiguous || ($0.order == .dayFirst) == wantsDayFirst }
            ?? top[0]
        return DateGuess(pattern: chosen, isAmbiguous: ambiguous, readCount: best, sampleCount: sample.count, example: sample.first)
    }

    /// Whether this iPhone's region writes the day before the month (3/4 is 3 April).
    static var regionPutsDayFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: .current) ?? "M/d"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }

    /// Spaces collapsed, "a.m." and "pm" written as "AM" and "PM", so one pattern fits them all.
    static func normalized(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        while value.contains("  ") { value = value.replacingOccurrences(of: "  ", with: " ") }
        for (written, standard) in [("a.m.", "AM"), ("p.m.", "PM"), ("am", "AM"), ("pm", "PM")] {
            if value.lowercased().hasSuffix(written) {
                value = String(value.dropLast(written.count)).trimmingCharacters(in: .whitespaces)
                value += " " + standard
                break
            }
        }
        return value
    }

    /// "Month/day/year: “05/21/2020 8:05 PM” is May 21, 2020 at 8:05 PM", to confirm in the preview.
    static func describe(_ guess: DateGuess, timeZone: TimeZone) -> String {
        let reader = DateReader(pattern: guess.pattern, timeZone: timeZone)
        guard let example = guess.example, let date = reader.date(example) else {
            if guess.pattern == .epoch { return String(localized: "Dates are timestamps.", comment: "Import preview") }
            switch guess.pattern.order {
            case .yearFirst: return String(localized: "Dates are year first.", comment: "Import preview")
            case .monthFirst: return String(localized: "Dates are month first.", comment: "Import preview")
            case .dayFirst: return String(localized: "Dates are day first.", comment: "Import preview")
            case .words: return String(localized: "Dates have the month in words.", comment: "Import preview")
            }
        }
        var style = Date.FormatStyle(date: .abbreviated, time: guess.pattern.hasTime ? .shortened : .omitted)
        style.timeZone = timeZone
        let read = date.formatted(style)
        if guess.pattern == .epoch {
            return String(localized: "Dates are timestamps: “\(example)” is \(read).", comment: "Import preview; a date as the file writes it, then how MyBaby reads it")
        }
        switch guess.pattern.order {
        case .yearFirst:
            return String(localized: "Dates are year first: “\(example)” is \(read).", comment: "Import preview; a date as the file writes it, then how MyBaby reads it")
        case .monthFirst:
            return String(localized: "Dates are month first: “\(example)” is \(read).", comment: "Import preview; a date as the file writes it, then how MyBaby reads it")
        case .dayFirst:
            return String(localized: "Dates are day first: “\(example)” is \(read).", comment: "Import preview; a date as the file writes it, then how MyBaby reads it")
        case .words:
            return String(localized: "Dates have the month in words: “\(example)” is \(read).", comment: "Import preview; a date as the file writes it, then how MyBaby reads it")
        }
    }
}

/// Reads one pattern's dates in a time zone. Values without a time are read as noon, so a time zone
/// change can't move them to another day.
///
/// 12-hour patterns are listed before 24-hour ones and patterns with a time before those without, so
/// when two would read a column equally well, the one that keeps the most of each value wins.
struct DateReader {
    let pattern: DatePattern
    let timeZone: TimeZone
    private let formatter: DateFormatter?
    private let isoFormatters: [ISO8601DateFormatter]
    private let calendar: Calendar

    init(pattern: DatePattern, timeZone: TimeZone) {
        self.pattern = pattern
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        if pattern == .iso8601 {
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoFormatters = [plain, fractional]
            formatter = nil
        } else if pattern == .epoch {
            isoFormatters = []
            formatter = nil
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.isLenient = false
            formatter.dateFormat = pattern.format
            self.formatter = formatter
            isoFormatters = []
        }
    }

    /// The moment `text` names, or `nil` when it isn't written this way.
    func date(_ text: String) -> Date? {
        let value = ImportDates.normalized(text)
        guard !value.isEmpty else { return nil }
        let read: Date?
        if pattern == .epoch {
            read = Self.epochDate(value)
        } else if pattern == .iso8601 {
            read = isoFormatters.lazy.compactMap { $0.date(from: value) }.first
        } else if let formatter, let parsed = formatter.date(from: value) {
            read = pattern.hasTime ? parsed : parsed.addingTimeInterval(12 * 3600)
        } else {
            read = nil
        }
        guard let date = read else { return nil }
        return ImportDates.plausibleYears.contains(calendar.component(.year, from: date)) ? date : nil
    }

    /// Seconds (10 digits) or milliseconds (13 digits) since 1970.
    static func epochDate(_ text: String) -> Date? {
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Double(text) else { return nil }
        switch text.count {
        case 9...10: return Date(timeIntervalSince1970: number)
        case 12...13: return Date(timeIntervalSince1970: number / 1000)
        default: return nil
        }
    }
}
