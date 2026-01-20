//
//  StreamURLCache.swift
//  mixbridge
//
//  State-of-the-art stream URL caching for instant playback
//  Aggressively prefetches stream URLs to eliminate network latency
//

import Foundation

/// Cached stream URL with expiration tracking
private struct CachedStream: Sendable {
    let url: String
    let streamType: String
    let accessToken: String  // OAuth token for direct CDN access (empty for Spotify)
    let cachedAt: Date
    let expiresAt: Date
    let isSpotify: Bool

    nonisolated var isExpired: Bool {
        Date() > expiresAt
    }

    nonisolated var isExpiringSoon: Bool {
        // Spotify URLs expire in ~6 hours, so use 5 minute buffer
        // SoundCloud URLs expire in ~5 minutes, so use 1 minute buffer
        let buffer: TimeInterval = isSpotify ? 300 : 60
        return Date().addingTimeInterval(buffer) > expiresAt
    }

    nonisolated init(url: String, streamType: String, accessToken: String, cachedAt: Date, expiresAt: Date, isSpotify: Bool = false) {
        self.url = url
        self.streamType = streamType
        self.accessToken = accessToken
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
        self.isSpotify = isSpotify
    }
}

/// Stream URL cache errors
enum StreamCacheError: LocalizedError {
    case noStreamAvailable

