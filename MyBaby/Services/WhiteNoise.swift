import AVFoundation
import Observation
import os

/// The sound the nursery monitor plays.
enum NoiseColor: String, CaseIterable, Identifiable, Codable {
    case off, white, pink, brown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .white: return "White"
        case .pink: return "Pink"
        case .brown: return "Brown"
        }
    }

    /// What it sounds like, for the picker's footer and VoiceOver.
    var detail: String {
        switch self {
        case .off: return "No sound."
        case .white: return "A bright hiss, like a radio between stations."
        case .pink: return "Softer, like steady rain."
        case .brown: return "Deep and low, like a distant waterfall."
        }
    }
}

/// When white noise turns itself off.
enum NoiseTimer: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case allNight = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .allNight: return "All night"
        }
    }

    var duration: TimeInterval? { rawValue == 0 ? nil : Double(rawValue) * 60 }
}

/// White, pink or brown noise made on the device, played by the nursery monitor through the same audio
/// engine that listens for crying (`CryMonitor`), so its echo cancellation can take the noise back out of
/// what the microphone hears. Nothing is downloaded or streamed.
///
/// **Volume.** The slider is capped well below full scale (`maxAmplitude`). The American Academy of
/// Pediatrics advises keeping a white noise machine well away from the crib (at least 7 feet, about 2 m)
/// and at a low volume, about as loud as a soft shower (50 dB): infant sleep machines at full volume can
/// exceed safe noise levels (Hugh et al., "Infant Sleep Machines and Hazardous Sound Pressure Levels",
/// Pediatrics 2014;133(4):677–681). The device's own volume buttons still apply on top, so the monitor
/// screen says this too.
@MainActor
@Observable
final class WhiteNoise {
    static let shared = WhiteNoise()

    /// The loudest the generator ever plays, as a fraction of full scale (about −12 dBFS).
    static let maxAmplitude: Float = 0.25

    private(set) var color: NoiseColor
    /// 0–1 of `maxAmplitude`.
    private(set) var volume: Double
    private(set) var timer: NoiseTimer
    /// When the sleep timer turns the noise off, while it's playing.
    private(set) var stopsAt: Date?

    var isPlaying: Bool { color != .off }

    @ObservationIgnored private let renderer = NoiseRenderer()
    @ObservationIgnored private var node: AVAudioSourceNode?
    @ObservationIgnored private weak var engine: AVAudioEngine?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    private enum Key {
        static let color = "whiteNoiseColor"
        static let volume = "whiteNoiseVolume"
        static let timer = "whiteNoiseTimer"
    }

    private init() {
        let defaults = UserDefaults.standard
        color = defaults.string(forKey: Key.color).flatMap(NoiseColor.init(rawValue:)) ?? .off
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.4
        timer = NoiseTimer(rawValue: defaults.integer(forKey: Key.timer)) ?? .allNight
    }

    // MARK: Settings

