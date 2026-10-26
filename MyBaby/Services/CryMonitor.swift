import AVFoundation
import Observation
import SoundAnalysis
import UIKit

/// One stretch of crying that the monitor heard.
struct CryEpisode: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Listens through the microphone for a baby crying and buzzes the parent on duty.
///
/// Audio is analyzed on the device with Apple's built-in sound classifier. Nothing is recorded or saved.
/// Each phone decides on its own whether to buzz, based on the night plan and who the phone belongs to,
/// so when both parents' phones are listening in the same room, only the right one goes off.
///
/// Detection has two stages, to sip battery all night: a cheap loudness gate looks at every buffer, and
/// only a sound clearly louder than the room wakes the classifier for a few seconds (see `CryGate`).
///
/// On a spare device left by the baby (`Mode.monitorDevice`, see `NurseryMonitor`), it never buzzes
/// itself and sends the alerts to the parents' phones instead (`RemoteCryAlerts`), and it can play
/// white noise through the same audio engine (`WhiteNoise`).
///
/// On a parent's phone, listening also shows outside the app (`listeningSummary`): a mic badge on the
/// widgets, and a Live Activity on the Lock Screen and in the Dynamic Island with a Stop button.
@MainActor
@Observable
final class CryMonitor {
    static let shared = CryMonitor()

    /// Where alerts go.
    enum Mode {
        /// A parent's phone: it buzzes itself when its owner is on duty.
        case phone
        /// A spare device by the crib: nobody is next to it, so alerts go to the parents' phones.
        case monitorDevice
    }

    private(set) var isListening = false
    private(set) var mode: Mode = .phone
    /// When the crying going on now started, or `nil` when it's quiet.
    private(set) var cryStart: Date?
    /// Latest crying confidence from the classifier, 0–1. Only kept up to date while a screen that shows
    /// it is open and the app is in front (see `meterAppeared`), and at most once a second.
    private(set) var level: Double = 0
    private(set) var episodes: [CryEpisode] = []
    private(set) var stopsAt: Date?
    private(set) var errorMessage: String?
    /// What the last alert decision was, e.g. "Buzzed Sam" or "Sam is on duty, so this phone stayed quiet".
    private(set) var lastAction: String?
    /// Whether the sound classifier is running right now, rather than only the loudness gate. For debugging.
    private(set) var isClassifierActive = false
    /// In Low Power Mode the gate is a little less eager and a cry takes a little longer to count as over.
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Counted in debug builds only (see `CryGateMetrics`), as of the last time the classifier started or stopped.
    private(set) var debugMetrics = CryGateMetrics()
    private(set) var listeningSince: Date?
    /// Stops listening at `stopsAt` (see `updateStopTime`).
    @ObservationIgnored private var stopTimer: Task<Void, Never>?
    /// What the widgets and the Live Activity were last told (`publishListening`).
    @ObservationIgnored private var publishedSummary: WidgetSnapshot.Listening?

