import Accelerate
import AVFoundation
import SoundAnalysis

/// How eager the loudness gate in front of the cry classifier is (see `CryGate`).
struct CryGateTuning: Sendable {
    /// How far above the room's usual level (its noise floor) a sound must be to wake the classifier.
    var marginDB: Float
    /// How long it must stay that loud first, so a door click or a cough doesn't wake it.
    var holdSeconds: Double
    /// How long the classifier listens once woken, unless it hears something cry-like, which keeps it going.
    var burstSeconds: Double
    /// A classifier result at least this sure of crying keeps it listening for another burst.
    var extendConfidence: Double

    /// - Medium: 10 dB above the floor for 0.5 s, then 7 s of listening.
    /// - High sensitivity hears softer cries (8 dB); Low needs a louder one (12 dB).
    /// - Low Power Mode asks for 2 dB more and 0.8 s, so the classifier wakes a little less often.
    static func make(sensitivity: CrySensitivity, lowPower: Bool) -> CryGateTuning {
        let margin: Float
        switch sensitivity {
        case .low: margin = 12
        case .medium: margin = 10
        case .high: margin = 8
        }
        return CryGateTuning(
            marginDB: margin + (lowPower ? 2 : 0),
            holdSeconds: lowPower ? 0.8 : 0.5,
            burstSeconds: 7,
            extendConfidence: sensitivity.threshold * 0.75
        )
    }
}

/// Counters for comparing battery use on a device (shown in Cry alerts in debug builds only).
struct CryGateMetrics: Sendable, Equatable {
    /// Buffers only the cheap loudness check looked at.
    var buffersGated = 0
    /// Buffers the classifier analyzed.
    var buffersClassified = 0
    /// Seconds of audio the classifier analyzed.
    var classifierSeconds: Double = 0
    /// Results the classifier produced.
    var inferences = 0
}

enum CryGateError: LocalizedError {
    case noFormat

    var errorDescription: String? { "The microphone's audio couldn't be prepared for listening." }
}

/// The cheap first stage of cry detection, in front of SoundAnalysis.
///
/// Running Apple's sound classifier all night is what makes a phone warm. Most of the night is quiet,
/// so every buffer first gets a loudness check (an RMS level with Accelerate, a few microseconds), compared
/// with the room's noise floor: a slow average of how loud the room usually is, so a fan or white noise
/// becomes part of "quiet". Only a sound that stays clearly louder than the floor wakes the classifier,
/// for a few seconds. The last second of audio is kept, and given to the classifier first, so the start of
/// the cry isn't missed. While a cry episode goes on, the classifier keeps listening until it ends.
///
/// Audio is converted to 16 kHz mono first, which is what the classifier listens at anyway.
///
/// Not thread-safe: everything runs on `CryMonitor`'s analysis queue, including `tuning` and `episodeActive`.
final class CryGate: @unchecked Sendable {
    /// SoundAnalysis' built-in classifier works at 16 kHz, so nothing is lost by converting down.
    static let sampleRate: Double = 16_000
    /// How much audio from before the gate opened is given to the classifier.
    static let preRollSeconds: Double = 1
    /// Quieter than anything a microphone reports, for an empty buffer.
    private static let silenceDB: Float = -140

    let analyzer: SNAudioStreamAnalyzer
    let analysisFormat: AVAudioFormat
    var tuning: CryGateTuning
    /// Set by the monitor while a cry episode goes on; the classifier keeps listening until it ends.
    var episodeActive = false

    /// Told when the classifier starts or stops listening.
    private let onChange: @Sendable (Bool, CryGateMetrics) -> Void
    private var converter: AVAudioConverter?
    private var noiseFloor: Float?
    /// How long the level has stayed above the floor, in seconds of audio.
    private var loudSeconds: Double = 0
    private var isClassifying = false
    /// Seconds of audio left before the classifier goes back to sleep.
    private var burstLeft: Double = 0
    /// The last `preRollSeconds` of audio, while only the gate is listening.
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames: AVAudioFrameCount = 0
    /// The analyzer sees one continuous stream made of the stretches it was given.
    private var framePosition: AVAudioFramePosition = 0
    private var metrics = CryGateMetrics()

