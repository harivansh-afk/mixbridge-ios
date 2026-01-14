import AVFoundation
import Accelerate

/// Deck identifier for the DJ mixer.
public enum DJDeck: Sendable {
    case a
    case b
}

/// Error types for DJ mixer operations.
public enum DJMixerError: Error, Sendable {
    case audioFileLoadFailed(URL, String)
    case engineNotRunning
    case invalidConfiguration(String)
    case renderingFailed(String)
    case transitionInProgress
}

/// State of the mixer engine.
public enum DJMixerState: Sendable {
    case idle
    case playing
    case transitioning
    case stopped
}

/// Configuration for the DJ mixer engine.
public struct DJMixerEngineConfig: Sendable {
    /// Sample rate for audio processing.
    public let sampleRate: Double

    /// Whether to enable manual rendering mode for offline processing.
    public let manualRenderingMode: Bool

    /// Maximum frames to render per cycle in manual mode.
    public let maxFramesPerRender: AVAudioFrameCount

    /// Default configuration for real-time playback.
    public static let realtime = DJMixerEngineConfig(
        sampleRate: 44100,
        manualRenderingMode: false,
        maxFramesPerRender: 4096
    )

    /// Configuration for offline/test rendering.
    public static let manualRendering = DJMixerEngineConfig(
        sampleRate: 44100,
        manualRenderingMode: true,
        maxFramesPerRender: 4096
    )

    public init(sampleRate: Double, manualRenderingMode: Bool, maxFramesPerRender: AVAudioFrameCount) {
        self.sampleRate = sampleRate
        self.manualRenderingMode = manualRenderingMode
        self.maxFramesPerRender = maxFramesPerRender
    }
}

/// DJ Mixer Engine with two decks, 3-band EQ per deck, tempo matching,
/// beat-aligned scheduling, and equal-power crossfade.
///
/// Supports both real-time playback and manual/offline rendering for testing.
public final class DJMixerEngine {
    // MARK: - Audio Engine Components

    private let engine: AVAudioEngine
    private let config: DJMixerEngineConfig

    // Deck A components
    private let playerNodeA: AVAudioPlayerNode
    private let timePitchA: AVAudioUnitTimePitch
    private let eqA: DJThreeBandEQ
    private let mixerNodeA: AVAudioMixerNode

    // Deck B components
    private let playerNodeB: AVAudioPlayerNode
    private let timePitchB: AVAudioUnitTimePitch
    private let eqB: DJThreeBandEQ
    private let mixerNodeB: AVAudioMixerNode

    // Main mixer
    private let mainMixer: AVAudioMixerNode

    // MARK: - State

    private var audioFileA: AVAudioFile?
    private var audioFileB: AVAudioFile?
    private var timingA: DJTrackTiming?
    private var timingB: DJTrackTiming?

    private(set) public var state: DJMixerState = .idle

    private var currentPlan: DJTransitionPlan?
    private var transitionStartSampleTime: AVAudioFramePosition = 0
    private var transitionDurationSamples: AVAudioFramePosition = 0

    private let validator: DJPlanValidator

    // MARK: - Initialization

    /// Creates a new DJ mixer engine with the specified configuration.
    public init(config: DJMixerEngineConfig = .realtime, validator: DJPlanValidator = .default) {
        self.config = config
        self.validator = validator

        // Create engine
        engine = AVAudioEngine()

        // Create deck A components
        playerNodeA = AVAudioPlayerNode()
        timePitchA = AVAudioUnitTimePitch()
        eqA = DJThreeBandEQ()
        mixerNodeA = AVAudioMixerNode()

        // Create deck B components
        playerNodeB = AVAudioPlayerNode()
        timePitchB = AVAudioUnitTimePitch()
        eqB = DJThreeBandEQ()
        mixerNodeB = AVAudioMixerNode()

        // Create main mixer
        mainMixer = AVAudioMixerNode()

        // Setup audio graph
        setupAudioGraph()
    }

    // MARK: - Audio Graph Setup