    var errorDescription: String? {
        switch self {
        case .noStreamAvailable:
            return "No stream available for this track"
        }
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
    private let spotifyService = SpotifyStreamService.shared

    /// Track ID -> Cached stream mapping
    private var cache: [String: CachedStream] = [:]

    /// Track ID -> in-flight fetch task (dedupes concurrent callers)
    private var inFlight: [String: Task<CachedStreamData, Error>] = [:]

    /// Pending prefetch queue (rate-limited to avoid flooding network/server)
    private var pendingPrefetch: [(trackId: String, spotifyUrl: String?)] = []
    private var pendingPrefetchSet: Set<String> = []
    private var prefetchWorker: Task<Void, Never>?

    /// Cap queued prefetches to avoid runaway work from list scrolling
    private let maxQueuedPrefetches = 50

    /// SoundCloud HLS URLs expire after ~5 minutes (signed Policy + Signature)
    /// Cache for 3 minutes to leave buffer before expiration
    private let soundCloudExpiryInterval: TimeInterval = 180

    /// Spotify stream URLs expire after ~6 hours
    /// Cache for 5.5 hours to leave buffer before expiration
    private let spotifyExpiryInterval: TimeInterval = 19800

    private init() {
        logDebug(.cache, "StreamURLCache initialized")
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
            enqueuePrefetch(trackId: trackId, spotifyUrl: nil)
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
    /// Uses Convex action for SoundCloud, SpotifyStreamService for Spotify
    func prefetchStreamURL(for trackId: String, spotifyUrl: String? = nil) {
        enqueuePrefetch(trackId: trackId, spotifyUrl: spotifyUrl)
    }

    /// Aggressively prefetch stream URLs for multiple tracks
    /// Prefetch next 3-5 tracks in queue
    func prefetchBatch(trackIds: [String], spotifyUrls: [String: String] = [:], priority: TaskPriority = .utility) {
        logDebug(.cache, "Batch prefetching \(trackIds.count) tracks")

        for trackId in trackIds {
            enqueuePrefetch(trackId: trackId, spotifyUrl: spotifyUrls[trackId])
        }
    }

    /// Prefetch stream URLs for upcoming tracks in queue
    /// Looks ahead N tracks (default: 3)
    func prefetchUpcoming(tracks: [Track], spotifyUrls: [String: String] = [:], lookAhead: Int = 3) {
        let trackIds = tracks.prefix(lookAhead).map { $0.id }
        prefetchBatch(trackIds: trackIds, spotifyUrls: spotifyUrls)
    }

    /// Prefetch current track + neighbors (previous + next N tracks)
    /// Useful for queue browsing and instant playback
    func prefetchTrackAndNeighbors(currentIndex: Int, queue: [Track], spotifyUrls: [String: String] = [:], lookAhead: Int = 3) {
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

        prefetchBatch(trackIds: trackIds, spotifyUrls: spotifyUrls, priority: .userInitiated)
    }

    /// Clear expired entries from cache
    func cleanupExpired() {
        let before = cache.count
        cache = cache.filter { !$0.value.isExpired }
        let removed = before - cache.count

        if removed > 0 {
            logDebug(.cache, "Cleaned up \(removed) expired cache entries")
        }
    }

    /// Clear all cached URLs (useful on memory warning or logout)
    func clearAll() {
        cache.removeAll()
        inFlight.removeAll()
        pendingPrefetch.removeAll()
        pendingPrefetchSet.removeAll()
        prefetchWorker?.cancel()
        prefetchWorker = nil

        logDebug(.cache, "Cleared all cached stream URLs")
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
        pendingPrefetch.removeAll { $0.trackId == trackId }

        logDebug(.cache, "Force refreshing stream URL for track: \(trackId)")

        do {
            let stream = try await ensureStream(for: trackId, priority: .userInitiated, forceRefresh: true)

            logDebug(.cache, "Force refresh successful for track: \(trackId)")

            return stream
        } catch {
            logError(.cache, "Force refresh failed for track \(trackId): \(error)")
            return nil
        }
    }

    /// Invalidate cache entry for a track (without fetching new)
    func invalidate(trackId: String) {
        cache.removeValue(forKey: trackId)

        logDebug(.cache, "Invalidated cache for track: \(trackId)")
    }

    /// Ensure a stream is available (used by actual playback start).
    /// - Note: Returns cached value if fresh; otherwise fetches and updates cache.
    /// - Parameters:
    ///   - trackId: The track ID to fetch stream for
    ///   - spotifyUrl: Optional Spotify URL (if nil and user is on Spotify, constructs from trackId)
    ///   - priority: Task priority for the fetch
    ///   - forceRefresh: If true, bypasses cache and fetches fresh URL
    func ensureStream(
        for trackId: String,
        spotifyUrl: String? = nil,
        priority: TaskPriority = .userInitiated,
        forceRefresh: Bool = false
    ) async throws -> CachedStreamData {
        if !forceRefresh, let cached = getCachedStream(for: trackId), !cached.url.isEmpty {
            return cached
        }

        if let existingTask = inFlight[trackId] {
            return try await existingTask.value
        }

        // Determine if we should use Spotify service
        // If spotifyUrl is provided, use it. Otherwise, check if user is on Spotify provider
        // AND the track ID looks like a Spotify ID (base62, ~22 chars with letters).
        // SoundCloud IDs are purely numeric, so we can distinguish them.
        let isSpotifyUser = await MainActor.run { AuthManager.shared.currentProvider == .spotify }
        let looksLikeSpotifyId = trackId.contains(where: { $0.isLetter }) && trackId.count >= 20 && trackId.count <= 24
        let effectiveSpotifyUrl: String? = spotifyUrl ?? (isSpotifyUser && looksLikeSpotifyId ? "https://open.spotify.com/track/\(trackId)" : nil)
        let isSpotify = effectiveSpotifyUrl != nil

        logInfo(.cache, "[StreamCache] ensureStream: trackId=\(trackId), provider=\(isSpotifyUser ? "spotify" : "soundcloud"), looksLikeSpotifyId=\(looksLikeSpotifyId), usingSpotifyService=\(isSpotify), spotifyUrl=\(effectiveSpotifyUrl ?? "nil")")

        let task = Task<CachedStreamData, Error>(priority: priority) { [convexService, spotifyService] in
            if let spotifyUrl = effectiveSpotifyUrl {
                logInfo(.cache, "[StreamCache] Fetching via SpotifyStreamService: \(spotifyUrl)")
                let response = try await spotifyService.getStreamURL(spotifyUrl: spotifyUrl)
                logInfo(.cache, "[StreamCache] Spotify stream OK: format=\(response.format)")
                return CachedStreamData(
                    url: response.streamURL,
                    streamType: response.format,
                    accessToken: ""
                )
            } else {
                logInfo(.cache, "[StreamCache] Fetching via Convex: trackId=\(trackId)")
                do {
                    let response = try await convexService.getDirectStreamURL(trackId: trackId)
                    logInfo(.cache, "[StreamCache] Convex stream OK: type=\(response.stream_type)")
                    return CachedStreamData(
                        url: response.stream_url,
                        streamType: response.stream_type,
                        accessToken: response.access_token
                    )
                } catch {
                    logError(.cache, "[StreamCache] Convex stream FAILED for trackId=\(trackId): \(error)")
                    throw error
                }
            }
        }

        inFlight[trackId] = task
        defer { inFlight.removeValue(forKey: trackId) }

        let stream = try await task.value

        let expiryInterval = isSpotify ? spotifyExpiryInterval : soundCloudExpiryInterval
        let cached = CachedStream(
            url: stream.url,
            streamType: stream.streamType,
            accessToken: stream.accessToken,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(expiryInterval),
            isSpotify: isSpotify
        )

        cache[trackId] = cached
        return stream
    }

    // MARK: - Prefetch Queue (rate-limited)

    private func enqueuePrefetch(trackId: String, spotifyUrl: String?) {
        cleanupExpired()

        // Skip if already cached or in-flight
        if cache[trackId] != nil || inFlight[trackId] != nil {
            return
        }

        guard pendingPrefetch.count < maxQueuedPrefetches else { return }
        guard !pendingPrefetchSet.contains(trackId) else { return }

        pendingPrefetch.append((trackId: trackId, spotifyUrl: spotifyUrl))
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
            guard let item = dequeuePrefetch() else {
                return
            }

            do {
                _ = try await ensureStream(for: item.trackId, spotifyUrl: item.spotifyUrl, priority: .utility)
                logDebug(.cache, "Prefetched stream URL for track: \(item.trackId)")
            } catch {
                logError(.cache, "Prefetch failed for track \(item.trackId): \(error)")
            }
        }
    }

    private func dequeuePrefetch() -> (trackId: String, spotifyUrl: String?)? {
        guard !pendingPrefetch.isEmpty else { return nil }
        let next = pendingPrefetch.removeFirst()
        pendingPrefetchSet.remove(next.trackId)
        return next
    }
}
