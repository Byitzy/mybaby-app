import SwiftUI
import UIKit

extension Palette {
    /// The nursery monitor's dark screen.
    static let monitorBackground = Color.black
    /// The night light: a warm, dim amber glow.
    static let nightLight = Color(red: 1.0, green: 0.55, blue: 0.2)
}

extension View {
    /// Shows the nursery monitor full screen while this device is the baby monitor. On the root view, so it
    /// stays up while the screens behind it are rebuilt (a new day, another baby).
    func nurseryMonitorCover() -> some View {
        modifier(NurseryMonitorCover())
    }
}

private struct NurseryMonitorCover: ViewModifier {
    private let monitor = NurseryMonitor.shared

    func body(content: Content) -> some View {
        let isActive = monitor.isActive
        content.fullScreenCover(isPresented: Binding(get: { isActive }, set: { _ in })) {
            MonitorView()
        }
    }
}

/// The spare device's screen while it's the nursery monitor: dark and dim, with what it hears, who's on
/// duty, white noise and a night light. The screen stays on (and dim) while it's open; nothing else in
/// MyBaby keeps the screen awake.
struct MonitorView: View {
    @AppStorage(SettingsKey.nightPlan, store: .shared) private var nightPlanData = Data()
    @AppStorage("monitorNightLight") private var nightLight = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var emojiSize: CGFloat = 64

    private let monitor = NurseryMonitor.shared
    private let cryMonitor = CryMonitor.shared
    private let noise = WhiteNoise.shared
    private let alerts = RemoteCryAlerts.shared