    private func setupAudioGraph() {
        // Attach all nodes to engine
        engine.attach(playerNodeA)
        engine.attach(timePitchA)
        engine.attach(eqA.eqNode)
        engine.attach(mixerNodeA)

        engine.attach(playerNodeB)
        engine.attach(timePitchB)
        engine.attach(eqB.eqNode)
        engine.attach(mixerNodeB)

        engine.attach(mainMixer)

        // Get format for connections
        let format = AVAudioFormat(standardFormatWithSampleRate: config.sampleRate, channels: 2)!

        // Connect deck A: player -> timePitch -> EQ -> mixer
        engine.connect(playerNodeA, to: timePitchA, format: format)
        engine.connect(timePitchA, to: eqA.eqNode, format: format)
        engine.connect(eqA.eqNode, to: mixerNodeA, format: format)

        // Connect deck B: player -> timePitch -> EQ -> mixer
        engine.connect(playerNodeB, to: timePitchB, format: format)
        engine.connect(timePitchB, to: eqB.eqNode, format: format)
        engine.connect(eqB.eqNode, to: mixerNodeB, format: format)

        // Connect both deck mixers to main mixer
        engine.connect(mixerNodeA, to: mainMixer, format: format)
        engine.connect(mixerNodeB, to: mainMixer, format: format)

        // Connect main mixer to output
        engine.connect(mainMixer, to: engine.mainMixerNode, format: format)

        // Initialize time pitch units with no change
        timePitchA.rate = 1.0
        timePitchA.pitch = 0.0 // No pitch shift
        timePitchA.overlap = 8.0 // Good quality

        timePitchB.rate = 1.0
        timePitchB.pitch = 0.0
        timePitchB.overlap = 8.0

        // Initialize mixer volumes
        mixerNodeA.outputVolume = 1.0
        mixerNodeB.outputVolume = 0.0 // B starts silent
    }

    // MARK: - Track Loading

    /// Loads an audio file into the specified deck.
    /// - Parameters:
    ///   - url: URL to the audio file.
    ///   - deck: Which deck to load into.
    ///   - timing: Timing metadata for the track.
    public func loadTrack(url: URL, deck: DJDeck, timing: DJTrackTiming) throws {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw DJMixerError.audioFileLoadFailed(url, error.localizedDescription)
        }

