import CoreData
import SwiftUI

/// The state of Settings › Your data › Import from another app, from picking the file to the summary.
///
/// The file's contents live only here, in memory, while the sheet is open: reading, mapping and the
/// preview all work on `tables`, and nothing is written until the parent taps Import. Closing the
/// sheet lets go of all of it.
@MainActor
final class ImportFlow: ObservableObject {
    enum Step {
        case choose, mapping, preview, importing, finished
    }

    /// Where the entries go: a baby already in MyBaby, or one added for the import.
    enum Target: Hashable {
        case existing(NSManagedObjectID)
        case newBaby
    }

    @Published var step: Step = .choose

    // Choosing
    @Published private(set) var fileNames: [String] = []
    @Published private(set) var tables: [ImportTable] = []
    /// `nil` is Auto-detect.
    @Published var source: ImportSource?
    @Published private(set) var detected: ImportSource?
    @Published var target: Target
    @Published var newBabyName = ""
    @Published var newBabyHasBirthday = false
    @Published var newBabyBirthday = Date.now
    @Published var timeZoneID = TimeZone.current.identifier

    // Mapping (another app)
    @Published var mapping = GenericMapping()
    @Published var genericTableIndex = 0
    /// How the date column looks to be written, and the formats that read it, worked out once per change.
    @Published private(set) var dateGuess: DateGuess?
    @Published private(set) var dateChoices: [DatePattern] = []

    // Preview
    @Published var dateOrder: DateOrder = .automatic
    @Published private(set) var fullPlan: ImportPlan?
    /// Which of the file's babies to bring in, when it names more than one.
    @Published var fileBaby: String?
    @Published private(set) var duplicateCount: Int?

    // Importing
    @Published private(set) var progress = 0
    @Published private(set) var summary: ImportSummary?
    @Published private(set) var record: ImportRecord?
    @Published private(set) var importedBabyName = ""
    /// How many entries "Remove this import" took out, once it has.
    @Published private(set) var removedCount: Int?

    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var importTask: Task<Void, Never>?
    private var planTask: Task<Void, Never>?

    init(baby: Baby) {
        target = .existing(baby.objectID)
    }

    // MARK: Derived

    var effectiveSource: ImportSource {
        source ?? detected ?? .generic
    }

    var options: ImportOptions {
        var options = ImportOptions()
        options.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        options.dateOrder = dateOrder
        options.volumeUnit = UserDefaults.shared.string(forKey: SettingsKey.volumeUnit).flatMap(VolumeUnit.init(rawValue:)) ?? .ml
        return options
    }

    /// The plan for the chosen baby of the file.
    var plan: ImportPlan? {
        fullPlan.map { $0.only(baby: fileBaby) }
    }

    var genericTable: ImportTable? {
        tables.indices.contains(genericTableIndex) ? tables[genericTableIndex] : tables.first
    }

    var canContinue: Bool {
        !tables.isEmpty && !isWorking
    }

    /// Whether Import can go ahead: something to add, the duplicates counted, and a name for a new baby.
    var canImport: Bool {
        guard let plan, !plan.entries.isEmpty, duplicateCount != nil, !isWorking else { return false }
        return target != .newBaby || !newBabyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Choosing

    func filesPicked(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isWorking = true
            errorMessage = nil
            Task {
                do {
                    let tables = try await Task.detached(priority: .userInitiated) { try ImportFiles.read(urls) }.value
                    self.tables = tables
                    self.fileNames = urls.map(\.lastPathComponent)
                    self.detected = ImportFiles.detect(tables)
                    self.genericTableIndex = tables.firstIndex { !$0.rows.isEmpty } ?? 0
                    self.fullPlan = nil
                } catch {
                    self.tables = []
                    self.fileNames = []
                    self.detected = nil
                    self.errorMessage = error.localizedDescription
                }
                self.isWorking = false
            }
        }
    }

    /// From the first screen: to the mapping for another app, or straight to the preview.
    func continueFromChoose() {
        let source = effectiveSource
        guard ImportFiles.source(source, recognizes: tables) else {
            errorMessage = ImportError.notRecognized(source).localizedDescription
            return
        }
        if source == .generic {
            guessMapping()
            step = .mapping
        } else {
            step = .preview
            rebuildPlan()
        }
    }

    /// Columns matched from the headers of the chosen file.
    func guessMapping() {
        guard let table = genericTable else { return }
        mapping = GenericMapping.guess(for: table, options: options)
        refreshDateChoices(choosingPattern: false)
    }

    /// After the date or time column changes: guesses the format again (choosing it when asked), and
    /// lists the formats that read the first rows, the suggested one first.
    func refreshDateChoices(choosingPattern: Bool) {
        guard let table = genericTable else { return }
        let guess = GenericCSVImporter.dateGuess(table, mapping: mapping, options: options)
        dateGuess = guess
        if choosingPattern { mapping.datePattern = guess?.pattern }
        var readable: [DatePattern] = []
        if mapping[.dateTime] != nil {
            let samples = table.rows.prefix(20).map { GenericCSVImporter.dateText($0, mapping: mapping) }
            for pattern in ImportDates.patterns {
                let reader = DateReader(pattern: pattern, timeZone: options.timeZone)
                if samples.contains(where: { reader.date($0) != nil }) { readable.append(pattern) }
            }
        }
        if let suggested = guess?.pattern {
            readable.removeAll { $0 == suggested }
            readable.insert(suggested, at: 0)
        }
        if let current = mapping.datePattern, !readable.contains(current) { readable.append(current) }
        dateChoices = readable
    }

