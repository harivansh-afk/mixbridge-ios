import Foundation

/// Protocol for storing and retrieving audio analysis results.
/// Implementations must be thread-safe for concurrent access.
public protocol DJAnalysisStore: Sendable {

    /// Retrieves a cached analysis result for the given track and file identity.
    /// - Parameters:
    ///   - trackId: Unique identifier for the track.
    ///   - fileIdentity: Current file identity to validate against cached entry.
    /// - Returns: The cached result if found and valid, nil otherwise.
    func get(trackId: String, fileIdentity: FileIdentity) async -> DJAnalysisResult?

    /// Stores an analysis result for the given track.
    /// - Parameters:
    ///   - result: The analysis result to cache.
    ///   - trackId: Unique identifier for the track.
    ///   - fileIdentity: File identity at the time of analysis.
    func put(result: DJAnalysisResult, trackId: String, fileIdentity: FileIdentity) async

    /// Invalidates the cached result for a track.
    /// - Parameter trackId: Unique identifier for the track to invalidate.
    func invalidate(trackId: String) async

    /// Clears all cached results.
    func clearAll() async
}

/// A no-op store that never caches anything.
/// Useful for testing or when caching is not desired.
public actor DJNullAnalysisStore: DJAnalysisStore {

    public init() {}

    public func get(trackId: String, fileIdentity: FileIdentity) async -> DJAnalysisResult? {
        nil
    }

    public func put(result: DJAnalysisResult, trackId: String, fileIdentity: FileIdentity) async {
        // No-op
    }

    public func invalidate(trackId: String) async {
        // No-op
    }

    public func clearAll() async {
        // No-op
    }
}

/// An in-memory store for testing purposes.
/// Does not persist across app launches.
public actor DJInMemoryAnalysisStore: DJAnalysisStore {

    private var cache: [String: DJAnalysisCacheEntry] = [:]

    /// Counter for cache hits - useful for testing.
    public private(set) var hitCount: Int = 0

    /// Counter for cache misses - useful for testing.
    public private(set) var missCount: Int = 0

    /// Counter for put operations - useful for testing.
    public private(set) var putCount: Int = 0

    public init() {}

    public func get(trackId: String, fileIdentity: FileIdentity) async -> DJAnalysisResult? {
        guard let entry = cache[trackId], entry.matches(identity: fileIdentity) else {
            missCount += 1
            return nil
        }
        hitCount += 1
        return entry.result
    }

    public func put(result: DJAnalysisResult, trackId: String, fileIdentity: FileIdentity) async {
        putCount += 1
        cache[trackId] = DJAnalysisCacheEntry(
            trackId: trackId,
            fileIdentity: fileIdentity,
            result: result
        )
    }

    public func invalidate(trackId: String) async {
        cache.removeValue(forKey: trackId)
    }

    public func clearAll() async {
        cache.removeAll()
    }

    /// Resets all counters (for testing).
    public func resetCounters() {
        hitCount = 0
        missCount = 0
        putCount = 0
    }

    /// Returns the current cache size (for testing).
    public var count: Int {
        cache.count
    }
}
