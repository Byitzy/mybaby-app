import Foundation

/// One import, for Settings › Your data › Recent imports and its "Remove this import".
struct ImportRecord: Codable, Identifiable, Equatable {
    /// Also the `importBatchID` on every entry it added.
    let id: String
    let date: Date
    let source: ImportSource
    let fileName: String
    let babyName: String
    var added: Int
    /// Stopped with Cancel before it finished. What was added stays until it's removed.
    var wasStopped = false

    /// "Huckleberry · 1,204 entries for Mavie", or "… (stopped early)".
    var summary: String {
        let app = source.title
        let count = added.formatted()
        switch (added == 1, wasStopped) {
        case (true, false):
            return String(localized: "\(app) · 1 entry for \(babyName)", comment: "A recent import; the app, then the baby's name")
        case (true, true):
            return String(
                localized: "\(app) · 1 entry for \(babyName) (stopped early)",
                comment: "A recent import that was cancelled; the app, then the baby's name"
            )
        case (false, false):
            return String(
                localized: "\(app) · \(count) entries for \(babyName)",
                comment: "A recent import; the app, the number of entries, then the baby's name"
            )
        case (false, true):
            return String(
                localized: "\(app) · \(count) entries for \(babyName) (stopped early)",
                comment: "A recent import that was cancelled; the app, the number of entries, then the baby's name"
            )
        }
    }
}

/// The imports made on this iPhone, newest first, so one can be removed again.
///
/// Kept on this iPhone only (`UserDefaults.standard`), and only the summary: the file itself is never
/// kept. The entries carry the import's id (`importBatchID`), so removing works however long ago it
/// was, and from the shared log too, as long as this list still has it.
enum ImportHistory {
    private static let key = "importHistory"
    /// Imports listed, oldest dropped first.
    static let limit = 10

    static func load(_ defaults: UserDefaults = .standard) -> [ImportRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([ImportRecord].self, from: data)
        else { return [] }
        return records
    }

    static func save(_ records: [ImportRecord], _ defaults: UserDefaults = .standard) {
        let kept = Array(records.sorted { $0.date > $1.date }.prefix(limit))
        if let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: key)
        }
    }

    /// Adds `record`, or updates the one with its id.
    static func upsert(_ record: ImportRecord, _ defaults: UserDefaults = .standard) {
        var records = load(defaults).filter { $0.id != record.id }
        records.append(record)
        save(records, defaults)
    }

    static func remove(id: String, _ defaults: UserDefaults = .standard) {
        save(load(defaults).filter { $0.id != id }, defaults)
    }

    /// A new id for an import: unique, and readable in a database browser ("import-2026-10-25-…").
    static func newBatchID(now: Date = .now) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        return "import-\(day)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
