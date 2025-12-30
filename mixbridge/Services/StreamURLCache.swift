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

    nonisolated var isExpired: Bool {
        Date() > expiresAt
    }

    nonisolated var isExpiringSoon: Bool {
        // Consider expiring soon if within 1 minute of expiry
        Date().addingTimeInterval(60) > expiresAt
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
actor StreamURLCache {
    static let shared = StreamURLCache()

    private let convexService = ConvexService.shared

    /// Track ID -> Cached stream mapping
    private var cache: [String: CachedStream] = [:]

    /// Track ID -> in-flight fetch task (dedupes concurrent callers)
    private var inFlight: [String: Task<CachedStreamData, Error>] = [:]

    /// Pending prefetch queue (rate-limited to avoid flooding network/server)
    private var pendingPrefetch: [String] = []
    private var pendingPrefetchSet: Set<String> = []
    private var prefetchWorker: Task<Void, Never>?

    /// Cap queued prefetches to avoid runaway work from list scrolling
    private let maxQueuedPrefetches = 50

    /// SoundCloud HLS URLs expire after ~5 minutes (signed Policy + Signature)
    /// Cache for 3 minutes to leave buffer before expiration
    private let defaultExpiryInterval: TimeInterval = 180

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
            enqueuePrefetch(trackId: trackId)
        }

        return CachedStreamData(
            url: cached.url,
            streamType: cached.streamType,
            accessToken: cached.accessToken
        )
    }

    /// Check if cached stream will expire before a given deadline
    /// Used by Mix Mode to determine if a just-in-time refresh is needed
    /// - Parameters:
    ///   - trackId: The track to check
    ///   - deadline: The deadline to check against (e.g., now + crossfadeSeconds + 15s)
    /// - Returns: true if stream is cached but will expire before deadline,
    ///            false if not cached or will still be valid
    func isStreamExpiring(for trackId: String, before deadline: Date) -> Bool {
        guard let cached = cache[trackId] else {
            // Not cached - caller should fetch fresh
            return false
        }
        // Check if cached stream expires before the deadline
        return cached.expiresAt < deadline
    }

    /// Check if a stream is cached and fresh (not expiring soon)
    func hasValidCachedStream(for trackId: String) -> Bool {
        guard let cached = cache[trackId] else { return false }
        return !cached.isExpired && !cached.isExpiringSoon
    }

    /// Prefetch stream URL for a track (fire and forget)
    /// Uses Convex action for direct CDN URLs
    func prefetchStreamURL(for trackId: String) {
        enqueuePrefetch(trackId: trackId)
    }

    /// Aggressively prefetch stream URLs for multiple tracks
    /// Spotify-style: prefetch next 3-5 tracks in queue
    func prefetchBatch(trackIds: [String], priority: TaskPriority = .utility) {
        #if DEBUG
        print("🔥 Batch prefetching \(trackIds.count) tracks")
        #endif

        for trackId in trackIds {
            enqueuePrefetch(trackId: trackId)
        }
    }

    /// Prefetch stream URLs for upcoming tracks in queue
    /// Looks ahead N tracks (default: 3, Spotify uses 3)
    func prefetchUpcoming(tracks: [Track], lookAhead: Int = 3) {
        let trackIds = tracks.prefix(lookAhead).map { $0.id }
        prefetchBatch(trackIds: trackIds)
    }

    /// Prefetch current track + neighbors (previous + next N tracks)
    /// Useful for queue browsing and instant playback
    func prefetchTrackAndNeighbors(currentIndex: Int, queue: [Track], lookAhead: Int = 3) {
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

        prefetchBatch(trackIds: trackIds, priority: .userInitiated)
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
        inFlight.removeAll()
        pendingPrefetch.removeAll()
        pendingPrefetchSet.removeAll()
        prefetchWorker?.cancel()
        prefetchWorker = nil

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
        inFlight[trackId]?.cancel()
        inFlight.removeValue(forKey: trackId)
        pendingPrefetchSet.remove(trackId)
        pendingPrefetch.removeAll { $0 == trackId }

        #if DEBUG
        print("🔄 Force refreshing stream URL for track: \(trackId)")
        #endif

        do {
            let stream = try await ensureStream(for: trackId, priority: .userInitiated, forceRefresh: true)

            #if DEBUG
            print("✅ Force refresh successful for track: \(trackId)")
            #endif

            return stream
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

    /// Ensure a stream is available (used by actual playback start).
    /// - Note: Returns cached value if fresh; otherwise fetches and updates cache.
    func ensureStream(
        for trackId: String,
        priority: TaskPriority = .userInitiated,
        forceRefresh: Bool = false
    ) async throws -> CachedStreamData {
        if !forceRefresh, let cached = getCachedStream(for: trackId), cached.url.isEmpty == false {
            return cached
        }

        if let existingTask = inFlight[trackId] {
            return try await existingTask.value
        }

        let task = Task<CachedStreamData, Error>(priority: priority) { [convexService] in
            let response = try await convexService.getDirectStreamURL(trackId: trackId)
            return CachedStreamData(
                url: response.stream_url,
                streamType: response.stream_type,
                accessToken: response.access_token
            )
        }

        inFlight[trackId] = task
        defer { inFlight.removeValue(forKey: trackId) }

        let stream = try await task.value

        let cached = CachedStream(
            url: stream.url,
            streamType: stream.streamType,
            accessToken: stream.accessToken,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(defaultExpiryInterval)
        )

        cache[trackId] = cached
        return stream
    }

    // MARK: - Prefetch Queue (rate-limited)

    private func enqueuePrefetch(trackId: String) {
        cleanupExpired()

        // Skip if already cached or in-flight
        if cache[trackId] != nil || inFlight[trackId] != nil {
            return
        }

        guard pendingPrefetch.count < maxQueuedPrefetches else { return }
        guard !pendingPrefetchSet.contains(trackId) else { return }

        pendingPrefetch.append(trackId)
        pendingPrefetchSet.insert(trackId)
        startPrefetchWorkerIfNeeded()
    }

    private func startPrefetchWorkerIfNeeded() {
        guard prefetchWorker == nil else { return }

        prefetchWorker = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runPrefetchWorker()
        }
    }

    private func runPrefetchWorker() async {
        defer {
            prefetchWorker = nil
        }

        while !Task.isCancelled {
            guard let trackId = dequeuePrefetch() else {
                return
            }

            do {
                _ = try await ensureStream(for: trackId, priority: .utility)
                #if DEBUG
                print("✅ Prefetched stream URL for track: \(trackId)")
                #endif
            } catch {
                #if DEBUG
                print("❌ Prefetch failed for track \(trackId): \(error)")
                #endif
            }
        }
    }

    private func dequeuePrefetch() -> String? {
        guard !pendingPrefetch.isEmpty else { return nil }
        let next = pendingPrefetch.removeFirst()
        pendingPrefetchSet.remove(next)
        return next
    }
}