    @State private var confirmingStop = false
    @State private var testResult: String?
    @State private var isSendingTest = false
    @State private var isPluggedIn = true
    /// The brightness before the monitor dimmed the screen, put back when it closes.
    @State private var savedBrightness: CGFloat?
    /// The screen's size, for the iPad layouts and so the night light's glow reaches every corner.
    @State private var screenSize: CGSize = .zero

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if isLargeScreen && screenSize.width > screenSize.height {
                landscapeLayout
            } else {
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        status
                            .padding(.top, Spacing.xl)
                            // On an iPad standing up, the clock and status fill the top of the screen.
                            .frame(minHeight: isLargeScreen ? screenSize.height * 0.45 : nil)
                        noiseControls
                        nightLightControl
                        tips
                        buttons
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            screenSize = size
        }
        .foregroundStyle(.white.opacity(0.85))
        .tint(Palette.nightLight)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("Stop the monitor?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop monitor", role: .destructive) { monitor.stop() }
        } message: {
            Text("The parents' phones won't get alerts from this device until you start it again.")
        }
        .onAppear(perform: appeared)
        .onDisappear(perform: disappeared)
        .onChange(of: nightLight) { _, _ in applyBrightness() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { applyBrightness() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateBattery()
        }
    }

    // MARK: iPad

    /// An iPad (regular width and height, whichever way it's turned) gets a big clock, and in
    /// landscape the controls move beside the status. iPhones keep the one-column screen.
    private var isLargeScreen: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    /// iPad on its side: the clock and status centered on the left, the controls in a column on the right.
    private var landscapeLayout: some View {
        HStack(spacing: Spacing.xl) {
            // Centered in the screen's height, and scrolls if the largest text sizes make it taller.
            ScrollView {
                status
                    .frame(maxWidth: .infinity, minHeight: screenSize.height)
            }
            .scrollIndicators(.hidden)
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    noiseControls
                    nightLightControl
                    tips
                    buttons
                }
                .padding(.vertical, Spacing.xl)
                .frame(minHeight: screenSize.height)
            }
            .scrollIndicators(.hidden)
            .frame(width: min(420, screenSize.width * 0.4))
        }
        .padding(.horizontal, Spacing.xl)
    }

    /// The time, large and dim, readable across a dark nursery.
    private func clock(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: 140, weight: .thin, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: Status

    private var plan: NightPlan { NightPlan(data: nightPlanData) }

    private var status: some View {
        // Redrawn each minute so VoiceOver reads how long the crying has gone on in words.
        TimelineView(.everyMinute) { timeline in
            VStack(spacing: Spacing.m) {
                if isLargeScreen {
                    clock(timeline.date)
                }
                Text(cryMonitor.cryStart != nil ? "😭" : (cryMonitor.isListening ? "🎧" : "⏸️"))
                    .font(.system(size: min(emojiSize, 120)))
                    .accessibilityHidden(true)
                statusTitle
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(cryMonitor.cryStart != nil ? 1 : 0.85))
                Text(onDutyText(at: timeline.date))
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if let action = cryMonitor.lastAction {
                    Text(action)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if alerts.waitingCount > 0 {
                    Text(alerts.waitingCount == 1 ? "1 alert is waiting for the network." : "\(alerts.waitingCount) alerts are waiting for the network.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let problem = monitor.problem {
                    VStack(spacing: Spacing.s) {
                        NoticeLabel(problem, systemImage: "exclamationmark.circle.fill", tint: Palette.danger)
                        Button("Start again") {
                            Task { await monitor.startAgain() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenStatus(now: timeline.date))
        }
    }

    /// "Listening for Noah", or "Noah is crying · 1:20" with a running clock.
    @ViewBuilder
    private var statusTitle: some View {
        if let cryStart = cryMonitor.cryStart {
            Text("\(monitor.babyName) is crying · \(Text(cryStart, style: .timer))")
                .monospacedDigit()
        } else if cryMonitor.isListening {
            Text("Listening for \(monitor.babyName)")
        } else {
            Text("Not listening")
        }
    }

    private func spokenStatus(now: Date) -> String {
        var parts: [String] = []
        let name = monitor.babyName
        if let cryStart = cryMonitor.cryStart {
            let duration = Format.spokenDuration(now.timeIntervalSince(cryStart))
            parts.append(String(localized: "\(name) is crying, for \(duration)", comment: "Read by VoiceOver: the baby's name, then how long, like \"3 minutes\""))
        } else {
            parts.append(cryMonitor.isListening ? String(localized: "Listening for \(name)", comment: "The baby's name") : String(localized: "Not listening"))
        }
        parts.append(onDutyText(at: now))
        if let action = cryMonitor.lastAction { parts.append(action) }
        return parts.joined(separator: ". ")
    }

    private func onDutyText(at date: Date) -> String {
        guard let shift = plan.shift(at: date) else {
            return String(localized: "No night shift now, so alerts go to every parent.")
        }
        let name = plan.name(of: shift.parent)
        let end = shift.end.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(name) is on duty until \(end).", comment: "A parent's name, then a time")
    }

    // MARK: White noise

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("White noise")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("White noise", selection: Binding(get: { noise.color }, set: { noise.setColor($0) })) {
                ForEach(NoiseColor.allCases) { color in
                    Text(color.title).tag(color)
                }
            }
            .pickerStyle(.segmented)
            Text(noise.color.detail)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))

            if noise.isPlaying {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "speaker.fill")
                        .accessibilityHidden(true)
                    Slider(value: Binding(get: { noise.volume }, set: { noise.setVolume($0) }), in: 0...1)
                        .accessibilityLabel("White noise volume")
                        .accessibilityValue("\(Int((noise.volume * 100).rounded())) percent of the most it plays")
                    Image(systemName: "speaker.wave.2.fill")
                        .accessibilityHidden(true)
                }
                Picker("Turn off after", selection: Binding(get: { noise.timer }, set: { noise.setTimer($0) })) {
                    ForEach(NoiseTimer.allCases) { timer in
                        Text(timer.title).tag(timer)
                    }
                }
                .pickerStyle(.menu)
                if let stopsAt = noise.stopsAt {
                    Text("Turns off at \(stopsAt.formatted(date: .omitted, time: .shortened)).")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text("Keep the device at least 7 feet (2 m) from the crib, and the volume low. Its volume buttons change it too. The monitor takes its own noise out of what it hears, so crying still gets through.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(Spacing.l)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    // MARK: Night light

    private var nightLightControl: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Night light")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("Night light", selection: $nightLight) {
                Text("Off").tag(false)
                Text("Warm glow").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(Spacing.l)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    @ViewBuilder
    private var background: some View {
        if nightLight {
            RadialGradient(
                colors: [Palette.nightLight.opacity(0.55), Palette.nightLight.opacity(0.18), Palette.monitorBackground],
                center: .center,
                startRadius: 20,
                endRadius: glowRadius
            )
        } else {
            Palette.monitorBackground
        }
    }

    /// 600 points, as on iPhone, or out to the corners of a bigger screen, so on an iPad the warm
    /// glow fills the whole screen rather than a circle in the middle of it.
    private var glowRadius: CGFloat {
        max(600, (screenSize.width * screenSize.width + screenSize.height * screenSize.height).squareRoot() / 2)
    }

    // MARK: Tips and buttons

    private var tips: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if !isPluggedIn {
                NoticeLabel("This device isn't plugged in. Listening all night needs power.", systemImage: "battery.25")
            }
            Label("Keep this device plugged in, on Wi-Fi, with MyBaby open.", systemImage: "powerplug")
            Label("This helps you rest. It isn't a medical or safety monitor.", systemImage: "info.circle")
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        VStack(spacing: Spacing.m) {
            Button {
                isSendingTest = true
                Task {
                    testResult = await monitor.sendTest()
                    isSendingTest = false
                }
            } label: {
                Label(isSendingTest ? "Sending…" : "Test alert", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSendingTest)
            if let testResult {
                Text(testResult)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Button(role: .destructive) {
                confirmingStop = true
            } label: {
                Label("Stop monitor", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.danger.opacity(0.7))
        }
    }

    // MARK: Screen

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private func appeared() {
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBattery()
        if savedBrightness == nil { savedBrightness = screen?.brightness }
        applyBrightness()
    }

    private func disappeared() {
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isBatteryMonitoringEnabled = false
        if let savedBrightness {
            screen?.brightness = savedBrightness
            self.savedBrightness = nil
        }
    }

    /// Dim, but a little brighter with the night light on, so it glows.
    private func applyBrightness() {
        screen?.brightness = nightLight ? 0.3 : 0.05
    }

    private func updateBattery() {
        let state = UIDevice.current.batteryState
        // Simulators and some iPads report unknown; don't nag then.
        isPluggedIn = state != .unplugged
    }
}

#Preview {
    MonitorView()
}
