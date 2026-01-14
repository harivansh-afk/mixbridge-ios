import AVFoundation
import Foundation

/// Factory for generating deterministic click track audio files for testing.
/// Produces perfectly periodic click sounds at specified BPM values.
enum TestClickTrackFactory {

    /// Configuration for click track generation.
    struct Config {
        /// BPM of the click track.
        let bpm: Double

        /// Duration in seconds.
        let durationSeconds: Double

        /// Sample rate (default 44100 Hz).
        let sampleRate: Double

        /// Frequency of the click tone in Hz (default 1000 Hz).
        let clickFrequency: Double

        /// Duration of each click in seconds (default 0.02s).
        let clickDurationSeconds: Double

        /// Amplitude of clicks (0.0 to 1.0).
        let amplitude: Float

        /// Offset in seconds before the first beat (default 0).
        let beatOffsetSeconds: Double

        /// Whether to emphasize downbeats (louder every N beats).
        let emphasizeDownbeats: Bool

        /// Number of beats per bar for downbeat emphasis (default 4).
        let beatsPerBar: Int

        init(
            bpm: Double,
            durationSeconds: Double = 10.0,
            sampleRate: Double = 44100.0,
            clickFrequency: Double = 1000.0,
            clickDurationSeconds: Double = 0.02,
            amplitude: Float = 0.8,
            beatOffsetSeconds: Double = 0.0,
            emphasizeDownbeats: Bool = false,
            beatsPerBar: Int = 4
        ) {
            self.bpm = bpm
            self.durationSeconds = durationSeconds
            self.sampleRate = sampleRate
            self.clickFrequency = clickFrequency
            self.clickDurationSeconds = clickDurationSeconds
            self.amplitude = amplitude
            self.beatOffsetSeconds = beatOffsetSeconds
            self.emphasizeDownbeats = emphasizeDownbeats
            self.beatsPerBar = beatsPerBar
        }
    }

    /// Generates a click track audio file at the specified BPM.
    /// - Parameter config: Click track configuration.
    /// - Returns: URL to the generated temporary audio file.
    static func generate(config: Config) throws -> URL {
        let frameCount = Int(config.durationSeconds * config.sampleRate)
        let beatDurationSamples = Int(60.0 / config.bpm * config.sampleRate)
        let clickDurationSamples = Int(config.clickDurationSeconds * config.sampleRate)
        let offsetSamples = Int(config.beatOffsetSeconds * config.sampleRate)

        // Create stereo format
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRate,
            channels: 2
        ) else {
            throw TestClickTrackError.formatCreationFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw TestClickTrackError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestClickTrackError.bufferCreationFailed
        }

        // Generate click track
        for frame in 0..<frameCount {
            var sample: Float = 0.0

            // Calculate position relative to beat grid (accounting for offset)
            let adjustedFrame = frame - offsetSamples

            if adjustedFrame >= 0 {
                let framesIntoBeat = adjustedFrame % beatDurationSamples

                // Generate click at the start of each beat
                if framesIntoBeat < clickDurationSamples {
                    let clickTime = Double(framesIntoBeat) / config.sampleRate

                    // Envelope: exponential decay
                    let envelope = Float(exp(-clickTime * 100.0))

                    // Click tone
                    let tone = Float(sin(2.0 * .pi * config.clickFrequency * clickTime))

                    // Determine amplitude (louder for downbeats if enabled)
                    var amplitude = config.amplitude
                    if config.emphasizeDownbeats {
                        let beatNumber = adjustedFrame / beatDurationSamples
                        if beatNumber % config.beatsPerBar == 0 {
                            amplitude *= 1.3 // Downbeat is louder
                        }
                    }

                    sample = tone * envelope * amplitude
                }
            }

            // Write to both channels
            channelData[0][frame] = sample
            channelData[1][frame] = sample
        }

        // Write to temporary file
        let filename = "click_\(Int(config.bpm))bpm_\(UUID().uuidString).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Generates a simple click track at the given BPM with default settings.
    /// - Parameters:
    ///   - bpm: Beats per minute.
    ///   - duration: Duration in seconds (default 10s).
    /// - Returns: URL to the generated audio file.
    static func generate(bpm: Double, duration: Double = 10.0) throws -> URL {
        try generate(config: Config(bpm: bpm, durationSeconds: duration))
    }

    /// Generates a click track with a specific beat offset.
    /// - Parameters:
    ///   - bpm: Beats per minute.
    ///   - beatOffset: Time offset before first beat in seconds.
    ///   - duration: Duration in seconds.
    /// - Returns: URL to the generated audio file.
    static func generate(bpm: Double, beatOffset: Double, duration: Double = 10.0) throws -> URL {
        try generate(config: Config(
            bpm: bpm,
            durationSeconds: duration,
            beatOffsetSeconds: beatOffset
        ))
    }

    /// Generates a click track with downbeat emphasis.
    /// - Parameters:
    ///   - bpm: Beats per minute.
    ///   - beatsPerBar: Number of beats per bar.
    ///   - duration: Duration in seconds.
    /// - Returns: URL to the generated audio file.
    static func generateWithDownbeats(
        bpm: Double,
        beatsPerBar: Int = 4,
        duration: Double = 10.0
    ) throws -> URL {
        try generate(config: Config(
            bpm: bpm,
            durationSeconds: duration,
            emphasizeDownbeats: true,
            beatsPerBar: beatsPerBar
        ))
    }

    /// Generates white noise (non-periodic) for testing low-confidence detection.
    /// - Parameters:
    ///   - duration: Duration in seconds.
    ///   - amplitude: Noise amplitude.
    /// - Returns: URL to the generated audio file.
    static func generateWhiteNoise(duration: Double = 5.0, amplitude: Float = 0.3) throws -> URL {
        let sampleRate = 44100.0
        let frameCount = Int(duration * sampleRate)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw TestClickTrackError.formatCreationFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw TestClickTrackError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestClickTrackError.bufferCreationFailed
        }

        // Deterministic seeded random for reproducible tests
        var rng = SeededRNG(seed: 42)

        for frame in 0..<frameCount {
            let noise = Float.random(in: -1.0...1.0, using: &rng) * amplitude
            channelData[0][frame] = noise
            channelData[1][frame] = noise
        }

        let filename = "noise_\(UUID().uuidString).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Cleans up a generated test file.
    static func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Errors from click track generation.
enum TestClickTrackError: Error {
    case formatCreationFailed
    case bufferCreationFailed
}

/// Seeded random number generator for deterministic test output.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