    /// Each classifier result covers 1.5 s of audio and the next one starts 1.125 s later (overlap 0.25),
    /// so results come a little under once a second, about half as often as with the default window.
    private static let classifierWindow: Double = 1.5
    private static let classifierOverlap: Double = 0.25
    /// A cry is 2 of the last 3 results: about 2.6 s of crying (one 1.5 s window and one step).
    private static let windowSize = 3
    private static let cryVotesNeeded = 2
    /// How long it must be quiet before a cry counts as over. A little longer in Low Power Mode.
    private static let quietToEnd: TimeInterval = 45
    private static let lowPowerQuietToEnd: TimeInterval = 60
    /// How often to buzz again while the crying goes on.
    private static let repeatAlertAfter: TimeInterval = 60
    /// From a monitor device, "still crying" goes to the parents' phones at most every 2 minutes.
    private static let remoteRepeatAlertAfter: TimeInterval = 120
    /// The tap hands over about a fifth of a second of audio at a time.
    private static let tapSeconds: Double = 0.2
    /// The level meter changes at most this often.
    private static let meterInterval: TimeInterval = 1

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "MyBaby.cry-analysis")
    @ObservationIgnored private var gate: CryGate?
    @ObservationIgnored private var observer: CryResultsObserver?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var isReconfiguring = false
    @ObservationIgnored private var recentVotes: [Bool] = []
    @ObservationIgnored private var lastHeard: Date?
    @ObservationIgnored private var lastAlert: Date?
    @ObservationIgnored private var escalated = false
    /// How many screens showing the level meter are open.
    @ObservationIgnored private var meterViewers = 0
    @ObservationIgnored private var lastMeterUpdate = Date.distantPast

    private init() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.powerStateChanged() }
        }
    }

    // MARK: Start & stop

    func start(mode: Mode = .phone) async {
        // A second tap while waiting for microphone permission must not install a second tap.
        guard !isListening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        setError(nil)

        guard await AVAudioApplication.requestRecordPermission() else {
            setError(String(localized: "MyBaby needs the microphone to hear crying. Allow it in Settings › MyBaby."))
            return
        }
        if self.mode != mode { self.mode = mode }

        do {
            let plan = NightPlan.load()
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = Self.windowDuration(for: request)
            request.overlapFactor = Self.classifierOverlap
            let cryLabels = request.knownClassifications.filter { $0.contains("cry") }

            let gate = try CryGate(
                tuning: .make(sensitivity: plan.crySensitivity, lowPower: isLowPowerMode),
                onChange: Self.gateHandler(for: self)
            )
            let observer = CryResultsObserver(labels: cryLabels, monitor: self, gate: gate, queue: analysisQueue)
            try gate.analyzer.add(request, withObserver: observer)
            self.gate = gate
            self.observer = observer

            try configureAudio()

            resetEpisode()
            isListening = true
            setLastAction(nil)
            listeningSince = .now
            debugMetrics = CryGateMetrics()
            // A monitor by the crib listens until it's stopped, for naps too.
            updateStopTime()
            observeInterruptions()
        } catch {
            stop()
            if CallWatcher.shared.isOnCall {
                // The call has the microphone. Start by itself once it's over, as asked.
                setError(String(localized: "MyBaby can't listen during a phone or FaceTime call. It starts listening by itself when the call ends."))
                let startMode = mode
                CallWatcher.shared.afterCallsEnd {
                    Task { @MainActor in
                        // A moment for iOS to hand the microphone back.
                        try? await Task.sleep(for: .seconds(1))
                        await CryMonitor.shared.start(mode: startMode)
                    }
                }
            } else {
                setError(String(localized: "Couldn't start listening: \(error.localizedDescription)", comment: "The argument is the system's reason"))
            }
        }
    }

    func stop() {
        // Stopped by hand: no starting by itself after a call either.
        CallWatcher.shared.cancel()
        let wasMonitor = isListening && mode == .monitorDevice
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        WhiteNoise.shared.detach()
        // The analyzer isn't thread-safe, so tear it down on the queue that feeds it.
        if let gate {
            analysisQueue.async { gate.tearDown() }
        }
        gate = nil
        observer = nil
        for observer in [interruptionObserver, configurationObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        interruptionObserver = nil
        configurationObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        finishEpisode()
        if isListening { isListening = false }
        if isClassifierActive { isClassifierActive = false }
        if level != 0 { level = 0 }
        if stopsAt != nil { stopsAt = nil }
        stopTimer?.cancel()
        stopTimer = nil
        publishListening()
        if wasMonitor {
            NurseryMonitor.shared.cryMonitorDidStop()
        }
    }

    /// The Stop button on the listening Live Activity (`StopListeningIntent`): the same as Stop
    /// listening in the app. Only on a parent's phone; a nursery monitor never shows the activity and
    /// stops from its own screen, which asks first. Also ends an activity left behind by an earlier
    /// run of the app, which this may have been launched for.
    func stopFromLiveActivity() {
        if isListening, mode == .phone {
            stop()
            setLastAction(String(localized: "Stopped listening from the Live Activity.", comment: "Cry alerts: listening was stopped with the Stop button on the Lock Screen or in the Dynamic Island"))
        }
        LiveActivities.syncListening(listeningSummary)
        WidgetSnapshotWriter.shared.listeningChanged(immediately: true)
    }

    /// iOS is closing MyBaby, e.g. it was swiped away in the app switcher while listening: stop, so the
    /// widgets stop saying "Listening", and end the Live Activity before the app is gone. iOS doesn't
    /// always say so first (it may just stop the app); then the next launch tidies up instead.
    func appWillTerminate() {
        if isListening { stop() }
        LiveActivities.endListeningBeforeExit()
    }

    // MARK: Outside the app

    /// What the widgets and the Live Activity show: listening on this iPhone, since when, until when, and
    /// whether crying is heard now. `nil` when not listening, and on a nursery monitor, which has its own
    /// full-screen view (see `LiveActivities.syncListening`).
    var listeningSummary: WidgetSnapshot.Listening? {
        guard isListening, mode == .phone, let listeningSince else { return nil }
        return WidgetSnapshot.Listening(since: listeningSince, cryingSince: cryStart, stopsAt: stopsAt)
    }

    /// Tells the Live Activity and the widgets about a change in `listeningSummary`, if there is one.
    /// The Live Activity is updated at once, also in the background; the widgets at once when
    /// listening starts, stops or gets a new stop time, and at most once a minute for a cry.
    private func publishListening() {
        let summary = listeningSummary
        guard summary != publishedSummary else { return }
        let onlyCryChanged = summary != nil && publishedSummary != nil
            && summary?.since == publishedSummary?.since && summary?.stopsAt == publishedSummary?.stopsAt
        publishedSummary = summary
        LiveActivities.syncListening(summary)
        WidgetSnapshotWriter.shared.listeningChanged(immediately: !onlyCryChanged)
    }

    /// Forgets the cry episodes and messages the Cry alerts screen shows, after Delete all MyBaby data.
    /// Only while not listening.
    func forgetEpisodes() {
        guard !isListening else { return }
        if !episodes.isEmpty { episodes = [] }
        setLastAction(nil)
        setError(nil)
    }

    /// White noise started or stopped on the monitor device: voice processing (echo cancellation) is only
    /// worth its extra processing while the device plays something, and can only be switched while the
    /// engine is stopped. Carries on with the same cry, if there is one.
    func whiteNoiseChanged() {
        guard isListening, mode == .monitorDevice else { return }
        restartAudio(failure: String(localized: "Listening stopped while changing the white noise. Start the monitor again."))
    }

    // MARK: The level meter

    /// Screens that show the level call these when they appear and disappear, so it isn't updated for nobody.
    func meterAppeared() {
        meterViewers += 1
    }

    func meterDisappeared() {
        meterViewers = max(0, meterViewers - 1)
    }

    private func updateMeter(_ value: Double) {
        guard meterViewers > 0, UIApplication.shared.applicationState == .active else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastMeterUpdate) >= Self.meterInterval else { return }
        lastMeterUpdate = now
        if level != value { level = value }
    }

    // MARK: Results

    fileprivate func handle(confidence: Double) {
        guard isListening else { return }
        let now = Date.now
        if let stopsAt, now >= stopsAt {
            stop()
            setLastAction(String(localized: "Stopped listening at the time you chose."))
            return
        }

        let plan = NightPlan.load()
        updateMeter(confidence)
        recentVotes.append(confidence >= plan.crySensitivity.threshold)
        if recentVotes.count > Self.windowSize { recentVotes.removeFirst() }
        let hearingCry = recentVotes.filter { $0 }.count >= Self.cryVotesNeeded

        if hearingCry {
            lastHeard = now
            if cryStart == nil {
                cryStart = now
                setGateEpisode(true)
                publishListening()
                alertOnDutyParent(plan: plan, isRepeat: false)
            } else if let lastAlert, now.timeIntervalSince(lastAlert) >= repeatInterval {
                alertOnDutyParent(plan: plan, isRepeat: true)
            }
            if let cryStart, !escalated, plan.cryEscalationMinutes > 0,
               now.timeIntervalSince(cryStart) >= Double(plan.cryEscalationMinutes) * 60 {
                escalated = true
                alertOffDutyParent(plan: plan, cryingFor: now.timeIntervalSince(cryStart))
            }
        } else if let lastHeard, now.timeIntervalSince(lastHeard) > quietToEnd {
            finishEpisode()
            publishListening()
        }
    }

    /// The gate woke the classifier, or let it sleep again.
    fileprivate func classifierChanged(_ active: Bool, metrics: CryGateMetrics) {
        guard isListening else { return }
        if isClassifierActive != active { isClassifierActive = active }
        #if DEBUG
        if debugMetrics != metrics { debugMetrics = metrics }
        #endif
        if !active {
            // The next time it wakes, it starts counting votes afresh.
            recentVotes.removeAll()
            if level != 0 { level = 0 }
        }
    }

    // MARK: Alerts

    /// Buzzes this phone if it belongs to whoever is on duty (or to both parents, or there's no shift now).
    private func alertOnDutyParent(plan: NightPlan, isRepeat: Bool) {
        if mode == .monitorDevice {
            lastAlert = .now
            sendRemote(isRepeat ? .stillCrying : .cry, to: .onDuty)
            return
        }
        let onDuty = plan.shift(at: .now)?.parent
        if let onDuty, !plan.alarmOwner.includes(onDuty) {
            setLastAction(String(localized: "\(plan.name(of: onDuty)) is on duty, so this phone stayed quiet."))
            return
        }
        lastAlert = .now
        let title = onDuty.map { String(localized: "👶 Baby is crying. Your turn, \(plan.name(of: $0))", comment: "Cry alert title; the argument is the parent on duty") }
            ?? String(localized: "👶 Baby is crying")
        let body = isRepeat
            ? String(localized: "Still crying.", comment: "Cry alert body: the baby is still crying")
            : String(localized: "Heard just now.", comment: "Cry alert body: the crying was heard a moment ago")
        buzz(title: title, body: body, plan: plan)
        setLastAction(onDuty.map { String(localized: "Buzzed \(plan.name(of: $0)).", comment: "A cry alert went to this parent's phone") }
            ?? String(localized: "Buzzed this phone.", comment: "A cry alert went to this phone"))
    }

    /// Buzzes the parent who's off duty when the crying has gone on too long.
    private func alertOffDutyParent(plan: NightPlan, cryingFor duration: TimeInterval) {
        guard let onDuty = plan.shift(at: .now)?.parent else { return }
        if mode == .monitorDevice {
            sendRemote(.stillCrying, to: .offDuty)
            return
        }
        let offDuty = onDuty.other
        guard plan.alarmOwner.includes(offDuty) else { return }
        let length = Format.duration(duration)
        buzz(
            title: String(localized: "👶 Baby's still crying"),
            body: String(localized: "It's been \(length). \(plan.name(of: onDuty)) may not have heard.", comment: "Cry alert: how long the crying has gone on, then the parent on duty"),
            plan: plan
        )
        setLastAction(String(localized: "Crying went on for \(length), so this phone buzzed \(plan.name(of: offDuty)) too.", comment: "How long the crying went on, then the parent who was off duty"))
    }

    /// Sent as a notification so iOS picks where it lands: a tap on the Apple Watch when it's on your
    /// wrist and the phone is locked, otherwise the iPhone. Vibrating the phone directly would
    /// buzz it even while the watch is being worn.
    private func buzz(title: String, body: String, plan: NightPlan) {
        NotificationManager.sendCryAlert(title: title, body: body, style: plan.alarmStyle)
    }

    /// From a monitor device, the alert goes to the parents' phones through their private inboxes.
    private func sendRemote(_ kind: CryAlertKind, to audience: CryAlertAudience) {
        let crying = cryStart.map { Date.now.timeIntervalSince($0) } ?? 0
        Task {
            let summary = await RemoteCryAlerts.shared.send(kind, crySeconds: crying, to: audience)
            setLastAction(summary)
        }
    }

    // MARK: Audio

    /// Sets up the audio session and the engine for the current mode, and starts it. Also used after a
    /// route change and when white noise starts or stops, without ending the cry episode.
    private func configureAudio() throws {
        guard let gate else { return }
        let playsNoise = mode == .monitorDevice && WhiteNoise.shared.isPlaying
        let session = AVAudioSession.sharedInstance()
        if playsNoise {
            // White noise comes out of the speaker. `.default` rather than `.measurement`, which asks iOS
            // not to process the signal and works against voice processing.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        } else {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        }
        // Little audio, in big chunks: 16 kHz, a tenth of a second at a time. iOS may not grant either
        // (voice processing usually runs at 24 or 48 kHz), so the gate converts what it gets.
        try? session.setPreferredSampleRate(CryGate.sampleRate)
        try? session.setPreferredIOBufferDuration(0.1)
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        try configureVoiceProcessing(playsNoise)
        if playsNoise {
            WhiteNoise.shared.attach(to: engine)
        } else {
            WhiteNoise.shared.detach()
        }

        // Read after voice processing is set: turning it on changes the input format.
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw CryMonitorError.noMicrophone }
        let queue = analysisQueue
        queue.async { gate.setInputFormat(format) }
        input.removeTap(onBus: 0)
        let bufferSize = AVAudioFrameCount(format.sampleRate * Self.tapSeconds)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: Self.tap(gate: gate, queue: queue))
        engine.prepare()
        try engine.start()
    }

    /// Apple's voice processing, only while the monitor device plays white noise. Its echo cancellation
    /// takes the device's own playback out of what the microphone hears, so the noise doesn't hide
    /// crying from the classifier. It must be switched while the engine is stopped, before the tap is
    /// installed. Needs a test on a real device: how much of the noise is removed depends on the hardware,
    /// and voice processing is tuned for speech.
    private func configureVoiceProcessing(_ enabled: Bool) throws {
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled != enabled {
            try input.setVoiceProcessingEnabled(enabled)
        }
        guard enabled else { return }
        // Automatic gain would turn a quiet nursery up until the noise floor sounds loud.
        input.isVoiceProcessingAGCEnabled = false
        // Voice processing turns other audio down while it runs; ask for the least of that.
        input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: false,
            duckingLevel: .min
        )
    }

    /// Stops the engine and sets it up again, keeping the cry episode and the classifier's state.
    private func restartAudio(failure message: String) {
        guard isListening, !isReconfiguring else { return }
        isReconfiguring = true
        defer { isReconfiguring = false }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        do {
            try configureAudio()
        } catch {
            stop()
            setError(message)
        }
    }

    // MARK: Helpers

    private var repeatInterval: TimeInterval {
        mode == .monitorDevice ? Self.remoteRepeatAlertAfter : Self.repeatAlertAfter
    }

    private var quietToEnd: TimeInterval {
        isLowPowerMode ? Self.lowPowerQuietToEnd : Self.quietToEnd
    }

    private func finishEpisode() {
        if let cryStart, let lastHeard {
            episodes.insert(CryEpisode(start: cryStart, end: lastHeard), at: 0)
        }
        resetEpisode()
    }

    private func resetEpisode() {
        if cryStart != nil { cryStart = nil }
        lastHeard = nil
        lastAlert = nil
        escalated = false
        recentVotes.removeAll()
        setGateEpisode(false)
    }

    /// While a cry episode goes on, the gate keeps the classifier listening.
    private func setGateEpisode(_ active: Bool) {
        guard let gate else { return }
        analysisQueue.async { gate.episodeActive = active }
    }

    private func setLastAction(_ action: String?) {
        if lastAction != action { lastAction = action }
    }

    private func setError(_ message: String?) {
        if errorMessage != message { errorMessage = message }
    }

    /// Low Power Mode makes the gate a little less eager. Listening never stops because of it.
    private func powerStateChanged() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if isLowPowerMode != lowPower { isLowPowerMode = lowPower }
        guard let gate else { return }
        let tuning = CryGateTuning.make(sensitivity: NightPlan.load().crySensitivity, lowPower: lowPower)
        analysisQueue.async { gate.tuning = tuning }
    }

    /// With a night plan, listening stops by itself when the night ends.
    /// When listening stops by itself, from the parent's choice in Cry alerts (`ListeningStop`), counted
    /// from when it started. Also called when that choice changes while listening. A timer stops it
    /// on time: in a quiet room the classifier, which checks `stopsAt` too, may not run at all.
    func updateStopTime() {
        stopTimer?.cancel()
        stopTimer = nil
        let stop = isListening && mode == .phone
            ? ListeningStop.stopDate(from: listeningSince ?? .now, plan: NightPlan.load())
            : nil
        if stopsAt != stop { stopsAt = stop }
        // Listening just started, or "until 7:00" changed.
        publishListening()
        guard let stop else { return }
        stopTimer = Task { [weak self] in
            let wait = stop.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self, self.isListening, self.stopsAt == stop else { return }
            self.stop()
            self.setLastAction(String(localized: "Stopped listening at \(stop.formatted(date: .omitted, time: .shortened)), as you chose."))
        }
    }

    /// The classifier's window closest to `classifierWindow` that it allows.
    private static func windowDuration(for request: SNClassifySoundRequest) -> CMTime {
        let wanted = CMTime(seconds: classifierWindow, preferredTimescale: 1000)
        switch request.windowDurationConstraint {
        case .enumeratedDurations(let allowed):
            let nearest = allowed.min { abs($0.seconds - classifierWindow) < abs($1.seconds - classifierWindow) }
            return nearest ?? request.windowDuration
        case .durationRange(let range):
            guard range.isValid else { return request.windowDuration }
            return CMTimeClampToRange(wanted, range: range)
        @unknown default:
            return request.windowDuration
        }
    }

    /// Phone calls and alarms pause the microphone; pick back up when they end.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                guard let self, self.isListening else { return }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.engine.start()
                } catch {
                    self.stop()
                    self.setError(String(localized: "Listening stopped after an interruption. Tap Start listening to resume."))
                }
            }
        }

        // Headphones, Bluetooth or a sample-rate change stop the engine; set it up again with the new
        // format. Switching voice processing can post this too, after the engine is already running
        // again, so a running engine is left alone.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening, !self.engine.isRunning else { return }
                self.restartAudio(failure: String(localized: "Listening stopped when the audio changed. Tap Start listening to resume."))
            }
        }
    }

    /// Built outside the main actor: the audio engine calls it on its own thread.
    private nonisolated static func tap(gate: CryGate, queue: DispatchQueue) -> AVAudioNodeTapBlock {
        { buffer, _ in
            queue.async {
                gate.process(buffer)
            }
        }
    }

    /// Built outside the main actor: the gate calls it on the analysis queue.
    private nonisolated static func gateHandler(for monitor: CryMonitor) -> @Sendable (Bool, CryGateMetrics) -> Void {
        { [weak monitor] active, metrics in
            Task { @MainActor in
                monitor?.classifierChanged(active, metrics: metrics)
            }
        }
    }
}

enum CryMonitorError: LocalizedError {
    case noMicrophone

    var errorDescription: String? { String(localized: "No microphone is available right now.") }
}

/// Receives classifier results and passes the crying confidence to the gate and the monitor.
private final class CryResultsObserver: NSObject, SNResultsObserving {
    private let labels: [String]
    private weak var monitor: CryMonitor?
    private let gate: CryGate
    private let queue: DispatchQueue

    init(labels: [String], monitor: CryMonitor, gate: CryGate, queue: DispatchQueue) {
        self.labels = labels
        self.monitor = monitor
        self.gate = gate
        self.queue = queue
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let confidence = labels.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0
        let gate = gate
        queue.async { gate.noteResult(confidence: confidence) }
        Task { @MainActor [weak monitor] in
            monitor?.handle(confidence: confidence)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
}
