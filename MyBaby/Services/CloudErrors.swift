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

    static let waitingForConnection = "Waiting for a connection"
    static let storageFull = "Your iCloud storage is full, so changes aren't syncing. Free up space in Settings › your name › iCloud."
    static let notSetUpForThisVersion = "iCloud isn't set up for this version of MyBaby yet."
    static let developerSchemaNote = "For developers: the CloudKit schema needs deploying to Production (see the README's TestFlight & App Store checklist)."

    // MARK: What kind of problem

    private enum Kind {
        case noAccount, quota, schema, zoneDeleted, network, busy, other
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
        if isSchemaProblem(errors) || (unknownItemIsSchema && codes.contains(.unknownItem)) { return .schema }
        if codes.contains(.userDeletedZone) { return .zoneDeleted }
        if !codes.isDisjoint(with: [.networkUnavailable, .networkFailure]) { return .network }
        if !codes.isDisjoint(with: [.zoneBusy, .serviceUnavailable, .requestRateLimited]) { return .busy }
        return .other
    }

    /// The server turned down a record type or field it doesn't know: in TestFlight and App Store
    /// builds, that's the schema not having been deployed to Production.
    private static func isSchemaProblem(_ errors: [NSError]) -> Bool {
        let hints = ["production", "cannot create or modify field", "did not find record type", "schema"]
        return errors.contains { error in
            let text = describe(error).lowercased()
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
            return SyncIssue(message: "Sign in to iCloud to sync", isWaitingForConnection: false)
        case .quota:
            return SyncIssue(message: storageFull, isWaitingForConnection: false)
        case .schema:
            return SyncIssue(message: notSetUpForThisVersion, isWaitingForConnection: false)
        case .zoneDeleted:
            return SyncIssue(message: "Your iCloud copy was deleted from another device", isWaitingForConnection: false)
        case .busy:
            return SyncIssue(message: "iCloud is busy, retrying soon", isWaitingForConnection: false)
        case .other:
            return SyncIssue(message: "Couldn't sync (\(shortCode(for: error)))", isWaitingForConnection: false)
        }
    }

    /// For an invitation that couldn't be set up (or joined): what to do first, then a "Details:"
    /// line. `otherwise` is the first line for anything unexpected.
    static func sharingMessage(
        for error: Error,
        otherwise: String = "Couldn't set up sharing. Please try again in a minute."
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
            headline = "\(waitingForConnection). Try again once this iPhone is online."
        case .quota:
            headline = storageFull
        case .schema:
            headline = "\(notSetUpForThisVersion)\n\(developerSchemaNote)"
        case .zoneDeleted, .busy, .other:
            headline = otherwise
        }
        return "\(headline)\n\n\(details(for: error))"
    }

    /// "Details: Cocoa error 134410: … · CKError 2: …", every error inside, for a bug report.
    static func details(for error: Error) -> String {
        var seen = Set<String>()
        let parts = chain(of: error).compactMap { error -> String? in
            let text = "\(domainName(error.domain)) \(error.code): \(describe(error))"
            return seen.insert(text).inserted ? String(text.prefix(300)) : nil
        }
        return "Details: " + parts.prefix(5).joined(separator: " · ")
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