    /// Back one screen, keeping every choice made.
    func goBack() {
        planTask?.cancel()
        isWorking = false
        switch step {
        case .mapping: step = .choose
        case .preview: step = effectiveSource == .generic ? .mapping : .choose
        default: break
        }
    }

    func continueFromMapping() {
        step = .preview
        rebuildPlan()
    }

    // MARK: The plan

    /// Reads the file again with the current choices, off the main thread, then counts what's already in MyBaby.
    func rebuildPlan() {
        planTask?.cancel()
        isWorking = true
        duplicateCount = nil
        let source = effectiveSource
        let tables = self.tables
        let options = self.options
        let mapping = self.mapping
        let table = genericTable
        planTask = Task {
            let plan = await Task.detached(priority: .userInitiated) { () -> ImportPlan in
                if source == .generic, let table {
                    return GenericCSVImporter.read(table, mapping: mapping, options: options)
                }
                return ImportFiles.plan(source, tables: tables, options: options)
            }.value
            guard !Task.isCancelled else { return }
            fullPlan = plan
            if !plan.babyNames.isEmpty, fileBaby.map({ plan.babyNames.contains($0) }) != true {
                fileBaby = preferredFileBaby(in: plan.babyNames)
            }
            if target == .newBaby, newBabyName.isEmpty, let name = fileBaby ?? plan.babyNames.first {
                newBabyName = name
            }
            if target == .newBaby, let birth = plan.babyBirthDate, !newBabyHasBirthday {
                newBabyBirthday = birth
                newBabyHasBirthday = true
            }
            isWorking = false
            await countDuplicates()
        }
    }

    /// The file's baby with the same name as the chosen one, or the first.
    private func preferredFileBaby(in names: [String]) -> String? {
        let wanted: String
        switch target {
        case .existing(let id):
            wanted = (PersistenceController.shared.viewContext.object(with: id) as? Baby)?.name ?? ""
        case .newBaby:
            wanted = newBabyName
        }
        return names.first { $0.caseInsensitiveCompare(wanted) == .orderedSame } ?? names.first
    }

    func fileBabyChanged() {
        Task { await countDuplicates() }
    }

    private func countDuplicates() async {
        guard case .existing(let babyID) = target, let entries = plan?.entries, !entries.isEmpty else {
            duplicateCount = 0
            return
        }
        duplicateCount = nil
        duplicateCount = await ImportWriter.countDuplicates(entries, babyID: babyID, container: PersistenceController.shared.container)
    }

    // MARK: Importing

    func startImport() {
        guard let plan, !plan.entries.isEmpty else { return }
        step = .importing
        progress = 0
        importTask = Task {
            let persistence = PersistenceController.shared
            let babyID: NSManagedObjectID
            switch target {
            case .existing(let id):
                babyID = id
                importedBabyName = (persistence.viewContext.object(with: id) as? Baby)?.displayName ?? String(localized: "Baby")
            case .newBaby:
                let name = newBabyName.trimmingCharacters(in: .whitespacesAndNewlines)
                let baby = await persistence.addBaby(name: name, birthDate: newBabyHasBirthday ? newBabyBirthday : nil)
                if let sex = plan.babySex {
                    baby.sex = sex
                    baby.managedObjectContext?.saveIfChanged()
                }
                babyID = baby.objectID
                importedBabyName = baby.displayName
            }
            let batchID = ImportHistory.newBatchID()
            var record = ImportRecord(
                id: batchID, date: .now, source: plan.source,
                fileName: fileNames.joined(separator: ", "), babyName: importedBabyName, added: 0
            )
            // Saved before the first entry, so even an import that's stopped or interrupted can be removed.
            ImportHistory.upsert(record)
            self.record = record
            do {
                let summary = try await ImportWriter.write(
                    plan.entries, babyID: babyID, batchID: batchID, container: persistence.container
                ) { [weak self] done in
                    self?.progress = done
                }
                record.added = summary.added
                record.wasStopped = summary.wasStopped
                if summary.added == 0 {
                    // Nothing to remove later.
                    ImportHistory.remove(id: batchID)
                } else {
                    ImportHistory.upsert(record)
                }
                self.record = record
                self.summary = summary
            } catch {
                record.added = ImportWriter.count(batchID: batchID, in: persistence.viewContext)
                record.wasStopped = true
                if record.added > 0 { ImportHistory.upsert(record) } else { ImportHistory.remove(id: batchID) }
                self.record = record
                var summary = ImportSummary()
                summary.added = record.added
                summary.wasStopped = true
                self.summary = summary
                errorMessage = String(localized: "The import stopped partway: \(error.localizedDescription)", comment: "The reason")
            }
            step = .finished
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    /// Removes what an import added, from its summary screen.
    func removeImported() async {
        guard let record else { return }
        isWorking = true
        do {
            removedCount = try await ImportWriter.remove(batchID: record.id, container: PersistenceController.shared.container)
            ImportHistory.remove(id: record.id)
            self.record = nil
        } catch {
            errorMessage = String(localized: "Couldn't remove the import: \(error.localizedDescription)", comment: "The reason")
        }
        isWorking = false
    }

    var isImporting: Bool { step == .importing }
}
