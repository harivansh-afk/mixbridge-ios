//
//  DJAnalysisManager.swift
//  mixbridge
//
//  Manages DJ audio analysis with persistent file-based caching.
//  Wraps MixBridgeDJ's DJLocalAnalyzer and DJFileAnalysisStore.
//

import Foundation
import MixBridgeDJ

/// Singleton manager for DJ audio analysis with persistent caching.
/// Thread-safe via actor isolation in the underlying analyzer.
@MainActor
final class DJAnalysisManager {
    static let shared = DJAnalysisManager()

    /// The underlying analyzer from MixBridgeDJ.
    private let analyzer: DJLocalAnalyzer

    /// The file-based cache store.
    private let store: DJFileAnalysisStore

    private init() {
        // Initialize the file-based analysis store with default location
        // (Application Support/MixBridgeDJ/AnalysisCache)
        do {
            store = try DJFileAnalysisStore.defaultStore()
            logInfo(.dj, "DJAnalysisManager: initialized with file-based cache")
        } catch {
            // Fallback: create store in a temp directory if default fails
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MixBridgeDJ/AnalysisCache", isDirectory: true)
            do {
                store = try DJFileAnalysisStore(cacheDirectory: tempDir)
                logWarning(.dj, "DJAnalysisManager: using temp directory for cache: \(error)")
            } catch {
                // This should never happen, but handle gracefully
                fatalError("DJAnalysisManager: failed to create analysis store: \(error)")
            }
        }

        // Create analyzer with the cache store
        analyzer = DJLocalAnalyzer(store: store, options: .default)
    }

    // MARK: - Public API

    /// Analyzes an audio file and returns BPM, beat offset, and confidence.
    /// Results are automatically cached to disk.
    ///
    /// - Parameters:
    ///   - url: Local file URL of the downloaded audio file.
    ///   - trackId: Unique identifier for the track (used for cache key).
    /// - Returns: Analysis result with BPM, beat phase, and confidence metrics.
    func analyze(url: URL, trackId: String) async throws -> DJAnalysisResult {
        logDebug(.dj, "DJAnalysisManager: analyzing track \(trackId)")
        let result = try await analyzer.analyze(url: url, trackId: trackId)
        logInfo(.dj, "DJAnalysisManager: analyzed \(trackId) - BPM: \(String(format: "%.1f", result.bpm)), confidence: \(String(format: "%.2f", result.confidence))")
        return result
    }

    /// Checks if analysis results exist in cache for a track.
    /// - Parameters:
    ///   - url: Local file URL of the audio file.
    ///   - trackId: Unique identifier for the track.
    /// - Returns: Cached analysis result if available and valid, nil otherwise.
    func getCachedAnalysis(url: URL, trackId: String) async -> DJAnalysisResult? {
        guard let fileIdentity = FileIdentity.from(url: url) else {
            return nil
        }
        return await store.get(trackId: trackId, fileIdentity: fileIdentity)
    }

    /// Returns cache statistics for debugging.
    func cacheStats() async -> (hits: Int, misses: Int, puts: Int) {
        let hits = await store.hitCount
        let misses = await store.missCount
        let puts = await store.putCount
        return (hits, misses, puts)
    }

    /// Clears all cached analysis results.
    func clearCache() async {
        await store.clearAll()
        logInfo(.dj, "DJAnalysisManager: cache cleared")
    }
}