    func setColor(_ newColor: NoiseColor) {
        guard newColor != color else { return }
        let wasPlaying = isPlaying
        color = newColor
        UserDefaults.standard.set(newColor.rawValue, forKey: Key.color)
        pushTarget()
        restartTimer()
        // Echo cancellation is only on while noise plays, and switching it restarts the engine.
        if wasPlaying != isPlaying {
            if isPlaying {
                CryMonitor.shared.whiteNoiseChanged()
            } else {
                // Let it fade out first.
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !self.isPlaying else { return }
                    CryMonitor.shared.whiteNoiseChanged()
                }
            }
        }
    }

    func setVolume(_ newVolume: Double) {
        let clamped = min(max(newVolume, 0), 1)
        guard clamped != volume else { return }
        volume = clamped
        UserDefaults.standard.set(clamped, forKey: Key.volume)
        pushTarget()
    }

    func setTimer(_ newTimer: NoiseTimer) {
        guard newTimer != timer else { return }
        timer = newTimer
        UserDefaults.standard.set(newTimer.rawValue, forKey: Key.timer)
        restartTimer()
    }

    // MARK: The audio engine

    /// Adds the generator to `engine`, before it starts. `CryMonitor` calls this in monitor mode while
    /// noise is on, after turning on voice processing, which can change the output's sample rate.
    func attach(to engine: AVAudioEngine) {
        removeNode()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48_000, channels: 1) else { return }
        let node = Self.makeSourceNode(renderer: renderer, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.node = node
        self.engine = engine
        pushTarget()
        // Attached again after a route change: the sleep timer keeps counting.
        if stopsAt == nil {
            restartTimer()
        }
    }

    /// Takes the generator out of the engine, e.g. when the monitor stops.
    func detach() {
        removeNode()
        timerTask?.cancel()
        timerTask = nil
        if stopsAt != nil { stopsAt = nil }
    }

    private func removeNode() {
        if let node, let engine {
            engine.detach(node)
        }
        node = nil
        engine = nil
    }

    /// What the audio thread should play. It fades there, so changes never click.
    private func pushTarget() {
        let target = NoiseRenderer.Target(color: color, gain: Float(volume) * Self.maxAmplitude)
        renderer.target.withLock { $0 = target }
    }

    /// The sleep timer counts from when the noise starts, or from when the timer is changed.
    private func restartTimer() {
        timerTask?.cancel()
        timerTask = nil
        let ends = (isPlaying && node != nil) ? timer.duration.map { Date.now.addingTimeInterval($0) } : nil
        if stopsAt != ends { stopsAt = ends }
        guard let ends else { return }
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ends.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.setColor(.off)
        }
    }

    /// Built outside the main actor: the audio engine calls the block on its real-time thread.
    private nonisolated static func makeSourceNode(renderer: NoiseRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            isSilence.pointee = ObjCBool(renderer.render(frameCount: frameCount, into: audioBufferList))
            return noErr
        }
    }
}

/// Makes the noise on the audio thread.
///
/// Only `target` is shared with the main thread, behind a lock the audio thread never waits for: if it's
/// taken at that moment, the audio thread keeps what it had and picks up the change on the next buffer.
private final class NoiseRenderer: @unchecked Sendable {
    struct Target: Sendable {
        var color: NoiseColor
        var gain: Float
    }

    let target = OSAllocatedUnfairLock(initialState: Target(color: .off, gain: 0))

    // Audio thread only.
    private var current = Target(color: .off, gain: 0)
    /// The color being played, which keeps playing while it fades out after "Off".
    private var audible: NoiseColor = .white
    private var gain: Float = 0
    /// About half a second from silence to the loudest, so turning it on or off is gentle.
    private let rampPerSample: Float = 0.25 / 24_000  // `WhiteNoise.maxAmplitude` over 24,000 samples
    private var seed: UInt32 = 0x9E37_79B9
    /// Paul Kellet's filter for pink noise.
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    /// Brown noise: white noise added up, leaking back toward zero so it never drifts away.
    private var brown: Float = 0

    /// Fills the buffers and returns whether they're silent.
    func render(frameCount: AVAudioFrameCount, into list: UnsafeMutablePointer<AudioBufferList>) -> Bool {
        if let latest = target.withLockIfAvailable({ $0 }) {
            current = latest
        }
        if current.color != .off {
            audible = current.color
        }
        let goal: Float = current.color == .off ? 0 : current.gain
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let frames = Int(frameCount)

        if goal == 0, gain == 0 {
            for buffer in buffers {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return true
        }

        // The node's format is mono, so there's one buffer; any others get a copy. Nothing is allocated
        // here, since this runs on the real-time audio thread.
        guard let first = buffers.first, let data = first.mData else { return true }
        let output = data.assumingMemoryBound(to: Float.self)
        let count = min(frames, Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        for frame in 0..<count {
            if gain < goal {
                gain = min(goal, gain + rampPerSample)
            } else if gain > goal {
                gain = max(goal, gain - rampPerSample)
            }
            output[frame] = next(audible) * gain
        }
        for index in 1..<max(1, buffers.count) {
            if let copy = buffers[index].mData {
                memcpy(copy, data, min(Int(buffers[index].mDataByteSize), count * MemoryLayout<Float>.size))
            }
        }
        return false
    }

    /// One sample, roughly −1…1, with the three colors about equally loud.
    private func next(_ color: NoiseColor) -> Float {
        let white = random()
        switch color {
        case .off, .white:
            return white * 0.5
        case .pink:
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink * 0.11
        case .brown:
            brown = (brown + 0.02 * white) / 1.02
            return brown * 3.5
        }
    }

    /// A fast xorshift generator; the system's would be too slow, and may lock, on the audio thread.
    private func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }
}
