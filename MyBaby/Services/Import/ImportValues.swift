import Foundation

/// Reading the values other apps write, "120ml", "4 oz", "9 lb 4 oz", "2.67ft.in", "00:14R", "1h 20m",
/// "38.2 °C", into MyBaby's units: milliliters, kilograms, centimeters, degrees Celsius and minutes.
///
/// Every function returns `nil` rather than guess when the text doesn't say clearly, so the row can be
/// skipped and counted instead of saved wrong. Pure functions, with no Core Data.
///
/// Not localized: the words matched here ("oz", "wet", "mustard"…) are the ones other apps write, in English.
enum ImportValues {
    // MARK: Numbers

    /// The numbers in `text`, each with the words that follow it: "9 lb 4 oz" is (9, "lb"), (4, "oz").
    /// A comma followed by one or two digits is a decimal comma ("1,5"); with three it groups thousands.
    static func numbersWithUnits(_ text: String) -> [(value: Double, unit: String)] {
        var results: [(value: Double, unit: String)] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let startsNumber = character.isASCIIDigit
                || ((character == "." || character == "-") && index + 1 < characters.count && characters[index + 1].isASCIIDigit
                    && (character == "." || index == 0 || !characters[index - 1].isLetter))
            guard startsNumber else {
                index += 1
                continue
            }
            var number = ""
            if character == "-" {
                number.append("-")
                index += 1
            }
            var sawDecimal = false
            while index < characters.count {
                let c = characters[index]
                if c.isASCIIDigit {
                    number.append(c)
                    index += 1
                } else if (c == "." || c == ","), !sawDecimal, index + 1 < characters.count, characters[index + 1].isASCIIDigit {
                    var digitsAfter = 0
                    var look = index + 1
                    while look < characters.count, characters[look].isASCIIDigit {
                        digitsAfter += 1
                        look += 1
                    }
                    if c == "," && digitsAfter == 3 {
                        // A thousands separator: keep reading the digits.
                        index += 1
                        continue
                    }
                    number.append(".")
                    sawDecimal = true
                    index += 1
                } else {
                    break
                }
            }
            // The unit: everything up to the next number, without spaces and brackets around it.
            var unit = ""
            while index < characters.count, !characters[index].isASCIIDigit {
                if characters[index] == "-" || characters[index] == ".",
                   index + 1 < characters.count, characters[index + 1].isASCIIDigit,
                   unit.trimmingCharacters(in: .whitespaces).isEmpty || characters[index] == "-" {
                    break
                }
                unit.append(characters[index])
                index += 1
            }
            let cleaned = unit.trimmingCharacters(in: CharacterSet(charactersIn: " \t()[],;:/").union(.whitespaces)).lowercased()
            if let value = Double(number) {
                results.append((value: value, unit: cleaned))
            }
        }
        return results
    }

    /// The first number in `text`, whatever follows it.
    static func number(_ text: String) -> Double? {
        numbersWithUnits(text).first?.value
    }

    // MARK: Volume

    /// "120ml", "4 oz", "4 fl oz", "120 cc" in milliliters. A number on its own is read in `defaultUnit`,
    /// or not at all without one.
    static func milliliters(_ text: String, defaultUnit: VolumeUnit? = nil) -> Double? {
        guard let first = numbersWithUnits(text).first, first.value >= 0 else { return nil }
        let unit = first.unit
        if unit.isEmpty {
            guard let defaultUnit else { return nil }
            return defaultUnit.toML(first.value)
        }
        if let volume = volumeUnit(unit) {
            return volume.toML(first.value)
        }
        if unit == "l" || unit == "liter" || unit == "litre" || unit == "liters" || unit == "litres" {
            return first.value * 1000
        }
        return nil
    }

    /// "ml" or "oz" in their usual spellings.
    static func volumeUnit(_ text: String) -> VolumeUnit? {
        let unit = text.lowercased().trimmingCharacters(in: .whitespaces)
        if ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres", "cc"].contains(unit) { return .ml }
        if ["oz", "ozs", "fl oz", "fl. oz", "fl.oz", "floz", "ounce", "ounces", "fl ounce"].contains(unit) { return .oz }
        return nil
    }

    // MARK: Weight and length

    /// A weight in kilograms: "4.2kg", "4200 g", "9 lb 4 oz", "9.25 lb", "148 oz". Huckleberry writes
    /// pounds as "13.03lbs.oz", but the number is decimal pounds (13.03 lb), not 13 lb 3 oz: its checkups
    /// only line up as a growth curve read that way (see `HuckleberryImporter`). A number alone is read
    /// in `defaultUnit` ("kg" or "lb").
    static func kilograms(_ text: String, defaultUnit: String? = nil) -> Double? {
        let parts = numbersWithUnits(text)
        guard let first = parts.first, first.value > 0 else { return nil }
        let unit = first.unit.isEmpty ? (defaultUnit ?? "") : first.unit
        if unit.hasPrefix("lb") || unit.hasPrefix("pound") {
            // "9 lb 4 oz"
            if parts.count > 1, parts[1].unit.hasPrefix("oz") || parts[1].unit.hasPrefix("ounce") {
                return GrowthUnits.kg(pounds: first.value, ounces: parts[1].value)
            }
            return first.value * GrowthUnits.kgPerPound
        }
        if unit == "kg" || unit.hasPrefix("kilo") { return first.value }
        if unit == "g" || unit.hasPrefix("gram") { return first.value / 1000 }
        if unit == "oz" || unit.hasPrefix("ounce") { return first.value / 16 * GrowthUnits.kgPerPound }
        return nil
    }

    /// A length in centimeters: "52 cm", "520 mm", "20.5 in", "20.5\"", and Huckleberry's "1.92ft.in",
    /// which is decimal feet like its weights. A number alone is read in `defaultUnit` ("cm" or "in").
    static func centimeters(_ text: String, defaultUnit: String? = nil) -> Double? {
        let parts = numbersWithUnits(text)
        guard let first = parts.first, first.value > 0 else { return nil }
        let unit = first.unit.isEmpty ? (defaultUnit ?? "") : first.unit
        if unit.hasPrefix("ft") || unit.hasPrefix("feet") || unit.hasPrefix("foot") || unit == "'" {
            // "1 ft 8 in"
            if parts.count > 1, parts[1].unit.hasPrefix("in") || parts[1].unit == "\"" {
                return (first.value * 12 + parts[1].value) * GrowthUnits.cmPerInch
            }
            return first.value * 12 * GrowthUnits.cmPerInch
        }
        if unit == "cm" || unit.hasPrefix("centi") { return first.value }
        if unit == "mm" { return first.value / 10 }
        if unit == "m" { return first.value * 100 }
        if unit.hasPrefix("in") || unit == "\"" { return first.value * GrowthUnits.cmPerInch }
        return nil
    }

    // MARK: Temperature

    /// A temperature in °C: "38.2 °C", "100.4F", or a number alone, read as °C between 30 and 45 and as
    /// °F between 86 and 113 (no baby's temperature is in both ranges).
    static func celsius(_ text: String, defaultUnit: TemperatureUnit? = nil) -> Double? {
        guard let first = numbersWithUnits(text).first else { return nil }
        let unit = first.unit.replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "º", with: "")
            .trimmingCharacters(in: .whitespaces)
        let value: Double
        if unit.hasPrefix("f") {
            value = TemperatureUnit.fahrenheit.toCelsius(first.value)
        } else if unit.hasPrefix("c") {
            value = first.value
        } else if let defaultUnit, unit.isEmpty {
            value = defaultUnit.toCelsius(first.value)
        } else if (30...45).contains(first.value) {
            value = first.value
        } else if (86...113).contains(first.value) {
            value = TemperatureUnit.fahrenheit.toCelsius(first.value)
        } else {
            return nil
        }
        // Outside these, it's a typo or not a body temperature.
        return (30...45).contains(value) ? value : nil
    }

    // MARK: Durations

    /// How long, in minutes: "1:20" and "01:20:30" are hours and minutes (and seconds), "1h 20m",
    /// "20 min", "90 s" and "1.5 hours" say their unit, and a number alone is in `defaultUnit` minutes,
    /// seconds or hours.
    static func minutes(_ text: String, defaultUnit: DurationUnit = .minutes) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let clock = clockMinutes(trimmed) { return clock }
        var total = 0.0
        var found = false
        for part in numbersWithUnits(trimmed) {
            let unit = part.unit
            if unit.isEmpty {
                total += part.value * defaultUnit.minutes
            } else if unit.hasPrefix("h") {
                total += part.value * 60
            } else if unit.hasPrefix("s") {
                total += part.value / 60
            } else if unit.hasPrefix("m") {
                total += part.value
            } else {
                continue
            }
            found = true
        }
        return found && total >= 0 ? total : nil
    }

    /// "1:20" or "01:20:30" (hours, minutes and maybe seconds), optionally followed by a side letter
    /// as Huckleberry writes it ("00:14R"), in minutes.
    static func clockMinutes(_ text: String) -> Double? {
        var body = text.trimmingCharacters(in: .whitespaces)
        if let last = body.last, last.isLetter { body.removeLast() }
        let pieces = body.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2 || pieces.count == 3,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        let numbers = pieces.compactMap { Double($0) }
        guard numbers.count == pieces.count else { return nil }
        let seconds = numbers.count == 3 ? numbers[2] : 0
        return numbers[0] * 60 + numbers[1] + seconds / 60
    }

    /// A side written next to a time, "00:14R" or "00:10 L", as Huckleberry does for breastfeeds.
    static func sideTime(_ text: String) -> (side: ImportedSide, minutes: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last?.uppercased(), let side = ImportedSide(letter: last),
              let minutes = clockMinutes(trimmed)
        else { return nil }
        return (side, minutes)
    }

    /// Whole minutes for a breastfeeding side: at least 1 for a side that was used, as the timer saves it.
    static func wholeMinutes(_ minutes: Double) -> Int {
        minutes <= 0 ? 0 : max(1, Int(minutes.rounded()))
    }

    // MARK: Words

    /// A diaper from the words other apps use: "pee", "wet", "poo", "poop", "dirty", "both", "mixed",
    /// "pee and poo", "dry", "clean".
    static func diaperType(_ text: String) -> DiaperType? {
        let words = text.lowercased()
        let wet = ["pee", "wet", "urine"].contains { words.contains($0) }
        let dirty = ["poo", "dirty", "stool", "bm", "soiled", "bowel"].contains { words.contains($0) }
        let both = ["both", "mixed", "wet + dirty", "wet and dirty"].contains { words.contains($0) }
        if both || (wet && dirty) { return .mixed }
        if dirty { return .dirty }
        if wet { return .wet }
        if words.contains("dry") || words.contains("clean") { return .dry }
        return nil
    }

    /// A poop color MyBaby knows, from its name. Anything else stays in the notes.
    static func poopColor(_ text: String) -> PoopColor? {
        let word = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = PoopColor(rawValue: word) { return color }
        switch word {
        case "mustard", "light yellow", "dark yellow": return .yellow
        case "dark green", "light green": return .green
        case "light brown", "dark brown", "tan": return .brown
        case "grey", "gray", "pale", "chalky": return .white
        default: return nil
        }
    }

    /// A poop consistency MyBaby knows, from the words other apps use. Anything else stays in the notes.
    static func poopConsistency(_ text: String) -> PoopConsistency? {
        let word = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let consistency = PoopConsistency(rawValue: word) { return consistency }
        switch word {
        case "watery", "very runny", "liquid", "loose": return .runny
        case "mushy", "pasty", "creamy", "soft serve": return .soft
        case "solid", "firm", "formed stool": return .formed
        case "little balls", "pellets", "pebbles", "hard balls": return .hard
        default: return nil
        }
    }

    /// Breast milk or formula, from the bottle's contents.
    static func bottleType(_ text: String) -> FeedingType? {
        let words = text.lowercased()
        if words.contains("formula") { return .formula }
        if words.contains("breast") || words.contains("expressed") || words.contains("pumped") {
            return .breastMilkBottle
        }
        return nil
    }
}

/// Which side a breastfeed or a pumping amount was on.
enum ImportedSide: Sendable {
    case left, right, both

    init?(letter: String) {
        switch letter {
        case "L": self = .left
        case "R": self = .right
        default: return nil
        }
    }

    /// "Left", "R", "both", "L+R" and the like.
    init?(word: String) {
        let text = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("both") || text == "lr" || text == "rl" || text == "l+r" || text == "r+l"
            || text == "l/r" || text == "b" || (text.contains("left") && text.contains("right")) {
            self = .both
        } else if text == "l" || text.hasPrefix("left") {
            self = .left
        } else if text == "r" || text.hasPrefix("right") {
            self = .right
        } else {
            return nil
        }
    }
}

/// The unit of a duration written as a plain number.
enum DurationUnit: String, CaseIterable, Identifiable, Sendable {
    case minutes, seconds, hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return String(localized: "Minutes", comment: "Import: the unit of a duration column")
        case .seconds: return String(localized: "Seconds", comment: "Import: the unit of a duration column")
        case .hours: return String(localized: "Hours", comment: "Import: the unit of a duration column")
        }
    }

    var minutes: Double {
        switch self {
        case .minutes: return 1
        case .seconds: return 1.0 / 60
        case .hours: return 60
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
