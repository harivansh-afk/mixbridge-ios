import Foundation

/// Configuration options for local audio analysis.
public struct DJAnalysisOptions: Sendable, Equatable {

    /// Minimum BPM to consider during analysis (default: 60 BPM).
    public let minBPM: Double

    /// Maximum BPM to consider during analysis (default: 200 BPM).
    public let maxBPM: Double

    /// Analysis window size in seconds for onset detection (default: 0.1s).
    public let windowSizeSeconds: Double

    /// Hop size between analysis windows as fraction of window size (default: 0.5).
    public let hopFraction: Double

    /// Minimum confidence threshold for results to be considered usable (default: 0.6).
    public let confidenceThreshold: Double

    /// Whether to attempt bar-level alignment (downbeat detection).
    public let detectDownbeats: Bool

    /// Target sample rate for analysis (source will be resampled if different).
    public let analysisSampleRate: Double

    /// Maximum duration to analyze in seconds (for very long files).
    /// Analysis uses representative sections rather than entire file.
    public let maxAnalysisDurationSeconds: Double

    public init(
        minBPM: Double = 60.0,
        maxBPM: Double = 200.0,
        windowSizeSeconds: Double = 0.1,
        hopFraction: Double = 0.5,
        confidenceThreshold: Double = 0.6,
        detectDownbeats: Bool = true,
        analysisSampleRate: Double = 22050.0,
        maxAnalysisDurationSeconds: Double = 120.0
    ) {
        self.minBPM = max(30.0, minBPM)
        self.maxBPM = min(300.0, maxBPM)
        self.windowSizeSeconds = max(0.01, windowSizeSeconds)
        self.hopFraction = max(0.1, min(1.0, hopFraction))
        self.confidenceThreshold = max(0.0, min(1.0, confidenceThreshold))
        self.detectDownbeats = detectDownbeats
        self.analysisSampleRate = analysisSampleRate
        self.maxAnalysisDurationSeconds = maxAnalysisDurationSeconds
    }

    /// Default options suitable for most DJ use cases.
    public static let `default` = DJAnalysisOptions()

    /// Options optimized for click tracks and synthetic test signals.
    /// Uses higher sample rate and finer hop size for precision within 0.5 BPM.
    public static let clickTrack = DJAnalysisOptions(
        minBPM: 60.0,
        maxBPM: 200.0,
        windowSizeSeconds: 0.02,
        hopFraction: 0.1,
        confidenceThreshold: 0.5,
        detectDownbeats: true,
        analysisSampleRate: 44100.0
    )

    /// Computed properties

    /// Window size in samples at the analysis sample rate.
    public var windowSizeSamples: Int {
        Int(windowSizeSeconds * analysisSampleRate)
    }

    /// Hop size in samples.
    public var hopSizeSamples: Int {
        Int(Double(windowSizeSamples) * hopFraction)
    }

    /// Minimum beat interval in seconds (derived from maxBPM).
    public var minBeatIntervalSeconds: Double {
        60.0 / maxBPM
    }

    /// Maximum beat interval in seconds (derived from minBPM).
    public var maxBeatIntervalSeconds: Double {
        60.0 / minBPM
    }
}
