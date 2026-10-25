import Foundation
import MetricKit

/// Crash and hang reports from MetricKit, kept on this iPhone so a parent can choose to attach the
/// latest one when they tell us something isn't working (see `FeedbackView`).
///
/// After MyBaby crashes or freezes, iOS hands the app a diagnostic report, usually the next time
/// it opens. A report holds technical details only: where in the code the app stopped, the iOS
/// version and the device model, never anything from the log. Nothing is sent anywhere: a report
/// only leaves the iPhone attached to an email the parent writes and sends themselves.
///
/// Reports are kept in the app's own Application Support folder (not the App Group, not iCloud,
/// and left out of iCloud Backup): the newest `maxCount`, about `maxBytes` in all, each for at most
/// `maxAge`. A report's date is in its file name, so cleaning up never reads file dates.
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()

    /// One report as iOS gave it.
    struct Report: Equatable {
        let fileName: String
        /// When iOS handed it to the app.
        let receivedAt: Date
        /// `MXDiagnosticPayload.jsonRepresentation()`, attached to the email as it is.
        let json: Data
    }

    static let maxCount = 3
    static let maxBytes = 200_000
    static let maxAge: TimeInterval = 30 * 24 * 3600

    private let lock = NSLock()
    private var isStarted = false

    /// Subscribes to MetricKit, and clears out old reports. Call once at launch.
    func start() {
        let first = lock.withLock { () -> Bool in
            defer { isStarted = true }
            return !isStarted
        }
        guard first else { return }
        MXMetricManager.shared.add(self)
        DispatchQueue.global(qos: .utility).async {
            self.lock.withLock { self.prune(now: .now) }
        }
    }

    // MARK: MXMetricManagerSubscriber

    /// Keeps the payloads that hold a crash or a hang. iOS may call this on any queue.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let now = Date.now
        let reports = payloads
            .filter { !($0.crashDiagnostics ?? []).isEmpty || !($0.hangDiagnostics ?? []).isEmpty }
            .enumerated()
            .map { index, payload in
                Report(fileName: Self.fileName(receivedAt: now, index: index), receivedAt: now, json: payload.jsonRepresentation())
            }
        guard !reports.isEmpty, let folder = Self.folder else { return }
        lock.withLock {
            for report in reports {
                try? report.json.write(to: folder.appendingPathComponent(report.fileName), options: .atomic)
            }
            prune(now: now)
        }
    }

    // MARK: Reading

    /// The reports on this iPhone, newest first.
    var reports: [Report] {
        lock.withLock { Self.kept(loadAll(), now: .now) }
    }

    // MARK: Keeping only a few

    /// The reports to keep: younger than `maxAge`, newest first, at most `maxCount` of them and
    /// `maxBytes` in all. A single report bigger than that isn't kept.
    static func kept(_ reports: [Report], now: Date) -> [Report] {
        var kept = reports
            .filter { now.timeIntervalSince($0.receivedAt) < maxAge && $0.json.count <= maxBytes }
            .sorted { $0.receivedAt > $1.receivedAt }
        kept = Array(kept.prefix(maxCount))
        while kept.reduce(0, { $0 + $1.json.count }) > maxBytes {
            kept.removeLast()
        }
        return kept
    }

    /// "report-1729876543000-0.json": milliseconds since 1970, then its place in the batch.
    static func fileName(receivedAt: Date, index: Int) -> String {
        "report-\(Int64(receivedAt.timeIntervalSince1970 * 1000))-\(index).json"
    }

    /// The date in a name made by `fileName(receivedAt:index:)`.
    static func receivedAt(fileName: String) -> Date? {
        let prefix = "report-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".json") else { return nil }
        guard let milliseconds = fileName.dropFirst(prefix.count).split(separator: "-").first.flatMap({ Int64($0) }) else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    // MARK: Files

    /// Application Support/CrashReports, made the first time it's needed.
    private static var folder: URL? {
        let fileManager = FileManager.default
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        var folder = support.appendingPathComponent("CrashReports", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            // Only useful on this iPhone, for a little while, so it's not worth a place in backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        return folder
    }

    /// Every report file. Only call with `lock` held.
    private func loadAll() -> [Report] {
        guard let folder = Self.folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return names.compactMap { name in
            guard let date = Self.receivedAt(fileName: name),
                  let json = try? Data(contentsOf: folder.appendingPathComponent(name))
            else { return nil }
            return Report(fileName: name, receivedAt: date, json: json)
        }
    }

    /// Deletes the reports `kept` leaves out. Only call with `lock` held.
    private func prune(now: Date) {
        guard let folder = Self.folder else { return }
        let all = loadAll()
        let keep = Set(Self.kept(all, now: now).map(\.fileName))
        for report in all where !keep.contains(report.fileName) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(report.fileName))
        }
    }
}
