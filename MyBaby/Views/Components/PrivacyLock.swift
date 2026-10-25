import LocalAuthentication
import SwiftUI
import UIKit

extension SettingsKey {
    // In `UserDefaults.standard`:
    /// Whether the parent care page asks for Face ID, Touch ID or the passcode before it opens. On by default.
    static let careLockEnabled = "careLockEnabled"
}

/// Shows `content` only after Face ID, Touch ID, Optic ID or the iPhone's passcode, for a private page
/// like the parent care page.
///
/// The content isn't built until the page is unlocked, so nothing in it is fetched or drawn before.
/// The page locks again when the parent leaves it (but not for a screen it opens itself, like
/// My medicines), when the app goes to the background, and when the app comes back after more than
/// two minutes away. While the app isn't active, the page is blurred, so the app switcher's picture
/// doesn't show it.
///
/// It uses `.deviceOwnerAuthentication`: biometrics, with the passcode when they fail or are locked
/// out. An iPhone without a passcode can't lock anything, so the page then shows with a banner saying so.
struct PrivateContentLock<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage private var lockEnabled: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private let title: String
    private let message: String
    private let reason: String
    private let turnOffReason: String
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
    /// When the app stopped being active, for the two-minute relock.
    @State private var inactiveSince: Date?
    @State private var probe = NavigationEntryProbe()

    /// How long the app can be away before the page locks again.
    static var relockInterval: TimeInterval { 2 * 60 }

    init(
        title: String,
        message: String = "Unlock to see your check-ins, medicines and notes.",
        reason: String = "Unlock your private care page",
        turnOffReason: String = "Turn off the lock on your private care page",
        settingKey: String = SettingsKey.careLockEnabled,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.reason = reason
        self.turnOffReason = turnOffReason
        self.content = content
        _lockEnabled = AppStorage(wrappedValue: true, settingKey)
    }

    var body: some View {
        ZStack {
            if mountsContent {
                content()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if lockEnabled && !security.hasPasscode {
                            NoPasscodeBanner()
                        }
                    }
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
        .hiddenInAppSwitcher()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsContent && security.hasPasscode {
                    lockMenu
                }
            }
        }
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
            guard isProtected else { return }
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
    }

    // MARK: State

    /// Locking is on, and this iPhone has a passcode to lock with.
    private var isProtected: Bool { lockEnabled && security.hasPasscode }

    private var showsContent: Bool { !isProtected || isUnlocked }

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
            // The Face ID sheet makes the app inactive too; that time doesn't count as away.
            if !isAuthenticating && inactiveSince == nil {
                inactiveSince = .now
            }
        case .active:
            if let inactiveSince, Date.now.timeIntervalSince(inactiveSince) > Self.relockInterval {
                relock(keepingContent: false)
                pendingAutoUnlock = true
            }
            inactiveSince = nil
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
        guard isProtected, !isUnlocked, !isAuthenticating else { return }
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
            // Nothing to lock with: the content shows, with the banner.
            security.hasPasscode = false
        case .failed:
            unlockError = "Couldn't unlock. Try again."
        }
    }

    @MainActor
    private func turnOffLock() async {
        switch await authenticate(reason: turnOffReason) {
        case .success:
            lockEnabled = false
        case .noPasscode:
            security.hasPasscode = false
        case .cancelled, .failed:
            break
        }
    }

    private enum AuthenticationResult {
        case success, cancelled, noPasscode, failed
    }

    /// Face ID, Touch ID or Optic ID, falling back to the passcode (also when biometrics are locked out).
    @MainActor
    private func authenticate(reason: String) async -> AuthenticationResult {
        guard !isAuthenticating else { return .cancelled }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.code == LAError.Code.passcodeNotSet.rawValue ? .noPasscode : .failed
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
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
                        Text(title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    Button {
                        Task { await unlock() }
                    } label: {
                        Label(security.method.unlockTitle, systemImage: security.method.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isAuthenticating)

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

    private var lockMenu: some View {
        Menu {
            Toggle(isOn: lockToggle) {
                Label(security.method.lockTitle, systemImage: security.method.systemImage)
            }
        } label: {
            Label("Page lock", systemImage: lockEnabled ? "lock.fill" : "lock.open")
        }
        .accessibilityLabel("Page lock")
        .accessibilityValue(lockEnabled ? "On" : "Off")
        .accessibilityHint("Turns asking for \(security.method.name) on or off for this page.")
    }

    /// Turning the lock off asks for Face ID (or the passcode) first; turning it on doesn't, and
    /// leaves the page open until it next locks.
    private var lockToggle: Binding<Bool> {
        Binding(
            get: { lockEnabled },
            set: { turnOn in
                if turnOn {
                    lockEnabled = true
                    isUnlocked = true
                    keepsContent = true
                } else {
                    Task { await turnOffLock() }
                }
            }
        )
    }
}

// MARK: - Device

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

    var name: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .passcode: return "passcode"
        }
    }

    /// "Unlock with Face ID", or "Unlock with passcode".
    var unlockTitle: String { "Unlock with \(name)" }

    /// "Lock with Face ID", or "Lock with passcode".
    var lockTitle: String { "Lock with \(name)" }

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

/// At the top of the page when it can't be locked, so the parent knows it's open.
private struct NoPasscodeBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            NoticeLabel("Not locked: this iPhone has no passcode", systemImage: "lock.open.fill")
                .font(.subheadline.weight(.semibold))
            Text("Set a passcode on this iPhone to lock this page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// A blur with a lock over the whole view.
struct PrivacyCurtain: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hidden while MyBaby isn't open")
    }
}

private struct AppSwitcherCurtain: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if scenePhase != .active {
                    PrivacyCurtain()
                }
            }
    }
}

extension View {
    /// Blurs the view while the app isn't active, so the app switcher's picture of it doesn't show
    /// what's on it. For private screens, like those the care page pushes.
    func hiddenInAppSwitcher() -> some View {
        modifier(AppSwitcherCurtain())
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