        switch deck {
        case .a:
            audioFileA = audioFile
            timingA = timing
        case .b:
            audioFileB = audioFile
            timingB = timing
        }
    }

    // MARK: - Engine Control

    /// Starts the audio engine.
    public func start() throws {
        if config.manualRenderingMode {
            try enableManualRenderingMode()
        }

        try engine.start()
        state = .idle
    }

    /// Stops the audio engine.
    public func stop() {
        playerNodeA.stop()
        playerNodeB.stop()
        engine.stop()
        state = .stopped
    }

    /// Enables manual rendering mode for offline processing.
    private func enableManualRenderingMode() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: config.sampleRate, channels: 2)!

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: config.maxFramesPerRender
        )
    }

    // MARK: - Playback

    /// Starts playing deck A from the beginning.
    public func playDeckA() throws {
        guard let audioFile = audioFileA else {
            throw DJMixerError.invalidConfiguration("No audio file loaded on deck A")
        }

        playerNodeA.scheduleFile(audioFile, at: nil)
        playerNodeA.play()
        state = .playing
    }

    /// Gets the current playback time of deck A in seconds.
    public func currentTimeA() -> Double {
        guard let nodeTime = playerNodeA.lastRenderTime,
              let playerTime = playerNodeA.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    // MARK: - Transition Execution

    /// Executes a transition from deck A to deck B using the specified plan.
    /// - Parameter plan: The transition plan to execute.
    public func executeTransition(plan: DJTransitionPlan) throws {
        guard state == .playing else {
            throw DJMixerError.engineNotRunning
        }

        guard let audioFileB = audioFileB else {
            throw DJMixerError.invalidConfiguration("No audio file loaded on deck B")
        }

        // Validate the plan
        let validationResult = validator.validate(
            plan: plan,
            outgoingTiming: timingA,
            incomingTiming: timingB
        )

        let validatedPlan = validationResult.validatedPlan
        currentPlan = validatedPlan

        // Apply tempo matching to deck B
        if validatedPlan.tempoMatch.enabled, let incomingBPM = timingB?.bpm {
            // Compute rate: targetBPM / incomingBPM, clamped to safe range
            let rate = validatedPlan.tempoMatch.computeRate(incomingBPM: incomingBPM)
            timePitchB.rate = Float(rate)
            // Keep pitch at 0 (pitch-preserving time stretch)
            timePitchB.pitch = 0.0
        } else {
            timePitchB.rate = 1.0
            timePitchB.pitch = 0.0
        }

        // Compute incoming start time based on beat alignment
        let fadeStartTime = validatedPlan.fadeStartSeconds
        var incomingStartTime = fadeStartTime

        if let outgoingTiming = timingA {
            incomingStartTime = validatedPlan.computeIncomingStartTime(
                outgoingTiming: outgoingTiming,
                fadeStartTime: fadeStartTime
            )
        }

        // Calculate the start offset for incoming track to align its downbeat
        var incomingStartOffset: AVAudioFramePosition = 0
        if let incomingTiming = timingB {
            // Start from the downbeat offset so the first downbeat aligns
            incomingStartOffset = AVAudioFramePosition(incomingTiming.downbeatOffsetSeconds * config.sampleRate)
        }

        // Schedule deck B to start at the computed time
        let startSampleTime = AVAudioFramePosition(incomingStartTime * config.sampleRate)

        if let nodeTime = playerNodeA.lastRenderTime {
            let startTime = AVAudioTime(sampleTime: startSampleTime + nodeTime.sampleTime, atRate: config.sampleRate)

            // Schedule deck B with offset to align downbeat
            playerNodeB.scheduleSegment(
                audioFileB,
                startingFrame: incomingStartOffset,
                frameCount: AVAudioFrameCount(audioFileB.length - incomingStartOffset),
                at: startTime
            )
            playerNodeB.play()
        } else {
            // Fallback: schedule immediately
            playerNodeB.scheduleSegment(
                audioFileB,
                startingFrame: incomingStartOffset,
                frameCount: AVAudioFrameCount(audioFileB.length - incomingStartOffset),
                at: nil
            )
            playerNodeB.play()
        }

        // Record transition timing for progress calculation
        transitionStartSampleTime = AVAudioFramePosition(incomingStartTime * config.sampleRate)
        transitionDurationSamples = AVAudioFramePosition(validatedPlan.fadeDurationSeconds * config.sampleRate)

        state = .transitioning
    }

    // MARK: - Manual Rendering

    /// Renders audio offline and returns the output buffer.
    /// Used for testing to verify mixing behavior.
    /// - Parameter frameCount: Number of frames to render.
    /// - Returns: Buffer containing rendered audio.
    public func renderOffline(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard config.manualRenderingMode else {
            throw DJMixerError.invalidConfiguration("Engine not in manual rendering mode")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: config.sampleRate, channels: 2)!
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DJMixerError.renderingFailed("Could not create output buffer")
        }

        var renderedFrames: AVAudioFrameCount = 0

        while renderedFrames < frameCount {
            let framesToRender = min(config.maxFramesPerRender, frameCount - renderedFrames)

            guard let tempBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRender) else {
                throw DJMixerError.renderingFailed("Could not create temp buffer")
            }

            let status = try engine.renderOffline(framesToRender, to: tempBuffer)

            switch status {
            case .success:
                // Copy rendered frames to output buffer
                copyBuffer(from: tempBuffer, to: outputBuffer, atFrame: renderedFrames)
                renderedFrames += tempBuffer.frameLength

                // Update crossfade and EQ during transition
                if state == .transitioning, let plan = currentPlan {
                    updateTransitionProgress(currentFrame: renderedFrames, plan: plan)
                }

            case .insufficientDataFromInputNode:
                // No more data available
                break

            case .cannotDoInCurrentContext:
                throw DJMixerError.renderingFailed("Cannot render in current context")

            case .error:
                throw DJMixerError.renderingFailed("Render error")

            @unknown default:
                break
            }

            if status != .success {
                break
            }
        }

        outputBuffer.frameLength = renderedFrames
        return outputBuffer
    }

    /// Updates transition progress and applies crossfade/EQ changes.
    private func updateTransitionProgress(currentFrame: AVAudioFrameCount, plan: DJTransitionPlan) {
        guard transitionDurationSamples > 0 else { return }

        let currentSampleTime = AVAudioFramePosition(currentFrame)
        let elapsed = currentSampleTime - transitionStartSampleTime

        guard elapsed >= 0 else { return }

        let progress = min(1.0, Double(elapsed) / Double(transitionDurationSamples))

        // Apply crossfade gains
        let (outgoingGain, incomingGain) = plan.crossfadeGains(at: progress)
        mixerNodeA.outputVolume = Float(outgoingGain)
        mixerNodeB.outputVolume = Float(incomingGain)

        // Apply EQ curves
        eqA.applyEQCurves(plan.outgoingEQCurves, at: progress)
        eqB.applyEQCurves(plan.incomingEQCurves, at: progress)

        // Check if transition is complete
        if progress >= 1.0 {
            state = .playing
            // Deck B is now primary
        }
    }

    private func copyBuffer(from source: AVAudioPCMBuffer, to dest: AVAudioPCMBuffer, atFrame offset: AVAudioFrameCount) {
        guard let srcData = source.floatChannelData,
              let dstData = dest.floatChannelData else { return }

        let channelCount = Int(source.format.channelCount)
        let frameCount = Int(source.frameLength)

        for channel in 0..<channelCount {
            let srcPtr = srcData[channel]
            let dstPtr = dstData[channel].advanced(by: Int(offset))
            memcpy(dstPtr, srcPtr, frameCount * MemoryLayout<Float>.size)
        }
    }

    // MARK: - EQ Access

    /// Gets the EQ for the specified deck.
    public func eq(for deck: DJDeck) -> DJThreeBandEQ {
        switch deck {
        case .a: return eqA
        case .b: return eqB
        }
    }

    // MARK: - Volume Access

    /// Gets the current volume of the specified deck.
    public func volume(for deck: DJDeck) -> Float {
        switch deck {
        case .a: return mixerNodeA.outputVolume
        case .b: return mixerNodeB.outputVolume
        }
    }

    /// Sets the volume of the specified deck.
    public func setVolume(_ volume: Float, for deck: DJDeck) {
        let clampedVolume = max(0.0, min(1.0, volume))
        switch deck {
        case .a: mixerNodeA.outputVolume = clampedVolume
        case .b: mixerNodeB.outputVolume = clampedVolume
        }
    }

    // MARK: - Tempo Access

    /// Gets the playback rate of the specified deck.
    public func rate(for deck: DJDeck) -> Float {
        switch deck {
        case .a: return timePitchA.rate
        case .b: return timePitchB.rate
        }
    }

    /// Sets the playback rate of the specified deck.
    /// - Parameters:
    ///   - rate: Playback rate (1.0 = normal).
    ///   - deck: Which deck to adjust.
    ///   - preservePitch: Whether to preserve pitch (default true).
    public func setRate(_ rate: Float, for deck: DJDeck, preservePitch: Bool = true) {
        let timePitch = deck == .a ? timePitchA : timePitchB
        timePitch.rate = rate
        timePitch.pitch = preservePitch ? 0.0 : (rate - 1.0) * 1200.0 // cents
    }
}

