import CloudKit
import CoreData
import Foundation

/// Plain words for what went wrong with iCloud, for the sync status row (`SyncStatus`) and for
/// sharing. Error codes stay out of the first line; sharing keeps them on a "Details:" line.
///
/// Core Data wraps the CloudKit error it got (`NSUnderlyingErrorKey`), and a CloudKit partial
/// failure keeps the real reason in its per-item errors, so every error inside is looked at.
enum CloudErrors {
    /// What the status row shows for a sync event that failed.
    struct SyncIssue: Equatable {
        let message: String
        /// Offline: the container tries again by itself once there's a connection.
        let isWaitingForConnection: Bool
    }

    static let waitingForConnection = String(localized: "Waiting for a connection", comment: "iCloud sync status while offline")
    static let storageFull = String(localized: "Your iCloud storage is full, so changes aren't syncing. Free up space in Settings › your name › iCloud.")
    static let notSetUpForThisVersion = String(localized: "iCloud isn't set up for this version of MyBaby yet.")
    // Not localized: it's for the developer, and points at the README.
    static let developerSchemaNote = "For developers: the CloudKit schema needs deploying to Production (see the README's TestFlight & App Store checklist)."

    // MARK: What kind of problem

    private enum Kind {
        case noAccount, quota, schema, shareNotFound, zoneDeleted, network, busy, other
    }

    /// The most useful explanation among all the errors inside `error`.
    /// `unknownItemIsSchema`: when sharing, a missing item means the record types aren't in
    /// Production yet. While syncing, the container deals with missing records itself.
    private static func kind(of error: Error, unknownItemIsSchema: Bool) -> Kind {
        let errors = chain(of: error)
        let codes = Set(ckCodes(in: errors))
        if codes.contains(.notAuthenticated) || errors.contains(where: { $0.domain == NSCocoaErrorDomain && $0.code == 134400 }) {
            // 134400: Core Data couldn't start iCloud because there's no iCloud account.
            return .noAccount
        }
        if codes.contains(.quotaExceeded) { return .quota }
        if isShareNotFound(errors) { return .shareNotFound }
        if isSchemaProblem(errors) || (unknownItemIsSchema && codes.contains(.unknownItem)) { return .schema }
        if codes.contains(.userDeletedZone) { return .zoneDeleted }
        if !codes.isDisjoint(with: [.networkUnavailable, .networkFailure]) { return .network }
        if !codes.isDisjoint(with: [.zoneBusy, .serviceUnavailable, .requestRateLimited]) { return .busy }
        return .other
    }

    /// The record types or fields aren't in iCloud yet: in TestFlight and App Store builds, the schema
    /// hasn't been deployed to Production. A missing item counts too.
    static func isSchemaError(_ error: Error) -> Bool {
        kind(of: error, unknownItemIsSchema: true) == .schema
    }

    /// The invitation's share isn't in iCloud: it was replaced by a newer invitation or stopped, or it
    /// was made by a build from Xcode, which uses CloudKit's separate Development environment.
    private static func isShareNotFound(_ errors: [NSError]) -> Bool {
        errors.contains { error in
            matchText(error).contains("share not found")
                || (error.domain == "CKInternalErrorDomain" && error.code == 2003)
        }
    }

    static let shareNotFound = String(localized: "This invitation can't be found. It may have been replaced by a newer one or stopped, or it was sent from a test build. Ask your partner to send a new invitation from More › Settings › Manage sharing, with both of you on the TestFlight or App Store version of MyBaby.")

    /// The server turned down a record type or field it doesn't know: in TestFlight and App Store
    /// builds, that's the schema not having been deployed to Production.
    private static func isSchemaProblem(_ errors: [NSError]) -> Bool {
        let hints = ["production", "cannot create or modify field", "did not find record type", "schema"]
        return errors.contains { error in
            let text = matchText(error)
            return hints.contains { text.contains($0) }
        }
    }

    // MARK: Messages

    /// For the sync status row. The code of an unexpected error is kept so it can be looked up.
    static func syncIssue(for error: Error) -> SyncIssue {
        switch kind(of: error, unknownItemIsSchema: false) {
        case .network:
            return SyncIssue(message: waitingForConnection, isWaitingForConnection: true)
        case .noAccount:
            return SyncIssue(message: String(localized: "Sign in to iCloud to sync"), isWaitingForConnection: false)
        case .quota:
            return SyncIssue(message: storageFull, isWaitingForConnection: false)
        case .schema:
            return SyncIssue(message: notSetUpForThisVersion, isWaitingForConnection: false)
        case .shareNotFound:
            return SyncIssue(message: String(localized: "A shared log is no longer available"), isWaitingForConnection: false)
        case .zoneDeleted:
            return SyncIssue(message: String(localized: "Your iCloud copy was deleted from another device"), isWaitingForConnection: false)
        case .busy:
            return SyncIssue(message: String(localized: "iCloud is busy, retrying soon"), isWaitingForConnection: false)
        case .other:
            // The code stays as it is, e.g. "CKError 25", so it can be looked up.
            return SyncIssue(message: String(localized: "Couldn't sync (\(shortCode(for: error)))", comment: "The parentheses hold an error code like CKError 25"), isWaitingForConnection: false)
        }
    }

