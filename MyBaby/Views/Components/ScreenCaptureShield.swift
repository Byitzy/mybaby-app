import SwiftUI
import UIKit

/// Keeps a private screen out of screenshots, screen recordings, AirPlay and mirroring.
///
/// iOS has no public switch for this, so it uses two things:
/// - While the screen is being recorded, mirrored or sent with AirPlay (`sceneCaptureState`), the
///   screen is covered with the privacy curtain. That's public API and always works.
/// - For screenshots, the screen's view is drawn inside the layer iOS uses for password fields
///   (a `UITextField` with `isSecureTextEntry`), which iOS leaves blank in screenshots and
///   recordings. Banking and password apps do the same. If a future iOS changes that layer and it
///   can't be found, the screen simply isn't protected from screenshots; it never hides it on screen.
///
/// It protects the whole navigation entry the view is in, so put it on each private screen,
/// including the ones a private page pushes.
private struct ScreenCaptureShield: UIViewRepresentable {
    /// True while the screen is recorded, mirrored or sent with AirPlay.
    @Binding var isCaptured: Bool

    func makeUIView(context: Context) -> ShieldView {
        let view = ShieldView()
        view.onCaptureChange = { captured in
            if isCaptured != captured { isCaptured = captured }
        }
        return view
    }

    func updateUIView(_ uiView: ShieldView, context: Context) {}

    static func dismantleUIView(_ uiView: ShieldView, coordinator: ()) {
        uiView.unprotect()
    }

    final class ShieldView: UIView {
        var onCaptureChange: ((Bool) -> Void)?

        /// The screen's view, moved into `field`'s secure layer.
        private weak var protectedView: UIView?
        private var field: UITextField?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: ShieldView, _: UITraitCollection) in
                view.reportCapture()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                // Pushed under another screen, or gone: UIKit takes the screen's view out of its
                // container, so put things back the way they were.
                unprotect()
            } else {
                // Also after coming back from a pushed screen, when UIKit has put the view back in
                // its container the ordinary way.
                DispatchQueue.main.async { [weak self] in self?.protect() }
            }
            reportCapture()
        }

        private func reportCapture() {
            onCaptureChange?(traitCollection.sceneCaptureState == .active)
        }

        // MARK: Screenshots

        private func protect() {
            guard window != nil, let target = entryView, let container = target.superview,
                  let superlayer = target.layer.superlayer
            else { return }
            if protectedView === target, let field, target.layer.superlayer === secureLayer(of: field) { return }
            unprotect()

            let field = UITextField(frame: .zero)
            field.isSecureTextEntry = true
            field.isUserInteractionEnabled = false
            field.backgroundColor = .clear
            container.insertSubview(field, aboveSubview: target)
            field.layoutIfNeeded()
            guard let secure = secureLayer(of: field) else {
                // Not found on this iOS: leave the screen as it is.
                field.removeFromSuperview()
                return
            }
            secure.masksToBounds = false
            // Line the secure layer's corner up with the container's, so the screen stays in place.
            let offset = secure.convert(CGPoint.zero, to: field.layer)
            field.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
            // In the screen's place among its siblings, then the screen inside it.
            let index = superlayer.sublayers?.firstIndex(of: target.layer) ?? 0
            field.layer.removeFromSuperlayer()
            superlayer.insertSublayer(field.layer, at: UInt32(index))
            secure.addSublayer(target.layer)

            self.field = field
            protectedView = target
        }

        func unprotect() {
            guard let field else { return }
            if let target = protectedView, let fieldSuperlayer = field.layer.superlayer,
               target.layer.superlayer === secureLayer(of: field) {
                let index = fieldSuperlayer.sublayers?.firstIndex(of: field.layer) ?? 0
                fieldSuperlayer.insertSublayer(target.layer, at: UInt32(index))
            }
            field.layer.removeFromSuperlayer()
            field.removeFromSuperview()
            self.field = nil
            protectedView = nil
        }

        /// The secure text field's canvas: the layer iOS leaves out of screenshots.
        private func secureLayer(of field: UITextField) -> CALayer? {
            let canvas = field.subviews.first { NSStringFromClass(type(of: $0)).contains("CanvasView") }
            return canvas?.layer
        }

        /// The view of the navigation entry (or sheet, or tab) this view is in: the screen.
        private var entryView: UIView? {
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) {
                responder = current.next
            }
            var controller = responder as? UIViewController
            while let child = controller, let parent = child.parent {
                if parent is UINavigationController || parent is UITabBarController { break }
                controller = parent
            }
            return controller?.view
        }
    }
}

private struct PrivateScreen: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCaptured = false

    func body(content: Content) -> some View {
        content
            .background {
                ScreenCaptureShield(isCaptured: $isCaptured)
                    .accessibilityHidden(true)
            }
            .overlay {
                // Away from the app (the app switcher's picture), or while recorded or mirrored.
                if scenePhase != .active || isCaptured {
                    PrivacyCurtain(isCaptured: isCaptured)
                }
            }
    }
}

extension View {
    /// For private screens, like the parent care page and the screens it opens: left out of
    /// screenshots, covered while the screen is recorded, mirrored or sent with AirPlay, and
    /// blurred in the app switcher.
    func privateScreen() -> some View {
        modifier(PrivateScreen())
    }
}