// MARK: - Audio Analysis Utilities

extension DJMixerEngine {
    /// Computes the RMS (root mean square) energy of a buffer.
    /// - Parameter buffer: Audio buffer to analyze.
    /// - Returns: RMS value (linear, not dB).
    public static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var totalSquaredSum: Float = 0

        for channel in 0..<channelCount {
            let data = channelData[channel]
            var squaredSum: Float = 0

            vDSP_svesq(data, 1, &squaredSum, vDSP_Length(frameCount))
            totalSquaredSum += squaredSum
        }

        let meanSquared = totalSquaredSum / Float(frameCount * channelCount)
        return sqrt(meanSquared)
    }

    /// Computes the high-frequency energy of a buffer using a simple high-pass approximation.
    /// Uses the difference between adjacent samples as a simple high-pass filter.
    /// - Parameter buffer: Audio buffer to analyze.
    /// - Returns: High-frequency energy estimate.
    public static func computeHighFrequencyEnergy(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameCount > 1 else { return 0 }

        var totalHFEnergy: Float = 0

        for channel in 0..<channelCount {
            let data = channelData[channel]

            // Simple differentiator as high-pass approximation
            for i in 1..<frameCount {
                let diff = data[i] - data[i - 1]
                totalHFEnergy += diff * diff
            }
        }

        return sqrt(totalHFEnergy / Float((frameCount - 1) * channelCount))
    }
}
