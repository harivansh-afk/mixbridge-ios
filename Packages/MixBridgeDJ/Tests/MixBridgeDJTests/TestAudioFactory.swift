import AVFoundation
import Foundation

/// Factory for generating test audio files with known characteristics.
/// Used to create deterministic test inputs for DJ mixer verification.
enum TestAudioFactory {

    /// Generates a sine wave audio file at the specified BPM with click beats.
    /// - Parameters:
    ///   - bpm: Beats per minute.
    ///   - duration: Duration in seconds.
    ///   - frequency: Base sine wave frequency in Hz.
    ///   - sampleRate: Sample rate (default 44100).
    ///   - beatClickFrequency: Frequency of the beat click (default 1000 Hz).
    /// - Returns: URL to the generated audio file.
    static func generateBPMTestFile(
        bpm: Double,
        duration: Double,
        frequency: Double = 440.0,
        sampleRate: Double = 44100.0,
        beatClickFrequency: Double = 1000.0
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)
        let beatDuration = 60.0 / bpm
        let beatSamples = Int(beatDuration * sampleRate)
        let clickDurationSamples = Int(0.02 * sampleRate) // 20ms click

        // Create audio format
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw TestAudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestAudioError.bufferCreationFailed
        }

        // Generate audio: base sine wave + click on each beat
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate

            // Base sine wave (quieter background)
            let baseSine = Float(sin(2.0 * .pi * frequency * time) * 0.3)

            // Beat click (short burst at beat boundaries)
            var clickValue: Float = 0.0
            let framesIntoBeat = frame % beatSamples
            if framesIntoBeat < clickDurationSamples {
                let clickTime = Double(framesIntoBeat) / sampleRate
                // Envelope: quick attack, quick decay
                let envelope = Float(1.0 - Double(framesIntoBeat) / Double(clickDurationSamples))
                clickValue = Float(sin(2.0 * .pi * beatClickFrequency * clickTime)) * envelope * 0.7
            }

            let sample = baseSine + clickValue

            // Write to both channels
            channelData[0][frame] = sample
            channelData[1][frame] = sample
        }

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(bpm)bpm_\(UUID().uuidString).wav")

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Generates a simple sine wave file without beat markers.
    /// - Parameters:
    ///   - frequency: Sine wave frequency in Hz.
    ///   - duration: Duration in seconds.
    ///   - amplitude: Amplitude (0.0 to 1.0).
    ///   - sampleRate: Sample rate.
    /// - Returns: URL to the generated audio file.
    static func generateSineWave(
        frequency: Double,
        duration: Double,
        amplitude: Float = 0.5,
        sampleRate: Double = 44100.0
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw TestAudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestAudioError.bufferCreationFailed
        }

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let sample = Float(sin(2.0 * .pi * frequency * time)) * amplitude

            channelData[0][frame] = sample
            channelData[1][frame] = sample
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sine_\(Int(frequency))hz_\(UUID().uuidString).wav")

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Generates a white noise file for testing.
    /// - Parameters:
    ///   - duration: Duration in seconds.
    ///   - amplitude: Amplitude (0.0 to 1.0).
    ///   - sampleRate: Sample rate.
    /// - Returns: URL to the generated audio file.
    static func generateWhiteNoise(
        duration: Double,
        amplitude: Float = 0.3,
        sampleRate: Double = 44100.0
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw TestAudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestAudioError.bufferCreationFailed
        }

        // Use seeded random for deterministic output
        var rng = SeededRandomNumberGenerator(seed: 12345)

        for frame in 0..<frameCount {
            let noise = Float.random(in: -1.0...1.0, using: &rng) * amplitude

            channelData[0][frame] = noise
            channelData[1][frame] = noise
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("noise_\(UUID().uuidString).wav")

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Generates a multi-band test signal with distinct frequency content.
    /// Useful for testing EQ effects.
    /// - Parameters:
    ///   - duration: Duration in seconds.
    ///   - sampleRate: Sample rate.
    /// - Returns: URL to the generated audio file.
    static func generateMultiBandSignal(
        duration: Double,
        sampleRate: Double = 44100.0
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw TestAudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestAudioError.bufferCreationFailed
        }

        // Low: 60 Hz, Mid: 1000 Hz, High: 8000 Hz
        let lowFreq = 60.0
        let midFreq = 1000.0
        let highFreq = 8000.0

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate

            let low = Float(sin(2.0 * .pi * lowFreq * time)) * 0.3
            let mid = Float(sin(2.0 * .pi * midFreq * time)) * 0.3
            let high = Float(sin(2.0 * .pi * highFreq * time)) * 0.3

            let sample = low + mid + high

            channelData[0][frame] = sample
            channelData[1][frame] = sample
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multiband_\(UUID().uuidString).wav")

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }

    /// Cleans up a test audio file.
    static func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Errors from test audio generation.
enum TestAudioError: Error {
    case bufferCreationFailed
    case fileWriteFailed
}

/// Seeded random number generator for deterministic test output.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // Simple xorshift64 algorithm
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
