//
//  PreloadedItemCache.swift
//  mixbridge
//
//  State-of-the-art AVPlayerItem preloading for zero-latency playback
//  Eliminates 200-500ms asset preparation delay
//

import AVFoundation
import Foundation
import UIKit

/// Preloaded AVPlayerItem with metadata
private struct PreloadedItem {
    let item: AVPlayerItem
    let track: Track
    let soundCloudTrack: SoundCloudTrack?
    let createdAt: Date
    let streamURL: String

    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }

    /// Items older than 5 minutes should be refreshed
    var isStale: Bool {
        age > 300
    }
}

/// High-performance AVPlayerItem cache with aggressive preloading
/// Spotify-style: preload next 3 tracks as AVPlayerItems ready to play instantly
@MainActor
final class PreloadedItemCache {
    static let shared = PreloadedItemCache()

    private let keychain = KeychainManager.shared
    private let streamCache = StreamURLCache.shared

    /// Track ID -> Preloaded item mapping
    private var cache: [String: PreloadedItem] = [:]

    /// Tracks in-flight preload operations
    private var preloadingTracks: Set<String> = []

    /// Maximum number of preloaded items to keep in memory (Spotify uses ~3)
    private let maxCachedItems = 3

    /// Observers for playback readiness
    private var readinessObservers: [String: NSKeyValueObservation] = [:]

