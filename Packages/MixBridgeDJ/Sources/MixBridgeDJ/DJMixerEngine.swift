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

    /// Which physical deck is currently the "primary" (audible) deck.
    /// Defaults to `.a` to preserve existing behavior and tests.
    private var activeDeck: DJDeck = .a

    private var currentPlan: DJTransitionPlan?
    private var transitionStartSeconds: Double = 0
    private var transitionDurationSeconds: Double = 0

    /// Cached playback time for each deck, updated on pause so we can report accurate time when paused.
    /// AVAudioPlayerNode's playerTime(forNodeTime:) returns nil when paused, so we cache before pausing.
    private var cachedTimeA: Double?
    private var cachedTimeB: Double?

    /// Track timeline offset for each deck, in seconds.
    /// AVAudioPlayerNode's `playerTime` resets to 0 for each scheduled segment, so we keep
    /// an explicit base offset to report absolute "seconds into file" times for seeking,
    /// UI time, and scheduling transitions.
    private var deckStartOffsetSecondsA: Double = 0
    private var deckStartOffsetSecondsB: Double = 0

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

    // MARK: - Deck Helpers

    private func playerNode(for deck: DJDeck) -> AVAudioPlayerNode {
        deck == .a ? playerNodeA : playerNodeB
    }

    private func timePitch(for deck: DJDeck) -> AVAudioUnitTimePitch {
        deck == .a ? timePitchA : timePitchB
    }

    private func eqController(for deck: DJDeck) -> DJThreeBandEQ {
        deck == .a ? eqA : eqB
    }

    private func mixerNode(for deck: DJDeck) -> AVAudioMixerNode {
        deck == .a ? mixerNodeA : mixerNodeB
    }

    private func audioFile(for deck: DJDeck) -> AVAudioFile? {
        deck == .a ? audioFileA : audioFileB
    }

    private func timing(for deck: DJDeck) -> DJTrackTiming? {
        deck == .a ? timingA : timingB
    }

    private func setAudioFile(_ file: AVAudioFile?, timing: DJTrackTiming?, for deck: DJDeck) {
        switch deck {
        case .a:
            audioFileA = file
            timingA = timing
        case .b:
            audioFileB = file
            timingB = timing
        }
    }
    
    private func deckStartOffsetSeconds(for deck: DJDeck) -> Double {
        deck == .a ? deckStartOffsetSecondsA : deckStartOffsetSecondsB
    }
    
    private func setDeckStartOffsetSeconds(_ seconds: Double, for deck: DJDeck) {
        let clamped = max(0, seconds)
        switch deck {
        case .a:
            deckStartOffsetSecondsA = clamped
        case .b:
            deckStartOffsetSecondsB = clamped
        }
    }

    private func cachedTime(for deck: DJDeck) -> Double? {
        deck == .a ? cachedTimeA : cachedTimeB
    }

    private func setCachedTime(_ time: Double?, for deck: DJDeck) {
        switch deck {
        case .a:
            cachedTimeA = time
        case .b:
            cachedTimeB = time
        }
    }

    private func otherDeck(than deck: DJDeck) -> DJDeck {
        deck == .a ? .b : .a
    }

    private func setActiveDeck(_ deck: DJDeck) {
        activeDeck = deck
        mixerNode(for: deck).outputVolume = 1.0
        mixerNode(for: otherDeck(than: deck)).outputVolume = 0.0
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

        setAudioFile(audioFile, timing: timing, for: deck)
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

    /// Pauses playback on both decks (engine keeps its graph).
    public func pause() {
        // Cache current time before pausing - AVAudioPlayerNode's playerTime returns nil when paused.
        cachedTimeA = currentTimeFromNode(for: .a)
        cachedTimeB = currentTimeFromNode(for: .b)
        playerNodeA.pause()
        playerNodeB.pause()
    }

    /// Resumes playback for the currently active deck (and the other deck if transitioning).
    public func resume() {
        // Clear cached time so we use live time from the player node.
        cachedTimeA = nil
        cachedTimeB = nil

        switch state {
        case .transitioning:
            playerNodeA.play()
            playerNodeB.play()
        case .playing, .idle, .stopped:
            playerNode(for: activeDeck).play()
        }
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
        try play(deck: .a, fromSeconds: 0)
    }

    /// Gets the current playback time of deck A in seconds.
    public func currentTimeA() -> Double {
        currentTime(for: .a)
    }

    /// Starts playing the given deck from an optional offset.
    /// The started deck becomes the active (primary) deck and the other deck is silenced.
    public func play(deck: DJDeck, fromSeconds: Double) throws {
        guard let file = audioFile(for: deck) else {
            throw DJMixerError.invalidConfiguration("No audio file loaded on deck \(deck)")
        }

        let startSeconds = max(0, fromSeconds)
        let fileSampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(startSeconds * fileSampleRate)
        let clampedStartFrame = max(0, min(file.length, startFrame))
        let remaining = max(0, file.length - clampedStartFrame)

        let node = playerNode(for: deck)
        node.stop()

        if clampedStartFrame > 0 {
            node.scheduleSegment(
                file,
                startingFrame: clampedStartFrame,
                frameCount: AVAudioFrameCount(remaining),
                at: nil
            )
        } else {
            node.scheduleFile(file, at: nil)
        }

        // Ensure only this deck is audible.
        setActiveDeck(deck)
        setDeckStartOffsetSeconds(Double(clampedStartFrame) / fileSampleRate, for: deck)

        node.play()
        state = .playing
    }

    /// Gets the current playback time of the specified deck in seconds.
    public func currentTime(for deck: DJDeck) -> Double {
        // Try to get live time from the player node first.
        if let liveTime = currentTimeFromNode(for: deck) {
            return liveTime
        }
        // Fall back to cached time (set when paused) to avoid returning 0.
        return cachedTime(for: deck) ?? 0
    }

    /// Gets the current time directly from AVAudioPlayerNode. Returns nil if not available (e.g., when paused).
    private func currentTimeFromNode(for deck: DJDeck) -> Double? {
        let node = playerNode(for: deck)
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        let segmentSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        return deckStartOffsetSeconds(for: deck) + segmentSeconds
    }

    // MARK: - Transition Execution

    /// Executes a transition from deck A to deck B using the specified plan.
    /// - Parameter plan: The transition plan to execute.
    public func executeTransition(plan: DJTransitionPlan) throws {
        guard state == .playing else {
            throw DJMixerError.engineNotRunning
        }

        let outgoingDeck = activeDeck
        let incomingDeck = otherDeck(than: outgoingDeck)

        guard let audioFileIncoming = audioFile(for: incomingDeck) else {
            throw DJMixerError.invalidConfiguration("No audio file loaded on incoming deck")
        }

        // Validate the plan
        let validationResult = validator.validate(
            plan: plan,
            outgoingTiming: timing(for: outgoingDeck),
            incomingTiming: timing(for: incomingDeck)
        )

        let validatedPlan = validationResult.validatedPlan
        currentPlan = validatedPlan

        // Apply tempo matching to incoming deck
        let incomingTimePitch = timePitch(for: incomingDeck)
        if validatedPlan.tempoMatch.enabled, let incomingBPM = timing(for: incomingDeck)?.bpm {
            // Compute rate: targetBPM / incomingBPM, clamped to safe range
            let rate = validatedPlan.tempoMatch.computeRate(incomingBPM: incomingBPM)
            incomingTimePitch.rate = Float(rate)
            // Keep pitch at 0 (pitch-preserving time stretch)
            incomingTimePitch.pitch = 0.0
        } else {
            incomingTimePitch.rate = 1.0
            incomingTimePitch.pitch = 0.0
        }

        // Compute incoming start time based on beat alignment
        let fadeStartTime = validatedPlan.fadeStartSeconds
        var incomingStartTime = fadeStartTime

        if let outgoingTiming = timing(for: outgoingDeck) {
            incomingStartTime = validatedPlan.computeIncomingStartTime(
                outgoingTiming: outgoingTiming,
                fadeStartTime: fadeStartTime
            )
        }

        // Calculate the start offset for incoming track to align its downbeat
        var incomingStartOffsetFrames: AVAudioFramePosition = 0
        if let incomingTiming = timing(for: incomingDeck) {
            // Segment offsets are in *file frames*, not engine sample rate.
            incomingStartOffsetFrames = AVAudioFramePosition(incomingTiming.downbeatOffsetSeconds * audioFileIncoming.processingFormat.sampleRate)
        }
        setDeckStartOffsetSeconds(Double(incomingStartOffsetFrames) / audioFileIncoming.processingFormat.sampleRate, for: incomingDeck)

        // Schedule the incoming deck to start at the computed time.
        // Use host time for reliable future scheduling (sample time doesn't work reliably).
        let incomingNode = playerNode(for: incomingDeck)

        let startTime: AVAudioTime?
        let currentOutgoingTime = currentTime(for: outgoingDeck)
        let delaySeconds = max(0, incomingStartTime - currentOutgoingTime)

        if delaySeconds > 0.1 {
            // Convert delay to host time (nanoseconds via mach_absolute_time)
            var timebaseInfo = mach_timebase_info_data_t()
            mach_timebase_info(&timebaseInfo)
            let hostTicksPerSecond = Double(timebaseInfo.denom) / Double(timebaseInfo.numer) * 1_000_000_000
            let delayHostTicks = UInt64(delaySeconds * hostTicksPerSecond)
            let targetHostTime = mach_absolute_time() + delayHostTicks
            startTime = AVAudioTime(hostTime: targetHostTime)
        } else {
            // Start immediately if we're already at or past the transition point
            startTime = nil
        }

        // Schedule incoming deck with offset to align downbeat (offset in file frames).
        let remainingFrames = max(0, audioFileIncoming.length - incomingStartOffsetFrames)

        incomingNode.scheduleSegment(
            audioFileIncoming,
            startingFrame: incomingStartOffsetFrames,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: startTime
        )
        incomingNode.play()

        // Record transition timing for progress calculation (seconds on outgoing track timeline).
        transitionStartSeconds = incomingStartTime
        transitionDurationSeconds = validatedPlan.fadeDurationSeconds

        state = .transitioning
    }

    /// Immediately cuts to a specific deck, stopping the other deck and making the target deck primary.
    public func cutToDeck(_ deck: DJDeck) {
        let other = otherDeck(than: deck)
        playerNode(for: other).stop()
        mixerNode(for: other).outputVolume = 0.0
        mixerNode(for: deck).outputVolume = 1.0
        activeDeck = deck
        currentPlan = nil
        transitionStartSeconds = 0
        transitionDurationSeconds = 0
        state = .playing
    }

    /// Advances transition state in real-time. Call periodically (e.g., 30–60Hz) while transitioning.
    /// - Returns: current transition progress (0..1) if transitioning, else nil.
    @discardableResult
    public func tick() -> Double? {
        guard state == .transitioning, let plan = currentPlan else { return nil }

        let outgoingDeck = activeDeck
        let currentSeconds = currentTime(for: outgoingDeck)
        updateTransitionProgress(currentSeconds: currentSeconds, plan: plan, outgoingDeck: outgoingDeck)

        let elapsed = currentSeconds - transitionStartSeconds
        guard transitionDurationSeconds > 0 else { return 1.0 }
        return min(1.0, max(0.0, elapsed / transitionDurationSeconds))
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

                // Update crossfade and EQ during transition (manual render uses engine timeline seconds)
                if state == .transitioning, let plan = currentPlan {
                    let currentSeconds = deckStartOffsetSeconds(for: activeDeck) + (Double(renderedFrames) / config.sampleRate)
                    updateTransitionProgress(currentSeconds: currentSeconds, plan: plan, outgoingDeck: activeDeck)
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
    private func updateTransitionProgress(currentSeconds: Double, plan: DJTransitionPlan, outgoingDeck: DJDeck) {
        guard transitionDurationSeconds > 0 else { return }

        let elapsed = currentSeconds - transitionStartSeconds
        guard elapsed >= 0 else { return }

        let progress = min(1.0, elapsed / transitionDurationSeconds)

        let incomingDeck = otherDeck(than: outgoingDeck)

        // Apply crossfade gains
        let (outgoingGain, incomingGain) = plan.crossfadeGains(at: progress)
        mixerNode(for: outgoingDeck).outputVolume = Float(outgoingGain)
        mixerNode(for: incomingDeck).outputVolume = Float(incomingGain)

        // Apply EQ curves
        eqController(for: outgoingDeck).applyEQCurves(plan.outgoingEQCurves, at: progress)
        eqController(for: incomingDeck).applyEQCurves(plan.incomingEQCurves, at: progress)

        if progress >= 1.0 {
            finalizeTransition(outgoingDeck: outgoingDeck, incomingDeck: incomingDeck)
        }
    }

    private func finalizeTransition(outgoingDeck: DJDeck, incomingDeck: DJDeck) {
        // Stop outgoing deck to conserve CPU and avoid accidental overlap.
        playerNode(for: outgoingDeck).stop()
        mixerNode(for: outgoingDeck).outputVolume = 0.0
        mixerNode(for: incomingDeck).outputVolume = 1.0
        activeDeck = incomingDeck
        state = .playing
        currentPlan = nil
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
        deck == .a ? eqA : eqB
    }

    // MARK: - Volume Access

    /// Gets the current volume of the specified deck.
    public func volume(for deck: DJDeck) -> Float {
        mixerNode(for: deck).outputVolume
    }

    /// Sets the volume of the specified deck.
    public func setVolume(_ volume: Float, for deck: DJDeck) {
        let clampedVolume = max(0.0, min(1.0, volume))
        mixerNode(for: deck).outputVolume = clampedVolume
    }

    // MARK: - Tempo Access

    /// Gets the playback rate of the specified deck.
    public func rate(for deck: DJDeck) -> Float {
        timePitch(for: deck).rate
    }

    /// Sets the playback rate of the specified deck.
    /// - Parameters:
    ///   - rate: Playback rate (1.0 = normal).
    ///   - deck: Which deck to adjust.
    ///   - preservePitch: Whether to preserve pitch (default true).
    public func setRate(_ rate: Float, for deck: DJDeck, preservePitch: Bool = true) {
        let unit = timePitch(for: deck)
        unit.rate = rate
        unit.pitch = preservePitch ? 0.0 : (rate - 1.0) * 1200.0 // cents
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
