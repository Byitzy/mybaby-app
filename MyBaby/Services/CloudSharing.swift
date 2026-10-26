import CloudKit
import CoreData
import UIKit

/// Shows Apple's iCloud sharing sheet for inviting the other parent, or managing who has access.
@MainActor
enum CloudSharing {
    private static let delegate = SharingDelegate()

    static func present(_ share: CKShare, for baby: Baby) {
        let persistence = PersistenceController.shared
        let controller = UICloudSharingController(share: share, container: persistence.cloudKitContainer)
        delegate.share = share
        delegate.store = baby.objectID.persistentStore ?? persistence.privateStore
        controller.delegate = delegate
        // The owner picks each person's permission in the sheet: a partner can make changes, and a
        // grandparent or a nanny can be invited as view only.
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        // UICloudSharingController doesn't work inside a SwiftUI sheet, so present it from UIKit.
        guard let presenter = topViewController() else { return }
        // On iPad it can open as a popover, which needs something to point at, or UIKit stops the app:
        // the middle of the screen, with no arrow. iPhone has no popover, so nothing changes there.
        if let popover = controller.popoverPresentationController, let view = presenter.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    /// The share being shown, and the store holding the baby it shares.
    var share: CKShare?
    var store: NSPersistentStore?

    /// "Ava's care log", from the babies' names; the sheet saves it into the share.
    func itemTitle(for csc: UICloudSharingController) -> String? {
        PersistenceController.shared.invitationTitle
            ?? csc.share?[CKShare.SystemFieldKey.title] as? String
            ?? String(localized: "Baby's care log", comment: "Title of the iCloud invitation when no baby has a name")
    }

    /// The app icon, instead of a generic document, in the sheet and the invitation.
    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        ShareThumbnail.pngData
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        let message = CloudErrors.sharingMessage(for: error)
        Task { @MainActor in
            CloudStatus.shared.lastError = message
        }
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share, let store {
            PersistenceController.shared.persistUpdatedShare(share, in: store)
        }
    }

    /// The owner stopped sharing, or the invited parent removed themselves.
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        guard let share = csc.share ?? self.share, let store else { return }
        Task { @MainActor in
            await PersistenceController.shared.sharingStopped(share, in: store)
        }
    }
}

/// The app icon as a small PNG, for the share's thumbnail (`CKShare.SystemFieldKey.thumbnailImageData`)
/// and the sharing sheet. App icons can't always be loaded by name, so there's a 256 px copy in
/// the asset catalog (ShareThumbnail) too.
enum ShareThumbnail {
    static let pngData: Data? = {
        guard let icon = UIImage(named: "AppIcon") ?? UIImage(named: "ShareThumbnail") else { return nil }
        // Drawn at 256 px, so the share stays small even when the full-size icon loads.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            icon.draw(in: CGRect(origin: .zero, size: size))
        }
    }()
}
