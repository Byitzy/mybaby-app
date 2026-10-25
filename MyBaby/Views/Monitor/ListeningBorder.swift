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

    /// Roughly the corner radius of the screen, so the border follows its rounded corners.
    /// iPhones with a Home button have square corners.
    private static var screenCornerRadius: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        let hasRoundedScreen = (window?.safeAreaInsets.bottom ?? 0) > 0
        return hasRoundedScreen ? 52 : 0
    }
}
