import CryptoKit
import Foundation

/// File-based persistent cache for analysis results.
/// Stores JSON files in a specified directory, keyed by track ID.
public actor DJFileAnalysisStore: DJAnalysisStore {
    /// Directory where cache files are stored.
    private let cacheDirectory: URL

    /// JSON encoder for serialization.
    private let encoder: JSONEncoder

    /// JSON decoder for deserialization.
    private let decoder: JSONDecoder

    /// Counter for cache hits - useful for testing.
    public private(set) var hitCount: Int = 0

    /// Counter for cache misses - useful for testing.
    public private(set) var missCount: Int = 0

    /// Counter for analysis operations (put calls) - useful for testing.
    public private(set) var putCount: Int = 0

    /// Creates a file-based analysis store.
    /// - Parameter cacheDirectory: Directory to store cache files. Created if it doesn't exist.
    public init(cacheDirectory: URL) throws {
        self.cacheDirectory = cacheDirectory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Ensure cache directory exists
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Creates a store using the default cache location in Application Support.
    public static func defaultStore() throws -> DJFileAnalysisStore {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let cacheDir = appSupport.appendingPathComponent("MixBridgeDJ/AnalysisCache", isDirectory: true)
        return try DJFileAnalysisStore(cacheDirectory: cacheDir)
    }

    public func get(trackId: String, fileIdentity: FileIdentity) async -> DJAnalysisResult? {
        let fileURL = cacheFileURL(for: trackId)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            missCount += 1
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entry = try decoder.decode(DJAnalysisCacheEntry.self, from: data)

            // Validate file identity matches
            guard entry.matches(identity: fileIdentity) else {
                missCount += 1
                // File changed since analysis - invalidate stale cache
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            hitCount += 1
            return entry.result

        } catch {
            missCount += 1
            // Corrupted cache file - remove it
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    public func put(result: DJAnalysisResult, trackId: String, fileIdentity: FileIdentity) async {
        putCount += 1

        let entry = DJAnalysisCacheEntry(
            trackId: trackId,
            fileIdentity: fileIdentity,
            result: result
        )

        let fileURL = cacheFileURL(for: trackId)

        do {
            let data = try encoder.encode(entry)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache write failure is non-fatal.
        }
    }

    public func invalidate(trackId: String) async {
        let fileURL = cacheFileURL(for: trackId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func clearAll() async {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            for url in contents where url.pathExtension == "json" {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            // Ignore errors during cleanup
        }

        // Reset counters
        hitCount = 0
        missCount = 0
        putCount = 0
    }

    /// Resets all counters (for testing).
    public func resetCounters() {
        hitCount = 0
        missCount = 0
        putCount = 0
    }

    // MARK: - Private Helpers

    /// Generates a safe filename from a track ID.
    /// Uses SHA256 for long track IDs to ensure deterministic filenames across app launches.
    private func cacheFileURL(for trackId: String) -> URL {
        // Create a safe filename by replacing filesystem-unsafe characters
        let safeFilename = trackId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // Use SHA256 hash for very long track IDs to keep filenames manageable
        // Note: We use SHA256 instead of Swift's hashValue because hashValue is
        // randomly seeded per process and not deterministic across app launches.
        let filename: String
        if safeFilename.count > 200 {
            let hash = sha256Hash(of: trackId)
            filename = "track_\(hash)"
        } else {
            filename = safeFilename
        }

        return cacheDirectory.appendingPathComponent("\(filename).json")
    }

    /// Computes a deterministic SHA256 hash of a string, returning a hex string prefix.
    /// Uses first 16 characters (64 bits) which is sufficient for cache key uniqueness.
    private func sha256Hash(of string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        // Take first 8 bytes (16 hex chars) for a reasonably short but unique filename
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
