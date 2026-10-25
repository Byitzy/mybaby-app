import CoreData
import Foundation
import UIKit

/// What a parent's feedback is about. Its title goes in the email's subject, so feedback is easy to sort.
enum FeedbackKind: String, CaseIterable, Identifiable {
    case problem, idea, love, question

    var id: String { rawValue }

    /// As the parent picks it, and in the subject.
    var title: String {
        switch self {
        case .problem: return "Something's not working"
        case .idea: return "An idea"
        case .love: return "Something I love"
        case .question: return "A question"
        }
    }

    var systemImage: String {
        switch self {
        case .problem: return "wrench.and.screwdriver"
        case .idea: return "lightbulb"
        case .love: return "heart"
        case .question: return "questionmark.bubble"
        }
    }

    /// The hint in the empty message box.
    var placeholder: String {
        switch self {
        case .problem: return "What happened, and what did you expect? The steps to make it happen again help a lot."
        case .idea: return "What would make your days and nights easier?"
        case .love: return "What do you enjoy about MyBaby?"
        case .question: return "What would you like to know?"
        }
    }
}

/// The optional technical details added to feedback, so a problem can be found without asking
/// the parent for them.
///
/// Only things about the app and the iPhone: never baby or parent names, birthdays, anything from
/// the log, photos, the Apple ID, or an identifier that stays the same from one report to the next.
/// The parent can read the exact `text` before sending ("See what's included" in `FeedbackView`).
struct FeedbackDiagnostics: Equatable {
    /// Whether a nursery monitor is part of this family's setup.
    enum NurseryMonitorUse: Equatable {
        /// No device in the log has been a monitor.
        case notUsed
        /// A device in the log has been the monitor, but this one isn't right now.
        case inFamily
        /// This device is the monitor right now.
        case thisDevice
    }

    var appVersion: String
    var appBuild: String
    var systemVersion: String
    /// The `utsname` machine, like "iPhone15,2".
    var deviceModel: String
    /// The iPhone's first preferred language, like "fr-CA".
    var language: String?
    /// The iPhone's region setting, like "CA".
    var region: String?
    var iCloudSync: Bool
    var isShared: Bool
    /// Just how many babies there are.
    var babyCount: Int
    var cryAlertsListening: Bool
    var nurseryMonitor: NurseryMonitorUse
    var lowPowerMode: Bool
    var thermalState: ProcessInfo.ThermalState

    /// Exactly what's added to the email.
    var text: String { Self.text(for: self) }

    /// The details as plain lines, one fact per line. Only reads `details`, so it's easy to test.
    static func text(for details: FeedbackDiagnostics) -> String {
        [
            "App: MyBaby \(details.appVersion) (build \(details.appBuild))",
            "iOS: \(details.systemVersion)",
            "Device: \(details.deviceModel)",
            "Language: \(details.language ?? "unknown")",
            "Region: \(details.region ?? "unknown")",
            "iCloud sync: \(details.iCloudSync ? "on" : "off")",
            "Shared log: \(details.isShared ? "yes" : "no")",
            "Babies: \(details.babyCount)",
            "Cry alerts: \(details.cryAlertsListening ? "listening now" : "not listening now")",
            "Nursery monitor: \(monitorText(details.nurseryMonitor))",
            "Low Power Mode: \(details.lowPowerMode ? "on" : "off")",
            "Thermal state: \(thermalText(details.thermalState))",
        ].joined(separator: "\n")
    }

    private static func monitorText(_ use: NurseryMonitorUse) -> String {
        switch use {
        case .notUsed: return "not used"
        case .inFamily: return "used in this family"
        case .thisDevice: return "this device is the monitor"
        }
    }

    private static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Reading them from this iPhone

extension FeedbackDiagnostics {
    /// "1.0", from the app's Info.plist.
    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// "12", from the app's Info.plist.
    static var currentAppBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    /// The model identifier, like "iPhone15,2" (the Simulator says which model it's pretending to be).
    static var deviceModelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// The details as they are on this iPhone right now.
    @MainActor
    static func current() -> FeedbackDiagnostics {
        let persistence = PersistenceController.shared
        let context = persistence.viewContext
        let sync = PersistenceController.isSyncEnabled
        let babyCount = (try? context.count(for: Baby.fetchAll())) ?? 0
        let monitorCount = (try? context.count(for: MonitorDevice.fetchAll())) ?? 0
        let monitor: NurseryMonitorUse
        if NurseryMonitor.shared.isActive {
            monitor = .thisDevice
        } else if monitorCount > 0 {
            monitor = .inFamily
        } else {
            monitor = .notUsed
        }
        let processInfo = ProcessInfo.processInfo

        return FeedbackDiagnostics(
            appVersion: currentAppVersion,
            appBuild: currentAppBuild,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: deviceModelIdentifier,
            language: Locale.preferredLanguages.first,
            region: Locale.current.region?.identifier,
            iCloudSync: sync,
            // Only an iCloud log can be shared.
            isShared: sync && (persistence.ownShare != nil || persistence.hasJoinedLog),
            babyCount: babyCount,
            cryAlertsListening: CryMonitor.shared.isListening,
            nurseryMonitor: monitor,
            lowPowerMode: processInfo.isLowPowerModeEnabled,
            thermalState: processInfo.thermalState
        )
    }
}

// MARK: - The email

/// A feedback email: who it goes to, its subject and its body, as the parent will see them in Mail.
struct FeedbackEmail: Equatable {
    var recipient: String
    var subject: String
    var body: String

    /// The email for `message`, with the technical details at the end when they're included.
    static func make(
        kind: FeedbackKind,
        message: String,
        diagnostics: FeedbackDiagnostics?,
        version: String,
        build: String,
        recipient: String = AppLinks.feedbackEmail
    ) -> FeedbackEmail {
        FeedbackEmail(
            recipient: recipient,
            subject: subject(kind: kind, version: version, build: build),
            body: body(message: message, diagnostics: diagnostics)
        )
    }

    /// "MyBaby feedback: An idea (1.0, build 12)".
    static func subject(kind: FeedbackKind, version: String, build: String) -> String {
        "MyBaby feedback: \(kind.title) (\(version), build \(build))"
    }

    static func body(message: String, diagnostics: FeedbackDiagnostics?) -> String {
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let diagnostics {
            body += "\n\n---\nTechnical details\n" + diagnostics.text
        }
        return body
    }

    /// A `mailto:` link with the subject and body filled in, for when Mail isn't set up.
    /// It can't carry attachments.
    var mailtoURL: URL? {
        URL(string: "mailto:\(recipient)?subject=\(Self.encode(subject))&body=\(Self.encode(body))")
    }

    /// Everything, to paste into any email app.
    var plainText: String {
        "To: \(recipient)\nSubject: \(subject)\n\n\(body)"
    }

    /// Percent-encodes everything but letters, digits and `-._~`, with line breaks as CRLF (RFC 6068).
    static func encode(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        return lines.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
