import Foundation

/// Reads CSV text into rows, the way spreadsheets write it (RFC 4180): fields in double quotes can hold
/// the separator, line breaks and doubled quotes (""), and lines can end in CRLF or LF.
///
/// The separator is found from the first line: a comma, a semicolon (spreadsheets in regions that write
/// 1,5 for one and a half) or a tab. Pure functions, so they can be tried on sample text without a file.
enum CSVReader {
    /// The most rows read from one file, so a huge or broken file can't take the phone's memory.
    static let maxRows = 250_000

    /// The rows of `text`, blank lines left out. The first row is usually the header.
    static func rows(_ text: String, separator: Unicode.Scalar? = nil) -> [[String]] {
        let separator = separator ?? detectSeparator(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        // Unicode scalars rather than Characters: Swift reads "\r\n" as one Character, which would hide
        // the line break from the checks below.
        var scalars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?

        func next() -> Unicode.Scalar? {
            if let scalar = pending {
                pending = nil
                return scalar
            }
            return scalars.next()
        }

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRow() {
            endField()
            // A blank line is one empty field; skip it.
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let scalar = next() {
            if rows.count >= maxRows { break }
            if inQuotes {
                if scalar == "\"" {
                    // A doubled quote is a quote; anything else ends the quoted part.
                    if let following = next() {
                        if following == "\"" {
                            field.append(following)
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            if scalar == separator {
                endField()
            } else if scalar == "\"" {
                // Quotes only open a quoted field at its start (after any spaces); elsewhere they're text.
                if String(field).trimmingCharacters(in: .whitespaces).isEmpty {
                    field = String.UnicodeScalarView()
                    inQuotes = true
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\r" {
                if let following = next(), following != "\n" {
                    pending = following
                }
                endRow()
            } else if scalar == "\n" {
                endRow()
            } else {
                field.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }

    /// The separator that splits the first line into the most columns, outside quotes. Comma when unsure.
    static func detectSeparator(_ text: String) -> Unicode.Scalar {
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for scalar in text.unicodeScalars.prefix(4_000) {
            if scalar == "\"" { inQuotes.toggle() }
            if inQuotes { continue }
            if scalar == "\n" || scalar == "\r" { break }
            if counts[scalar] != nil { counts[scalar, default: 0] += 1 }
        }
        // On a tie the comma wins, as the most common separator.
        let winner = counts.max { a, b in a.value == b.value ? (a.key != "," && b.key == ",") : a.value < b.value }
        guard let winner, winner.value > 0 else { return "," }
        return winner.key
    }

    /// The header and rows of `text`, with a byte-order mark and spaces around the header names removed.
    static func table(named name: String, text: String) -> ImportTable? {
        var all = rows(text)
        guard !all.isEmpty else { return nil }
        let header = all.removeFirst().map {
            $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard header.contains(where: { !$0.isEmpty }) else { return nil }
        return ImportTable(name: name, header: header, rows: all)
    }

    /// The file's text: UTF-8 (with or without a byte-order mark) or UTF-16 as marked, otherwise the
    /// Windows and Latin encodings older spreadsheet apps use.
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        for encoding in [String.Encoding.utf8, .windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
            }
        }
        return nil
    }
}
