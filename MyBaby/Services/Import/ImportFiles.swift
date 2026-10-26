import Foundation
import UniformTypeIdentifiers

/// Opens the files a parent picked and reads them into tables, on the iPhone.
///
/// The files are read straight from where they are (Files, iCloud Drive, a USB drive) through the
/// access the file picker grants, into memory. MyBaby never copies them into its own folders, and the
/// tables are let go when the import sheet closes, so nothing from the file is kept except the entries
/// the parent chose to import.
enum ImportFiles {
    /// What the file picker offers: CSV, TXT (and TSV) and ZIP.
    static let contentTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .zip]

    /// The largest file read, so a wrong pick (a video) fails quickly instead of filling memory.
    static let maxFileBytes = 50 * 1024 * 1024

    /// Every table in `urls`: each CSV or TXT file, and each CSV or TXT inside a ZIP.
    static func read(_ urls: [URL]) throws -> [ImportTable] {
        var tables: [ImportTable] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxFileBytes else { throw ImportError.tooLarge }
            // Coordinated, so a file in iCloud Drive is downloaded and not changed while it's read.
            var readData: Data?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
                readData = try? Data(contentsOf: readURL)
            }
            guard let data = readData, coordinationError == nil else { throw ImportError.unreadable(url.lastPathComponent) }
            guard data.count <= maxFileBytes else { throw ImportError.tooLarge }
            tables += try self.tables(from: data, named: url.lastPathComponent)
        }
        guard tables.contains(where: { !$0.rows.isEmpty }) else { throw ImportError.empty }
        return tables
    }

    /// The tables in one file's bytes, opening a ZIP when it is one.
    static func tables(from data: Data, named name: String) throws -> [ImportTable] {
        if ZipReader.isZip(data) {
            let entries = ZipReader.entries(in: data) { path in
                let file = (path as NSString).lastPathComponent
                let ext = (file as NSString).pathExtension.lowercased()
                // Skip the hidden copies macOS adds to ZIPs it makes.
                return ["csv", "txt", "tsv"].contains(ext) && !file.hasPrefix(".") && !path.hasPrefix("__MACOSX")
            }
            let tables = entries.compactMap { entry -> ImportTable? in
                guard let text = CSVReader.decode(entry.data) else { return nil }
                return CSVReader.table(named: (entry.name as NSString).lastPathComponent, text: text)
            }
            guard !tables.isEmpty else { throw ImportError.unreadable(name) }
            return tables
        }
        guard let text = CSVReader.decode(data), let table = CSVReader.table(named: name, text: text) else {
            throw ImportError.unreadable(name)
        }
        return [table]
    }

    /// Which app the tables came from, from their columns. Another app when none fits.
    static func detect(_ tables: [ImportTable]) -> ImportSource {
        if tables.contains(where: MyBabyImporter.recognizes) { return .mybaby }
        if tables.contains(where: HuckleberryImporter.recognizes) { return .huckleberry }
        if tables.contains(where: NaraBabyImporter.recognizes) { return .nara }
        if tables.contains(where: GlowBabyImporter.recognizes) { return .glow }
        return .generic
    }

    /// Whether `source`'s reader understands at least one of the tables.
    static func source(_ source: ImportSource, recognizes tables: [ImportTable]) -> Bool {
        switch source {
        case .mybaby: return tables.contains(where: MyBabyImporter.recognizes)
        case .huckleberry: return tables.contains(where: HuckleberryImporter.recognizes)
        case .glow: return tables.contains(where: GlowBabyImporter.recognizes)
        case .nara: return tables.contains(where: NaraBabyImporter.recognizes)
        case .generic: return true
        }
    }

    /// The plan for a known source. The generic importer needs its mapping, so it has its own call.
    static func plan(_ source: ImportSource, tables: [ImportTable], options: ImportOptions) -> ImportPlan {
        var plan: ImportPlan
        switch source {
        case .mybaby: plan = MyBabyImporter.read(tables, options: options)
        case .huckleberry: plan = HuckleberryImporter.read(tables, options: options)
        case .glow: plan = GlowBabyImporter.read(tables, options: options)
        case .nara: plan = NaraBabyImporter.read(tables, options: options)
        case .generic: plan = ImportPlan(source: .generic)
        }
        // Files the reader didn't understand (a stray note in the ZIP) are mentioned, not silently dropped.
        let unread = tables.filter { table in
            switch source {
            case .mybaby: return !MyBabyImporter.recognizes(table)
            case .huckleberry: return !HuckleberryImporter.recognizes(table)
            case .glow: return !GlowBabyImporter.recognizes(table)
            case .nara: return !NaraBabyImporter.recognizes(table)
            case .generic: return false
            }
        }
        for table in unread where !table.rows.isEmpty {
            plan.rowCount += table.rows.count
            let file = table.name
            let app = source.title
            plan.skip(
                String(localized: "\(file) (not a \(app) file MyBaby can read)", comment: "Import preview; a file name, then an app's name"),
                count: table.rows.count
            )
        }
        return plan
    }
}
