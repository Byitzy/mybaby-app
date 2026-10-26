import LocalAuthentication
import SwiftUI
import UIKit

/// Shows `content` only after Face ID, Touch ID, Optic ID or the iPhone's passcode, for a private page
/// like the parent care page.
///
/// The page is always locked; there's no setting to turn that off. The content isn't built until
/// the page is unlocked, so nothing in it is fetched or drawn before. It locks again every time:
/// when the parent leaves it (but not for a screen it opens itself, like My medicines), and as soon
/// as the app stops being active (Control Center, the app switcher, another app, the Lock Screen),
/// so coming back always asks again. It's also a `privateScreen()`: left out of screenshots,
/// covered while the screen is recorded or mirrored, and blurred in the app switcher.
///
/// It uses `.deviceOwnerAuthentication`: biometrics, with the passcode when they fail or are locked
/// out. An iPhone without a passcode can't lock anything, so the page stays closed until one is set.
struct PrivateContentLock<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private let title: Text
    private let message: Text
    /// Shown by iOS in the Face ID or passcode prompt.
    private let reason: String
    private let content: () -> Content

    /// What this iPhone can unlock with, and whether it has a passcode at all.
    @State private var security = DeviceSecurity.current()
    /// Unlocked since the last relock.
    @State private var isUnlocked = false
    /// The content stays built while it's covered by the lock screen, so a screen it pushed survives.
    /// False until the first unlock, and again after the app goes to the background.
    @State private var keepsContent = false
    @State private var isAuthenticating = false
    @State private var unlockError: String?
    @State private var isOnScreen = false
    /// Try once, by itself, when the page appears or the app comes back from the background.
    @State private var pendingAutoUnlock = true
    /// When the last Face ID or passcode sheet closed. The app can report going inactive just after
    /// it, and that mustn't lock the page that was just unlocked.
    @State private var authenticationEndedAt: Date?
    @State private var probe = NavigationEntryProbe()

    /// A literal title and message are looked up in the String Catalog, like `Text("…")`.
    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey = "Unlock to see your check-ins, medicines and notes.",
        reason: String = String(localized: "Unlock your private care page", comment: "Shown by iOS in the Face ID or passcode prompt"),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            titleText: Text(title),
            messageText: Text(message),
            reason: reason,
            content: content
        )
    }

    /// A title (and message) that's already localized is shown as it is.
    @_disfavoredOverload
    init<S: StringProtocol>(
        title: S,
        message: String? = nil,
        reason: String = String(localized: "Unlock your private care page", comment: "Shown by iOS in the Face ID or passcode prompt"),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            titleText: Text(title),
            messageText: message.map { Text($0) } ?? Text("Unlock to see your check-ins, medicines and notes."),
            reason: reason,
            content: content
        )
    }

    private init(
        titleText title: Text,
        messageText message: Text,
        reason: String,
        content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.reason = reason
        self.content = content
    }

    var body: some View {
        ZStack {
            if mountsContent {
                content()
                    .opacity(showsContent ? 1 : 0)
                    .allowsHitTesting(showsContent)
                    .accessibilityHidden(!showsContent)
            }
            if !showsContent {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsContent)
        // Outside the animation, so it covers the page at once when the app stops being active.
        .privateScreen()
        .navigationBarTitleDisplayMode(.inline)
        .background {
            NavigationEntryReader(probe: probe)
                .accessibilityHidden(true)
        }
        .onAppear {
            isOnScreen = true
            security = .current()
            pendingAutoUnlock = true
            autoUnlockIfNeeded()
        }
        .onDisappear {
            isOnScreen = false
            switch probe.isCoveredByPushedScreen {
            case .some(true):
                // One of the page's own screens (like My medicines) is on top: still the private page.
                break
            case .some(false):
                relock(keepingContent: false)
            case .none:
                // Can't tell, so lock, but keep the content built in case it pushed a screen.
                relock(keepingContent: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        // Also from UIKit, in case a screen the page pushed is on top and this one isn't redrawn.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            handle(.background)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            handle(.inactive)
        }
    }

    // MARK: State

    /// Only after unlocking, and only on an iPhone with a passcode to unlock with.
    private var showsContent: Bool { isUnlocked && security.hasPasscode }

    private var mountsContent: Bool { showsContent || keepsContent }

    private func relock(keepingContent: Bool) {
        isUnlocked = false
        if !keepingContent { keepsContent = false }
        unlockError = nil
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            relock(keepingContent: false)
            pendingAutoUnlock = true
        case .inactive:
            // The Face ID sheet makes the app inactive too, and that isn't leaving.
            let justAuthenticated = authenticationEndedAt.map { Date.now.timeIntervalSince($0) < 1.5 } ?? false
            if !isAuthenticating && !justAuthenticated {
                relock(keepingContent: false)
                pendingAutoUnlock = true
            }
        case .active:
            // A passcode may have been set or removed in Settings meanwhile.
            security = .current()
            autoUnlockIfNeeded()
        @unknown default:
            break
        }
    }

    /// Asks once by itself, only while the page is on screen and the app is active. Cancelling
    /// doesn't ask again: the Face ID sheet only makes the app inactive, never background.
    private func autoUnlockIfNeeded() {
        guard pendingAutoUnlock, isOnScreen, scenePhase == .active else { return }
        pendingAutoUnlock = false
        guard security.hasPasscode, !isUnlocked, !isAuthenticating else { return }
        Task { await unlock() }
    }

    @MainActor
    private func unlock() async {
        unlockError = nil
        switch await authenticate(reason: reason) {
        case .success:
            isUnlocked = true
            keepsContent = true
        case .cancelled:
            break
        case .noPasscode:
            // Nothing to unlock with: the page stays closed and says why.
            security.hasPasscode = false
        case .failed:
            unlockError = String(localized: "Couldn't unlock. Try again.")
        }
    }

    private typealias AuthenticationResult = DeviceAuthentication.Result

    /// Face ID, Touch ID or Optic ID, falling back to the passcode (also when biometrics are locked out).
    @MainActor
    private func authenticate(reason: String) async -> AuthenticationResult {
        guard !isAuthenticating else { return .cancelled }
        isAuthenticating = true
        defer {
            isAuthenticating = false
            authenticationEndedAt = .now
        }
        return await DeviceAuthentication.authenticate(reason: reason)
    }

    // MARK: Views

    private var lockScreen: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.l) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    VStack(spacing: Spacing.s) {
                        title
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if security.hasPasscode {
                            message
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This page opens only with Face ID, Touch ID or your passcode. Set a passcode in the Settings app (Face ID & Passcode) to open it.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)

                    if security.hasPasscode {
                        Button {
                            Task { await unlock() }
                        } label: {
                            Label(security.method.unlockTitle, systemImage: security.method.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isAuthenticating)
                    } else {
                        Button("Check again") {
                            security = .current()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if let unlockError {
                        NoticeLabel(unlockError)
                            .font(.footnote)
                    }
                }
                .padding(Spacing.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.screenBackground)
    }
}

// MARK: - Device

/// Asks for Face ID, Touch ID or Optic ID, falling back to the passcode (also when biometrics are
/// locked out), with `.deviceOwnerAuthentication`. Used by the private page lock, and before
/// Delete all MyBaby data.
enum DeviceAuthentication {
    enum Result {
        case success, cancelled
        /// The iPhone has no passcode, so there's nothing to ask for.
        case noPasscode
        case failed
    }

    @MainActor
    static func authenticate(reason: String) async -> Result {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.code == LAError.Code.passcodeNotSet.rawValue ? .noPasscode : .failed
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .passcodeNotSet:
                return .noPasscode
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// What the iPhone unlocks with, for the button and the menu.
enum UnlockMethod: Equatable {
    case faceID, touchID, opticID, passcode

    init(_ biometry: LABiometryType) {
        switch biometry {
        case .faceID: self = .faceID
        case .touchID: self = .touchID
        case .opticID: self = .opticID
        case .none: self = .passcode
        @unknown default: self = .passcode
        }
    }

    /// "Face ID", or "passcode" in a sentence. The Apple names stay the same in every language.
    var name: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcode: return String(localized: "passcode", comment: "The iPhone's passcode, in the middle of a sentence")
        }
    }

    /// "Unlock with Face ID", or "Unlock with passcode". Its own sentence for the passcode, which
    /// other languages may say differently from an Apple name.
    var unlockTitle: String {
        switch self {
        case .passcode:
            return String(localized: "Unlock with passcode")
        case .faceID, .touchID, .opticID:
            return String(localized: "Unlock with \(name)", comment: "Face ID, Touch ID or Optic ID")
        }
    }

    /// "Lock with Face ID", or "Lock with passcode".
    var lockTitle: String {
        switch self {
        case .passcode:
            return String(localized: "Lock with passcode")
        case .faceID, .touchID, .opticID:
            return String(localized: "Lock with \(name)", comment: "Face ID, Touch ID or Optic ID")
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .passcode: return "lock.fill"
        }
    }
}

/// Whether the iPhone has a passcode, and the biometrics it can use right now.
struct DeviceSecurity: Equatable {
    var method: UnlockMethod
    var hasPasscode: Bool

    static func current() -> DeviceSecurity {
        var error: NSError?
        let canAuthenticate = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        // Only a missing passcode leaves the page unlocked; any other problem keeps it locked.
        let hasPasscode = canAuthenticate || error?.code != LAError.Code.passcodeNotSet.rawValue

        // `biometryType` is only filled in after `canEvaluatePolicy`. Biometrics that aren't set up
        // or are locked out mean the passcode, so the button says that.
        let biometrics = LAContext()
        let biometricsReady = biometrics.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let method = biometricsReady ? UnlockMethod(biometrics.biometryType) : .passcode
        return DeviceSecurity(method: method, hasPasscode: hasPasscode)
    }
}

// MARK: - Pieces

/// A blur with a lock over the whole view. While the screen is recorded or mirrored it's opaque
/// and says why, since a blur could still show shapes.
struct PrivacyCurtain: View {
    var isCaptured = false

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        ZStack {
            if isCaptured {
                Rectangle()
                    .fill(Palette.screenBackground)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            VStack(spacing: Spacing.m) {
                Image(systemName: isCaptured ? "eye.slash.fill" : "lock.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
                if isCaptured {
                    Text("Hidden while your screen is recorded or shared")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCaptured ? "Hidden while your screen is recorded or shared" : "Hidden while MyBaby isn't open")
    }
}

// MARK: - Telling a pushed screen from leaving

/// Finds the navigation stack entry a view is in, so the lock can tell a screen its page pushed
/// (still the private page) from the parent leaving it (another tab, or back).
///
/// SwiftUI's `NavigationStack` keeps each screen in a `UINavigationController`. When this can't be
/// told, the answer is nil and the lock locks.
@MainActor
final class NavigationEntryProbe {
    weak var view: UIView?

    /// True when a screen pushed after this one is on top of it, false when it isn't, nil when unknown.
    var isCoveredByPushedScreen: Bool? {
        guard let entry = entry,
              let navigation = entry.parent as? UINavigationController,
              let index = navigation.viewControllers.firstIndex(where: { $0 === entry })
        else { return nil }
        return index < navigation.viewControllers.count - 1
    }

    /// The view controller holding the view that sits directly in a navigation controller.
    private var entry: UIViewController? {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) {
            responder = current.next
        }
        var controller = responder as? UIViewController
        while let child = controller, let parent = child.parent {
            if parent is UINavigationController { return child }
            controller = parent
        }
        return nil
    }
}

/// An empty UIKit view behind the page, for `NavigationEntryProbe`.
private struct NavigationEntryReader: UIViewRepresentable {
    let probe: NavigationEntryProbe

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        probe.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        probe.view = uiView
    }
}