    /// For an invitation that couldn't be set up (or joined): what to do first, then a "Details:"
    /// line. `otherwise` is the first line for anything unexpected.
    static func sharingMessage(
        for error: Error,
        otherwise: String = String(localized: "Couldn't set up sharing. Please try again in a minute.")
    ) -> String {
        // The app's own reasons are already in plain words.
        if let error = error as? SharingError {
            return error.localizedDescription
        }
        let headline: String
        switch kind(of: error, unknownItemIsSchema: true) {
        case .noAccount:
            headline = ICloudProblem.noAccount.message
        case .network:
            headline = String(localized: "Waiting for a connection. Try again once this iPhone is online.")
        case .quota:
            headline = storageFull
        case .schema:
            headline = "\(notSetUpForThisVersion)\n\(developerSchemaNote)"
        case .shareNotFound:
            headline = shareNotFound
        case .zoneDeleted, .busy, .other:
            headline = otherwise
        }
        return "\(headline)\n\n\(details(for: error))"
    }

    /// "Details: Cocoa error 134410: … · CKError 2: …", every error inside, for a bug report. Only the
    /// "Details:" label is translated; the errors stay as the system gave them, so they can be looked up.
    static func details(for error: Error) -> String {
        var seen = Set<String>()
        let parts = chain(of: error).compactMap { error -> String? in
            let text = "\(domainName(error.domain)) \(error.code): \(describe(error))"
            return seen.insert(text).inserted ? String(text.prefix(300)) : nil
        }
        let list = parts.prefix(5).joined(separator: " · ")
        return String(localized: "Details: \(list)", comment: "Technical error details for a bug report, which stay in English")
    }

    /// Core Data's own CloudKit errors (134400–134499), such as 134410 when sharing starts before
    /// iCloud has finished setting up the store. Often gone a moment later.
    static func isCoreDataCloudKitError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && (134400...134499).contains(error.code)
    }

    // MARK: Looking inside errors

    /// `error`, the errors it wraps, and the per-item errors of a CloudKit partial failure.
    static func chain(of error: Error) -> [NSError] {
        var found: [NSError] = []
        var queue: [NSError] = [error as NSError]
        while !queue.isEmpty, found.count < 20 {
            let next = queue.removeFirst()
            found.append(next)
            queue += next.underlyingErrors.map { $0 as NSError }
            if next.domain == CKError.errorDomain,
               let items = next.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                queue += items.values.map { $0 as NSError }
            }
        }
        return found
    }

    /// The CloudKit codes found, leaving out the ones that only say "see the other errors".
    private static func ckCodes(in errors: [NSError]) -> [CKError.Code] {
        errors
            .filter { $0.domain == CKError.errorDomain }
            .compactMap { CKError.Code(rawValue: $0.code) }
            .filter { $0 != .partialFailure && $0 != .batchRequestFailed }
    }

    /// "CKError 25", or the Cocoa code when CloudKit gave none.
    private static func shortCode(for error: Error) -> String {
        let errors = chain(of: error)
        let best = errors.first { error in
            error.domain == CKError.errorDomain
                && error.code != CKError.Code.partialFailure.rawValue
                && error.code != CKError.Code.batchRequestFailed.rawValue
        } ?? errors[0]
        return "\(domainName(best.domain)) \(best.code)"
    }

    private static func domainName(_ domain: String) -> String {
        switch domain {
        case CKError.errorDomain: return "CKError"
        case NSCocoaErrorDomain: return "Cocoa error"
        default: return domain
        }
    }

    /// Everything the error says, lowercased, for recognizing it. The server's own words (in
    /// English whatever the iPhone's language) are included, so this still works once iOS shows the
    /// description itself in French or Spanish.
    private static func matchText(_ error: NSError) -> String {
        var parts = [error.localizedDescription]
        for (_, value) in error.userInfo {
            if let text = value as? String { parts.append(text) }
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// The description, plus the server's own words when CloudKit sent them.
    private static func describe(_ error: NSError) -> String {
        var text = error.localizedDescription
        for key in [NSLocalizedFailureReasonErrorKey, NSDebugDescriptionErrorKey, "ServerErrorDescription"] {
            if let extra = error.userInfo[key] as? String, !extra.isEmpty, !text.contains(extra) {
                text += " (\(extra))"
            }
        }
        return text
    }
}
