import Foundation

/// Result of local audio analysis containing BPM, beat phase, and confidence metrics.
public struct DJAnalysisResult: Sendable, Equatable, Codable {

    /// Detected beats per minute.
    public let bpm: Double

    /// Time offset in seconds from the start of the track to the first beat (beat zero).
    /// For bar-aware analysis, this is the first downbeat.
    public let beatOffsetSeconds: Double

    /// Time signature numerator (e.g., 4 for 4/4 time).
    /// May be nil if time signature detection was not performed or failed.
    public let timeSignatureNumerator: Int?

    /// Time signature denominator (e.g., 4 for 4/4 time).
    public let timeSignatureDenominator: Int?

    /// Confidence score for the analysis (0.0 to 1.0).
    /// Based on periodicity strength, peak sharpness, and temporal stability.
    public let confidence: Double

    /// Analysis metadata for debugging and cache validation.
    public let metadata: AnalysisMetadata

    public init(
        bpm: Double,
        beatOffsetSeconds: Double,
        timeSignatureNumerator: Int? = 4,
        timeSignatureDenominator: Int? = 4,
        confidence: Double,
        metadata: AnalysisMetadata = .empty
    ) {
        self.bpm = bpm
        self.beatOffsetSeconds = beatOffsetSeconds
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.confidence = max(0.0, min(1.0, confidence))
        self.metadata = metadata
    }

    // MARK: - Beat Sync Helpers

    /// Returns true if this result is usable for beat-synchronized transitions.
    /// Uses a default threshold of 0.6.
    public var isUsableForBeatSync: Bool {
        isUsableForBeatSync(threshold: 0.6)
    }

    /// Returns true if confidence meets or exceeds the given threshold.
    /// Use this to determine whether to use beat-sync or fall back to simple crossfade.
    /// - Parameter threshold: Minimum confidence required (default 0.6).
    /// - Returns: True if analysis is confident enough for beat sync.
    public func isUsableForBeatSync(threshold: Double) -> Bool {
        confidence >= threshold && bpm > 0 && bpm <= 300
    }

    /// Duration of one beat in seconds.
    public var beatDurationSeconds: Double {
        guard bpm > 0 else { return 0 }
        return 60.0 / bpm
    }

    /// Duration of one bar in seconds (assumes 4/4 if time signature unknown).
    public var barDurationSeconds: Double {
        let beatsPerBar = timeSignatureNumerator ?? 4
        return beatDurationSeconds * Double(beatsPerBar)
    }

    /// Converts this result to a DJTrackTiming for use with transition planning.
    public func toTrackTiming() -> DJTrackTiming {
        DJTrackTiming(
            bpm: bpm,
            timeSignatureNumerator: timeSignatureNumerator ?? 4,
            timeSignatureDenominator: timeSignatureDenominator ?? 4,
            downbeatOffsetSeconds: beatOffsetSeconds,
            confidence: confidence
        )
    }

    // MARK: - Factory Methods

    /// Creates a low-confidence result indicating analysis failure.
    /// Callers should fall back to non-beat-synced transitions.
    public static func lowConfidence(reason: String) -> DJAnalysisResult {
        DJAnalysisResult(
            bpm: 0,
            beatOffsetSeconds: 0,
            timeSignatureNumerator: nil,
            timeSignatureDenominator: nil,
            confidence: 0,
            metadata: AnalysisMetadata(
                analysisVersion: AnalysisMetadata.currentVersion,
                analysisDurationMs: 0,
                failureReason: reason
            )
        )
    }

    /// Creates a result with explicit fallback indicator for non-periodic audio.
    public static func nonPeriodic() -> DJAnalysisResult {
        lowConfidence(reason: "Non-periodic audio detected")
    }
}

// MARK: - Analysis Metadata

/// Metadata about the analysis process for debugging and cache validation.
public struct AnalysisMetadata: Sendable, Equatable, Codable {

    /// Version of the analysis algorithm (for cache invalidation on upgrades).
    public let analysisVersion: String

    /// How long the analysis took in milliseconds.
    public let analysisDurationMs: Int

    /// Optional reason if analysis produced low-confidence result.
    public let failureReason: String?

    /// Current algorithm version - increment when algorithm changes significantly.
    public static let currentVersion = "1.0.0"

    public init(
        analysisVersion: String = currentVersion,
        analysisDurationMs: Int = 0,
        failureReason: String? = nil
    ) {
        self.analysisVersion = analysisVersion
        self.analysisDurationMs = analysisDurationMs
        self.failureReason = failureReason
    }

    public static let empty = AnalysisMetadata()
}

// MARK: - File Identity

/// Identifies a file for cache purposes using size and modification time.
/// This avoids expensive content hashing while still detecting changes.
public struct FileIdentity: Sendable, Equatable, Codable, Hashable {

    /// File size in bytes.
    public let size: UInt64

    /// Last modification timestamp (seconds since epoch).
    public let modificationTime: TimeInterval

    public init(size: UInt64, modificationTime: TimeInterval) {
        self.size = size
        self.modificationTime = modificationTime
    }

    /// Creates a file identity from a URL.
    /// Returns nil if file attributes cannot be read.
    public static func from(url: URL) -> FileIdentity? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        guard let size = attrs[.size] as? UInt64,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return FileIdentity(size: size, modificationTime: modDate.timeIntervalSince1970)
    }
}

// MARK: - Cache Entry

/// A cached analysis result with file identity for validation.
public struct DJAnalysisCacheEntry: Sendable, Codable {

    /// The track identifier (typically filename or unique ID).
    public let trackId: String

    /// File identity at the time of analysis.
    public let fileIdentity: FileIdentity

    /// The analysis result.
    public let result: DJAnalysisResult

    /// When this entry was created.
    public let createdAt: Date

    public init(
        trackId: String,
        fileIdentity: FileIdentity,
        result: DJAnalysisResult,
        createdAt: Date = Date()
    ) {
        self.trackId = trackId
        self.fileIdentity = fileIdentity
        self.result = result
        self.createdAt = createdAt
    }

    /// Returns true if this cache entry matches the given file identity.
    public func matches(identity: FileIdentity) -> Bool {
        fileIdentity == identity
    }
}
