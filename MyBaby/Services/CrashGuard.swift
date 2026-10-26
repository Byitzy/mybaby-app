import Foundation

/// Stops a crash loop in the work MyBaby asks iCloud to do directly, outside Core Data's syncing.
///
/// Each step is marked as running while it runs. If the app ended while a step was running, which
/// almost always means it crashed there, the next launch pauses that step for a day instead of
/// running into the same crash every time MyBaby opens, and says once which step it was, so it
/// can be reported. A parent can try a paused step again by hand.
enum CrashGuard {
    enum Step: String, CaseIterable {
        /// The nursery monitor's alert inbox (`AlertInboxes.refresh`).
        case alertInboxes
        /// Finishing the iCloud part of Delete all MyBaby data (`DataWipe`).
        case iCloudDeletion
    }

    /// How long a step stays paused after the app ended while it ran.
    static let pause: TimeInterval = 24 * 60 * 60

    private static let runningKey = "crashGuard.running"
    private static func pausedKey(_ step: Step) -> String { "crashGuard.paused.\(step.rawValue)" }
    private static var defaults: UserDefaults { .standard }

    /// Once at launch, before any step runs: steps left marked as running are paused. Returns a
    /// message for the steps paused just now, or nil.
    static func checkAfterLaunch() -> String? {
        let leftRunning = (defaults.stringArray(forKey: runningKey) ?? []).compactMap(Step.init(rawValue:))
        defaults.removeObject(forKey: runningKey)
        guard !leftRunning.isEmpty else { return nil }
        for step in leftRunning {
            defaults.set(Date.now, forKey: pausedKey(step))
        }
        // The step names stay as they are, so feedback that mentions them can be looked up.
        let codes = leftRunning.map(\.rawValue).joined(separator: ", ")
        return message(alertInboxes: leftRunning.contains(.alertInboxes), iCloudDeletion: leftRunning.contains(.iCloudDeletion), codes: codes)
    }

    /// The message after a pause, one whole sentence for each step (or both), so it reads naturally
    /// in every language.
    private static func message(alertInboxes: Bool, iCloudDeletion: Bool, codes: String) -> String {
        if alertInboxes && iCloudDeletion {
            return String(localized: "MyBaby closed unexpectedly last time while it was setting up alerts from a nursery monitor and finishing deleting your iCloud copy. To keep that from happening again, it won't try that until tomorrow. If you send feedback, mention: \(codes).", comment: "The argument is a technical name, which stays in English")
        }
        if iCloudDeletion {
            return String(localized: "MyBaby closed unexpectedly last time while it was finishing deleting your iCloud copy. To keep that from happening again, it won't try that until tomorrow. If you send feedback, mention: \(codes).", comment: "The argument is a technical name, which stays in English")
        }
        return String(localized: "MyBaby closed unexpectedly last time while it was setting up alerts from a nursery monitor. To keep that from happening again, it won't try that until tomorrow. If you send feedback, mention: \(codes).", comment: "The argument is a technical name, which stays in English")
    }

    /// Whether a step is paused after the app ended while it ran.
    static func isPaused(_ step: Step) -> Bool {
        guard let since = defaults.object(forKey: pausedKey(step)) as? Date else { return false }
        if Date.now.timeIntervalSince(since) < pause { return true }
        defaults.removeObject(forKey: pausedKey(step))
        return false
    }

    /// When the parent asks to try a paused step again.
    static func resume(_ step: Step) {
        defaults.removeObject(forKey: pausedKey(step))
    }

    /// Marks a step as running. Pair with `end`, usually in a `defer`.
    static func begin(_ step: Step) {
        var running = defaults.stringArray(forKey: runningKey) ?? []
        if !running.contains(step.rawValue) {
            running.append(step.rawValue)
            defaults.set(running, forKey: runningKey)
        }
    }

    static func end(_ step: Step) {
        var running = defaults.stringArray(forKey: runningKey) ?? []
        running.removeAll { $0 == step.rawValue }
        defaults.set(running, forKey: runningKey)
    }
}

/// Keeps the reason when the app is stopped by an uncaught exception, which iOS's crash reports
/// leave out, so the next launch can show it. That launch is a safe launch (`isSafeLaunch`):
/// iCloud stays paused for it, so a crash that comes from iCloud can't stop the app from opening.
enum LastCrash {
    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("LastCrash.txt")
    }

    /// As early as possible at launch. The handler runs just before iOS stops the app.
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(12).joined(separator: "\n")
            let text = "\(exception.name.rawValue): \(exception.reason ?? "no reason given")\n\n\(symbols)"
            let url = LastCrash.fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
    }

    /// What stopped the app last time, read once and then forgotten, so only one launch is safe.
    static let previous: String? = {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return String(decoding: data, as: UTF8.self)
    }()

    /// This launch keeps iCloud paused, because the last one was stopped by an exception.
    static var isSafeLaunch: Bool { previous != nil }

    /// For an alert: what happened, and the reason to pass on.
    static var message: String? {
        guard let previous else { return nil }
        // The reason stays as the system gave it, so it can be looked up.
        let reason = String((previous.components(separatedBy: "\n").first ?? previous).prefix(600))
        return String(localized: "MyBaby closed unexpectedly last time, so iCloud is paused until you open the app again. Please take a screenshot of this and send it with Settings › Send feedback.\n\n\(reason)", comment: "The argument is the technical reason, which stays in English")
    }
}
