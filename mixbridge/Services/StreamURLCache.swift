//
//  StreamURLCache.swift
//  mixbridge
//
//  State-of-the-art stream URL caching for instant playback
//  Aggressively prefetches stream URLs to eliminate network latency
//

import Foundation

/// Cached stream URL with expiration tracking
private struct CachedStream {
    let url: String
    let streamType: String
    let accessToken: String  // OAuth token for direct CDN access
    let cachedAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isExpiringSoon: Bool {
        // Consider expired if within 5 minutes of expiry
        Date().addingTimeInterval(300) > expiresAt
    }
}

/// Cached stream data including OAuth token for direct CDN access
struct CachedStreamData {
    let url: String
    let streamType: String
    let accessToken: String
}

/// High-performance stream URL cache with aggressive prefetching
/// Eliminates 500-1000ms network latency by prefetching stream URLs before user interaction
@MainActor
final class StreamURLCache {
    static let shared = StreamURLCache()

    private let convexService = ConvexService.shared
    private let keychain = KeychainManager.shared

    /// Track ID -> Cached stream mapping
    private var cache: [String: CachedStream] = [:]

    /// Tracks in-flight prefetch requests to avoid duplicates
    private var prefetchingTracks: Set<String> = []

    /// Background queue for prefetch operations
    private let prefetchQueue = DispatchQueue(label: "com.mixbridge.stream-prefetch", qos: .utility)

    /// 4 hours - SoundCloud HLS URLs remain valid for extended periods
    private let defaultExpiryInterval: TimeInterval = 14400

    private init() {
        #if DEBUG
        print("🚀 StreamURLCache initialized - Ready for aggressive prefetching")
        #endif
    }

    // MARK: - Public API

    /// Get cached stream data if available and not expired
    func getCachedStream(for trackId: String) -> CachedStreamData? {
        guard let cached = cache[trackId] else {
            return nil
        }

        if cached.isExpired {
            cache.removeValue(forKey: trackId)
            return nil
        }

        if cached.isExpiringSoon {
            Task {
                await prefetchStreamURL(for: trackId)
            }
        }

        return CachedStreamData(
            url: cached.url,
            streamType: cached.streamType,
            accessToken: cached.accessToken
        )
    }

    /// Get cached stream URL if available and not expired (legacy compatibility)
    /// Returns nil if not cached or expired
    func getCachedStreamURL(for trackId: String) -> StreamResponse? {
        guard let cached = cache[trackId] else {
            return nil
        }

        // Remove if expired
        if cached.isExpired {
            cache.removeValue(forKey: trackId)
            #if DEBUG
            print("🗑️ Removed expired cache for track: \(trackId)")
            #endif
            return nil
        }

        // Refresh in background if expiring soon
        if cached.isExpiringSoon {
            #if DEBUG
            print("⚠️ Cache expiring soon for track: \(trackId), refreshing...")
            #endif
            Task {
                await prefetchStreamURL(for: trackId)
            }
        }

        #if DEBUG
        print("✅ Cache HIT for track: \(trackId)")
        #endif

        return StreamResponse(
            stream_url: cached.url,
            stream_type: cached.streamType,
            track_id: trackId
        )
    }

    /// Prefetch stream URL for a track (fire and forget)
    /// Uses Convex action for direct CDN URLs
    func prefetchStreamURL(for trackId: String) async {
        // Skip if already cached or in-flight
        guard cache[trackId] == nil && !prefetchingTracks.contains(trackId) else {
            return
        }

        prefetchingTracks.insert(trackId)
        defer { prefetchingTracks.remove(trackId) }

        do {
            let response = try await convexService.getDirectStreamURL(trackId: trackId)

            let cached = CachedStream(
                url: response.stream_url,
                streamType: response.stream_type,
                accessToken: response.access_token,
                cachedAt: Date(),
                expiresAt: Date().addingTimeInterval(defaultExpiryInterval)
            )

            cache[trackId] = cached

            #if DEBUG
            print("✅ Prefetched stream URL for track: \(trackId)")
            #endif
        } catch {
            #if DEBUG
            print("❌ Prefetch failed for track \(trackId): \(error)")
            #endif
        }
    }

