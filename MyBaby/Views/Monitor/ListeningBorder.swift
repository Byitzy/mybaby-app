import SwiftUI
import UIKit

/// A soft border around the whole app while cry alerts are listening, so it's obvious at a glance
/// that the microphone is on. It turns orange and pulses while the baby is crying.
///
/// While it only listens the border stays still: an animation that runs all night keeps the screen
/// redrawing up to 120 times a second, which warms the iPhone and drains the battery. It only
/// pulses during a cry, and stays still then too with Reduce Motion or Low Power Mode.
///
/// Drawn over everything but never takes taps. In 3 AM mode it's dimmer so it doesn't light up a
/// dark room.
struct ListeningBorder: View {
    var isDim = false

    private let monitor = CryMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        if monitor.isListening {
            let crying = monitor.cryStart != nil
            let border = RoundedRectangle(cornerRadius: Self.screenCornerRadius, style: .continuous)
                .strokeBorder(crying ? Palette.cryAlerts : Palette.listening, lineWidth: crying ? 6 : 4)
            let brightest = isDim ? 0.45 : 0.9
            let faintest = isDim ? 0.15 : 0.3

            Group {
                if crying && !reduceMotion && !lowPower {
                    // Only during a cry, which lasts minutes rather than all night.
                    border.phaseAnimator([false, true]) { content, bright in
                        content.opacity(bright ? brightest : faintest)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                    }
                } else {
                    // Drawn once and left alone, so a quiet night costs nothing to show.
                    border.opacity(crying ? brightest : (brightest + faintest) / 2)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    /// The corner radius of this iPhone's screen, so the border follows its rounded corners exactly.
    /// iOS has no public way to ask, so it's looked up by model; iPhones with a Home button have
    /// square corners. A newer model than the table knows gets the latest iPhones' radius.
    private static var screenCornerRadius: CGFloat {
        // An iPad's screen corners are much less rounded than an iPhone's.
        if UIDevice.current.userInterfaceIdiom == .pad {
            return hasRoundedScreen ? 18 : 0
        }
        if let radius = cornerRadii[modelIdentifier] { return radius }
        guard hasRoundedScreen else { return 0 }
        // "iPhone18,1" → 18: models after the table are at least as rounded as the newest in it.
        if modelIdentifier.hasPrefix("iPhone"),
           let major = Int(modelIdentifier.dropFirst(6).prefix { $0.isNumber }), major >= 18 {
            return 62
        }
        return 55
    }

    /// Screens with rounded corners have a Home indicator, and so a bottom safe area.
    private static var hasRoundedScreen: Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return (window?.safeAreaInsets.bottom ?? 0) > 0
    }

    /// "iPhone17,1" for an iPhone 16 Pro. The simulator reports the model it's simulating.
    private static let modelIdentifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    /// Screen corner radii in points, by model.
    private static let cornerRadii: [String: CGFloat] = [
        // X, XS, XS Max, 11 Pro, 11 Pro Max
        "iPhone10,3": 39, "iPhone10,6": 39, "iPhone11,2": 39, "iPhone11,4": 39, "iPhone11,6": 39,
        "iPhone12,3": 39, "iPhone12,5": 39,
        // XR, 11
        "iPhone11,8": 41.5, "iPhone12,1": 41.5,
        // 12 mini, 13 mini
        "iPhone13,1": 44, "iPhone14,4": 44,
        // 12, 12 Pro, 13, 13 Pro, 14, 16e
        "iPhone13,2": 47.33, "iPhone13,3": 47.33, "iPhone14,5": 47.33, "iPhone14,2": 47.33,
        "iPhone14,7": 47.33, "iPhone17,5": 47.33,
        // 12 Pro Max, 13 Pro Max, 14 Plus
        "iPhone13,4": 53.33, "iPhone14,3": 53.33, "iPhone14,8": 53.33,
        // 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus
        "iPhone15,2": 55, "iPhone15,3": 55, "iPhone15,4": 55, "iPhone15,5": 55,
        "iPhone16,1": 55, "iPhone16,2": 55, "iPhone17,3": 55, "iPhone17,4": 55,
        // 16 Pro, 16 Pro Max
        "iPhone17,1": 62, "iPhone17,2": 62,
    ]
}
