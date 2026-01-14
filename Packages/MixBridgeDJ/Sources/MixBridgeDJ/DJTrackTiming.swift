import Foundation

/// Timing metadata for a track used in DJ mixing operations.
/// This includes BPM, time signature, and downbeat offset information
/// required for beat-aligned transitions.
public struct DJTrackTiming: Sendable, Equatable {

    /// Beats per minute of the track.
    public let bpm: Double

    /// Time signature numerator (e.g., 4 for 4/4 time).
    public let timeSignatureNumerator: Int

    /// Time signature denominator (e.g., 4 for 4/4 time).
    public let timeSignatureDenominator: Int

    /// Offset in seconds from the start of the audio file to the first downbeat.
    /// Used to align the incoming track's downbeat to beat/bar boundaries.
    public let downbeatOffsetSeconds: Double

    /// Confidence level in the timing data (0.0 to 1.0).
    /// Used for fallback decisions when timing is uncertain.
    public let confidence: Double

    public init(
        bpm: Double,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4,
        downbeatOffsetSeconds: Double = 0.0,
        confidence: Double = 1.0
    ) {
        self.bpm = bpm
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.downbeatOffsetSeconds = downbeatOffsetSeconds
        self.confidence = max(0.0, min(1.0, confidence))
    }

    /// Duration of one beat in seconds.
    public var beatDurationSeconds: Double {
        60.0 / bpm
    }

    /// Duration of one bar in seconds.
    public var barDurationSeconds: Double {
        beatDurationSeconds * Double(timeSignatureNumerator)
    }

    /// Number of beats per bar.
    public var beatsPerBar: Int {
        timeSignatureNumerator
    }

    /// Returns true if timing data is considered valid for mixing operations.
    public var isValid: Bool {
        bpm > 0 && bpm <= 300 && confidence > 0.5
    }

    /// Computes the time of the next beat boundary at or after the given time.
    /// - Parameter currentTime: Current playback time in seconds.
    /// - Returns: Time of the next beat boundary in seconds.
    public func nextBeatBoundary(after currentTime: Double) -> Double {
        guard bpm > 0 else { return currentTime }

        // Calculate time relative to the first downbeat
        let adjustedTime = currentTime - downbeatOffsetSeconds
        let beatDuration = beatDurationSeconds

        // Find how many complete beats have passed
        let beatNumber = ceil(adjustedTime / beatDuration)

        // Return the time of that beat boundary, adjusted back to absolute time
        return (beatNumber * beatDuration) + downbeatOffsetSeconds
    }

    /// Computes the time of the next bar boundary at or after the given time.
    /// - Parameter currentTime: Current playback time in seconds.
    /// - Returns: Time of the next bar boundary in seconds.
    public func nextBarBoundary(after currentTime: Double) -> Double {
        guard bpm > 0 else { return currentTime }

        // Calculate time relative to the first downbeat
        let adjustedTime = currentTime - downbeatOffsetSeconds
        let barDuration = barDurationSeconds

        // Find how many complete bars have passed
        let barNumber = ceil(adjustedTime / barDuration)

        // Return the time of that bar boundary, adjusted back to absolute time
        return (barNumber * barDuration) + downbeatOffsetSeconds
    }

    /// Creates a default timing with no confidence (triggers fallback behavior).
    public static var unknown: DJTrackTiming {
        DJTrackTiming(bpm: 120.0, confidence: 0.0)
    }
}