    init(tuning: CryGateTuning, onChange: @escaping @Sendable (Bool, CryGateMetrics) -> Void) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
        ) else { throw CryGateError.noFormat }
        analysisFormat = format
        analyzer = SNAudioStreamAnalyzer(format: format)
        self.tuning = tuning
        self.onChange = onChange
    }

    /// The format the microphone tap delivers. Called again when it changes, e.g. when voice processing
    /// is switched on for white noise. Anything but 16 kHz mono goes through a converter.
    func setInputFormat(_ format: AVAudioFormat) {
        if format.sampleRate == analysisFormat.sampleRate, format.channelCount == 1,
           format.commonFormat == .pcmFormatFloat32, !format.isInterleaved {
            converter = nil
            return
        }
        let converter = AVAudioConverter(from: format, to: analysisFormat)
        // Several microphones become one channel.
        converter?.downmix = true
        // Plenty for telling crying apart from quiet, and cheaper than the default.
        converter?.sampleRateConverterQuality = AVAudioQuality.low.rawValue
        self.converter = converter
    }

    /// One buffer from the microphone tap.
    func process(_ input: AVAudioPCMBuffer) {
        guard let buffer = analysisBuffer(from: input), buffer.frameLength > 0 else { return }
        let seconds = Double(buffer.frameLength) / Self.sampleRate
        let level = Self.decibels(of: buffer)
        let loud = level > (noiseFloor ?? level) + tuning.marginDB
        adaptFloor(to: level, seconds: seconds)

        if isClassifying {
            feed(buffer, seconds: seconds)
            burstLeft -= seconds
            if burstLeft <= 0, !episodeActive {
                setClassifying(false)
            }
            return
        }

        #if DEBUG
        metrics.buffersGated += 1
        #endif
        remember(buffer)
        loudSeconds = loud ? loudSeconds + seconds : 0
        guard loudSeconds >= tuning.holdSeconds else { return }

        // Wake the classifier, starting with the second before, so the beginning of the cry is in it.
        burstLeft = tuning.burstSeconds
        setClassifying(true)
        for earlier in preRoll {
            feed(earlier, seconds: Double(earlier.frameLength) / Self.sampleRate)
        }
        preRoll.removeAll()
        preRollFrames = 0
    }

    /// A classifier result: anything that sounds like crying keeps it listening.
    func noteResult(confidence: Double) {
        #if DEBUG
        metrics.inferences += 1
        #endif
        if isClassifying, confidence >= tuning.extendConfidence {
            burstLeft = max(burstLeft, tuning.burstSeconds)
        }
    }

    func tearDown() {
        analyzer.removeAllRequests()
        preRoll.removeAll()
    }

    // MARK: Helpers

    private func setClassifying(_ classifying: Bool) {
        isClassifying = classifying
        loudSeconds = 0
        onChange(classifying, metrics)
    }

    private func feed(_ buffer: AVAudioPCMBuffer, seconds: Double) {
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
        #if DEBUG
        metrics.buffersClassified += 1
        metrics.classifierSeconds += seconds
        #endif
    }

    private func remember(_ buffer: AVAudioPCMBuffer) {
        preRoll.append(buffer)
        preRollFrames += buffer.frameLength
        let keep = AVAudioFrameCount(Self.preRollSeconds * Self.sampleRate)
        while let first = preRoll.first, preRollFrames - first.frameLength >= keep {
            preRoll.removeFirst()
            preRollFrames -= first.frameLength
        }
    }

    /// The floor follows the room: down quickly (2 s) when it gets quieter, up slowly (30 s) to steady
    /// sound like a fan or white noise, and barely (10 min) while a cry goes on, so crying never becomes
    /// the room's usual level.
    private func adaptFloor(to level: Float, seconds: Double) {
        guard let floor = noiseFloor else {
            noiseFloor = level
            return
        }
        let timeConstant: Double
        if level < floor {
            timeConstant = 2
        } else if episodeActive {
            timeConstant = 600
        } else {
            timeConstant = 30
        }
        let weight = Float(min(1, seconds / timeConstant))
        noiseFloor = max(Self.silenceDB, floor + weight * (level - floor))
    }

    /// 16 kHz mono, converted if the microphone delivers anything else.
    private func analysisBuffer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        guard buffer.format == converter.inputFormat else { return nil }
        let ratio = analysisFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: analysisFormat, frameCapacity: capacity) else { return nil }
        let supplier = OneBufferSupplier(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            supplier.next(inputStatus)
        }
        guard status != .error, error == nil else { return nil }
        return output
    }

    /// The buffer's loudness in dBFS (0 is full scale), from its RMS.
    private static func decibels(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return silenceDB }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        return max(silenceDB, 20 * log10(max(rms, 1e-7)))
    }
}

/// Hands the converter one buffer, then says there's nothing more for now, so the converter keeps its
/// state for the next one.
private final class OneBufferSupplier: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