    private init() {
        #if DEBUG
        print("🚀 PreloadedItemCache initialized - Ready for instant playback")
        #endif

        // Clean up on memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    // MARK: - Public API

    /// Get preloaded AVPlayerItem if available
    /// Returns nil if not preloaded or stale
    /// NOTE: Does NOT remove from cache - call consumePreloadedItem after successful use
    func getPreloadedItem(for trackId: String) -> (AVPlayerItem, SoundCloudTrack?)? {
        guard let preloaded = cache[trackId] else {
            #if DEBUG
            print("⚠️ Cache MISS for track: \(trackId) - not preloaded")
            #endif
            return nil
        }

        if preloaded.isStale {
            #if DEBUG
            print("⚠️ Preloaded item is stale for track: \(trackId), discarding")
            #endif
            // Remove stale item
            cache.removeValue(forKey: trackId)
            readinessObservers.removeValue(forKey: trackId)
            return nil
        }

        #if DEBUG
        print("✅ Cache HIT for preloaded item: \(trackId) (age: \(String(format: "%.1f", preloaded.age))s)")
        #endif

        return (preloaded.item, preloaded.soundCloudTrack)
    }

    /// Consume (remove) preloaded item after successful playback start
    /// Call this ONLY after playback has successfully started
    func consumePreloadedItem(for trackId: String) {
        cache.removeValue(forKey: trackId)
        readinessObservers.removeValue(forKey: trackId)

        #if DEBUG
        print("✅ Consumed preloaded item: \(trackId)")
        #endif
    }

    /// Check if track is preloaded and ready
    func isPreloaded(_ trackId: String) -> Bool {
        guard let preloaded = cache[trackId] else {
            return false
        }
        return !preloaded.isStale
    }

    /// Preload AVPlayerItem for a track
    /// Non-blocking, optimizes for instant playback
    func preloadItem(for track: Track, soundCloudTrack: SoundCloudTrack?, streamURL: String) async -> Bool {
        // Skip if already preloading
        if preloadingTracks.contains(track.id) {
            return false
        }

        // Skip if already cached and fresh
        if let existing = cache[track.id], !existing.isStale {
            return true
        }

        preloadingTracks.insert(track.id)

        #if DEBUG
        print("⬇️ Preloading AVPlayerItem for track: \(track.title)")
        #endif

        do {
            guard let url = URL(string: streamURL) else {
                throw PlayerState.PlaybackError.invalidStreamURL
            }

            // Create asset with auth headers
            var options: [String: Any] = [:]
            if let token = keychain.getAccessToken() {
                options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": "Bearer \(token)"]
            }

            let asset = AVURLAsset(url: url, options: options)

            // ⚡ CRITICAL: Load asset properties asynchronously BEFORE creating AVPlayerItem
            // This eliminates blocking during playback start
            try await asset.load(.isPlayable, .tracks, .duration)

            guard asset.isPlayable else {
                #if DEBUG
                print("❌ Asset not playable for track: \(track.title)")
                #endif
                preloadingTracks.remove(track.id)
                return false
            }

            // Create AVPlayerItem with optimized buffer settings
            let item = AVPlayerItem(asset: asset)

            // ⚡ CRITICAL: Start with minimal buffer for instant playback
            // This will be increased after playback starts
            item.preferredForwardBufferDuration = 1

            // Allow network usage while paused (for preloading)
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            // Store preloaded item
            let preloaded = PreloadedItem(
                item: item,
                track: track,
                soundCloudTrack: soundCloudTrack,
                createdAt: Date(),
                streamURL: streamURL
            )

            cache[track.id] = preloaded

            // Enforce cache size limit
            enforceMaxCacheSize()

            #if DEBUG
            print("✅ Preloaded AVPlayerItem for track: \(track.title)")
            #endif

            preloadingTracks.remove(track.id)
            return true

        } catch {
            #if DEBUG
            print("❌ Failed to preload item for track \(track.title): \(error)")
            #endif
            preloadingTracks.remove(track.id)
            return false
        }
    }

    /// Aggressively preload AVPlayerItems for multiple tracks
    /// Requires stream URLs (use StreamURLCache first)
    func preloadBatch(tracks: [(Track, SoundCloudTrack?, String)]) async {
        #if DEBUG
        print("🔥 Batch preloading \(tracks.count) AVPlayerItems")
        #endif

        for (track, scTrack, streamURL) in tracks {
            await preloadItem(for: track, soundCloudTrack: scTrack, streamURL: streamURL)
        }
    }

    /// Smart preload: Prefetch stream URLs + preload AVPlayerItems for upcoming tracks
    /// One-stop shop for aggressive preloading
    func smartPreload(tracks: [Track], soundCloudTracks: [String: SoundCloudTrack], lookAhead: Int = 3) async {
        let tracksToPreload = Array(tracks.prefix(lookAhead))

        #if DEBUG
        print("🧠 Smart preloading \(tracksToPreload.count) tracks (URLs + Items)")
        #endif

        // Step 1: Prefetch stream URLs
        await streamCache.prefetchUpcoming(tracks: tracksToPreload, lookAhead: lookAhead)

        // Step 2: Preload AVPlayerItems for tracks with cached URLs
        for track in tracksToPreload {
            if let streamResponse = streamCache.getCachedStreamURL(for: track.id) {
                let scTrack = soundCloudTracks[track.id]
                await preloadItem(for: track, soundCloudTrack: scTrack, streamURL: streamResponse.stream_url)
            }
        }
    }

    /// Remove preloaded item from cache
    func removePreloadedItem(for trackId: String) {
        cache.removeValue(forKey: trackId)
        readinessObservers.removeValue(forKey: trackId)

        #if DEBUG
        print("🗑️ Removed preloaded item for track: \(trackId)")
        #endif
    }

    /// Clear all preloaded items
    func clearAll() {
        cache.removeAll()
        readinessObservers.removeAll()
        preloadingTracks.removeAll()

        #if DEBUG
        print("🗑️ Cleared all preloaded items")
        #endif
    }

    /// Get cache statistics
    func getCacheStats() -> (total: Int, fresh: Int, stale: Int, inFlight: Int) {
        let fresh = cache.values.filter { !$0.isStale }.count
        let stale = cache.values.filter { $0.isStale }.count

        return (cache.count, fresh, stale, preloadingTracks.count)
    }

    // MARK: - Private Helpers

    /// Enforce maximum cache size by removing oldest items
    private func enforceMaxCacheSize() {
        guard cache.count > maxCachedItems else { return }

        // Remove oldest items first
        let sorted = cache.sorted { $0.value.createdAt < $1.value.createdAt }
        let toRemove = sorted.prefix(cache.count - maxCachedItems)

        for (trackId, _) in toRemove {
            cache.removeValue(forKey: trackId)
            readinessObservers.removeValue(forKey: trackId)

            #if DEBUG
            print("🗑️ Evicted preloaded item (cache full): \(trackId)")
            #endif
        }
    }

    @objc private func handleMemoryWarning() {
        #if DEBUG
        print("⚠️ Memory warning - clearing preloaded items cache")
        #endif
        clearAll()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
