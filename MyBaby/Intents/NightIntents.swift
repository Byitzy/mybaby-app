import AppIntents
import UIKit

// Siri and Shortcuts at night: cry alerts on a parent's phone, and white noise on the nursery monitor.
//
// iPhone only lets the microphone start while the app is on screen, and both of these (re)start the audio
// engine that listens through it. So when MyBaby is in the background they ask to continue in MyBaby
// (`ForegroundContinuableIntent`, iOS 16.4+), which opens it and carries on there. Stopping cry alerts
// only stops the engine, so that one runs in the background.

/// Start or stop, for "Start cry alerts in MyBaby" and "Stop listening in MyBaby". The synonyms are
/// other words Siri understands.
enum NightAction: String, CaseIterable, AppEnum {
    case start, stop

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Start or Stop"
    static var caseDisplayRepresentations: [NightAction: DisplayRepresentation] = [
        .start: DisplayRepresentation(title: "Start", synonyms: ["turn on", "switch on", "begin"]),
        .stop: DisplayRepresentation(title: "Stop", synonyms: ["turn off", "switch off", "end"]),
    ]
}

/// "Start cry alerts in MyBaby" / "Stop listening in MyBaby": the same as Cry alerts › Start listening
/// in the app, with the same settings (sensitivity, who's on duty).
struct CryAlertsIntent: ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "Start or Stop Cry Alerts"
    static var description = IntentDescription(
        "Starts listening for your baby crying, so the parent on duty is buzzed, or stops listening. Starting opens MyBaby, because iPhone only lets the microphone start while the app is on screen. Audio is analyzed on this iPhone and never recorded."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Start or Stop", default: .start)
    var action: NightAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) cry alerts")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let monitor = CryMonitor.shared
        let nursery = NurseryMonitor.shared
        switch action {
        case .stop:
            guard monitor.isListening else {
                return .result(dialog: "Cry alerts are already off.")
            }
            if nursery.isActive {
                // This device is the nursery monitor: stop it the way its Stop monitor button does.
                nursery.stop()
                return .result(dialog: "The nursery monitor stopped listening.")
            }
            monitor.stop()
            return .result(dialog: "Stopped listening. Cry alerts are off.")

        case .start:
            if monitor.isListening {
                return .result(dialog: "Cry alerts are already listening.")
            }
            if UIApplication.shared.applicationState == .active {
                await Self.startListening()
            } else {
                try await requestToContinueInForeground(
                    IntentDialog("Cry alerts need MyBaby on screen to turn on the microphone.")
                ) {
                    await Self.startListening()
                }
            }
            guard monitor.isListening else { throw IntentFailure.cryAlertsDidNotStart }
            if nursery.isActive {
                return .result(dialog: "The nursery monitor is listening again.")
            }
            return .result(dialog: "Listening for crying. Keep your iPhone near the baby, and plugged in.")
        }
    }

    /// Like Start listening in the app. On a nursery monitor whose listening stopped by itself, like its
    /// Start again button, so it keeps sending alerts to the parents' phones.
    @MainActor
    private static func startListening() async {
        if NurseryMonitor.shared.isActive {
            await NurseryMonitor.shared.startAgain()
        } else {
            await CryMonitor.shared.start()
        }
    }
}

// MARK: - White noise

/// The sound for "Start white noise", without `NoiseColor.off`, which is what stopping is for.
enum NoiseChoice: String, CaseIterable, AppEnum {
    case white, pink, brown

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sound"
    static var caseDisplayRepresentations: [NoiseChoice: DisplayRepresentation] = [
        .white: DisplayRepresentation(title: "White noise", subtitle: "A bright hiss, like a radio between stations."),
        .pink: DisplayRepresentation(title: "Pink noise", subtitle: "Softer, like steady rain."),
        .brown: DisplayRepresentation(title: "Brown noise", subtitle: "Deep and low, like a distant waterfall."),
    ]

    var color: NoiseColor {
        switch self {
        case .white: return .white
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

/// "Start white noise" / "Stop white noise", on the device that's the nursery monitor, where white noise
/// plays (`WhiteNoise`, through the monitor's audio engine). It plays at the volume and with the sleep
/// timer set on the monitor's screen.
///
/// In Shortcuts and Spotlight only: MyBaby's 10 Siri phrases are taken (see MyBabyShortcuts.swift). Add it
/// to Siri from the Shortcuts app ("Add to Siri") to say it.
struct WhiteNoiseIntent: ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "Start or Stop White Noise"
    static var description = IntentDescription(
        "Plays white, pink or brown noise on the nursery monitor, or stops it. Run it on the iPhone or iPad that's the nursery monitor; it plays at the volume set there."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Start or Stop", default: .start)
    var action: NightAction

    @Parameter(title: "Sound", description: "White noise, unless you choose another.")
    var sound: NoiseChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) white noise") {
            \.$sound
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let noise = WhiteNoise.shared
        guard NurseryMonitor.shared.isActive, CryMonitor.shared.isListening else {
            return .result(dialog: "White noise plays on the nursery monitor. On the device by the crib, go to Cry alerts and use it as the baby monitor first.")
        }
        // Changing the noise restarts the monitor's audio engine, which needs MyBaby on screen.
        let target: NoiseColor = action == .start ? (sound?.color ?? .white) : .off
        if target == noise.color {
            if action == .stop {
                return .result(dialog: "White noise is already off.")
            }
            return .result(dialog: "That's already playing.")
        }
        if UIApplication.shared.applicationState == .active {
            noise.setColor(target)
        } else {
            try await requestToContinueInForeground(
                IntentDialog("White noise needs MyBaby on screen on the monitor.")
            ) {
                WhiteNoise.shared.setColor(target)
            }
        }
        if action == .stop {
            return .result(dialog: "White noise is off.")
        }
        return .result(dialog: "Playing \(target.title.lowercased()) noise. Keep the monitor quiet, and at least 7 feet from the crib.")
    }
}