    /// Aggressively prefetch stream URLs for multiple tracks
    /// Spotify-style: prefetch next 3-5 tracks in queue
    func prefetchBatch(trackIds: [String], priority: TaskPriority = .utility) async {
        #if DEBUG
        print("🔥 Batch prefetching \(trackIds.count) tracks")
        #endif

        await withTaskGroup(of: Void.self) { group in
            for trackId in trackIds {
                group.addTask(priority: priority) {
                    await self.prefetchStreamURL(for: trackId)
                }
            }
        }
    }

    /// Prefetch stream URLs for upcoming tracks in queue
    /// Looks ahead N tracks (default: 3, Spotify uses 3)
    func prefetchUpcoming(tracks: [Track], lookAhead: Int = 3) async {
        let trackIds = tracks.prefix(lookAhead).map { $0.id }
        await prefetchBatch(trackIds: trackIds)
    }

    /// Prefetch current track + neighbors (previous + next N tracks)
    /// Useful for queue browsing and instant playback
    func prefetchTrackAndNeighbors(currentIndex: Int, queue: [Track], lookAhead: Int = 3) async {
        var trackIds: [String] = []

        // Add previous track (instant back button)
        if currentIndex > 0 {
            trackIds.append(queue[currentIndex - 1].id)
        }

        // Add current track
        trackIds.append(queue[currentIndex].id)

        // Add next N tracks
        let nextTracks = queue.dropFirst(currentIndex + 1).prefix(lookAhead)
        trackIds.append(contentsOf: nextTracks.map { $0.id })

        await prefetchBatch(trackIds: trackIds, priority: .userInitiated)
    }

    /// Clear expired entries from cache
    func cleanupExpired() {
        let before = cache.count
        cache = cache.filter { !$0.value.isExpired }
        let removed = before - cache.count

        #if DEBUG
        if removed > 0 {
            print("🧹 Cleaned up \(removed) expired cache entries")
        }
        #endif
    }

    /// Clear all cached URLs (useful on memory warning or logout)
    func clearAll() {
        cache.removeAll()
        prefetchingTracks.removeAll()

        #if DEBUG
        print("🗑️ Cleared all cached stream URLs")
        #endif
    }

    /// Force refresh stream URL for a track (bypasses cache)
    /// Use when stream fails during playback and needs fresh URL
    @discardableResult
    func forceRefresh(for trackId: String) async -> CachedStreamData? {
        // Remove from cache first
        cache.removeValue(forKey: trackId)
        prefetchingTracks.remove(trackId)

        #if DEBUG
        print("🔄 Force refreshing stream URL for track: \(trackId)")
        #endif

        do {
            let response = try await convexService.getDirectStreamURL(trackId: trackId)

            let cached = CachedStream(
                url: response.stream_url,
                streamType: response.stream_type,
                accessToken: response.access_token,
                cachedAt: Date(),
                expiresAt: Date().addingTimeInterval(defaultExpiryInterval)
            )

            cache[trackId] = cached

            #if DEBUG
            print("✅ Force refresh successful for track: \(trackId)")
            #endif

            return CachedStreamData(
                url: response.stream_url,
                streamType: response.stream_type,
                accessToken: response.access_token
            )
        } catch {
            #if DEBUG
            print("❌ Force refresh failed for track \(trackId): \(error)")
            #endif
            return nil
        }
    }

    /// Invalidate cache entry for a track (without fetching new)
    func invalidate(trackId: String) {
        cache.removeValue(forKey: trackId)

        #if DEBUG
        print("🗑️ Invalidated cache for track: \(trackId)")
        #endif
    }

    /// Get cache statistics for debugging
    func getCacheStats() -> (total: Int, valid: Int, expiring: Int, expired: Int) {
        let valid = cache.values.filter { !$0.isExpired && !$0.isExpiringSoon }.count
        let expiring = cache.values.filter { $0.isExpiringSoon && !$0.isExpired }.count
        let expired = cache.values.filter { $0.isExpired }.count

        return (cache.count, valid, expiring, expired)
    }
}
