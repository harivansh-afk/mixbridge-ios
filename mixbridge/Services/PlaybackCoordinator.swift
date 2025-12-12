//
//  PlaybackCoordinator.swift
//  mixbridge
//
//  State-of-the-art audio playback with instant startup and zero latency
//  Implements aggressive prefetching, preloading, and buffer optimization
//

import AVFoundation
import MediaPlayer
import SwiftUI
import Combine

@MainActor
protocol PlaybackCoordinatorDelegate: AnyObject {
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didUpdate snapshot: PlaybackSnapshot)
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didEncounter error: Error)
}

struct PlaybackSnapshot {
    let track: Track?
    let queueIndex: Int?
    let status: PlayerState.PlaybackStatus
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
}

private struct PlaybackContext: Equatable {
    let track: Track
    let soundCloudTrack: SoundCloudTrack?
    let queueIndex: Int?

    static func == (lhs: PlaybackContext, rhs: PlaybackContext) -> Bool {
        lhs.track.id == rhs.track.id && lhs.queueIndex == rhs.queueIndex
    }
}

@MainActor
final class PlaybackCoordinator: NSObject {
    static let shared = PlaybackCoordinator()

    weak var delegate: PlaybackCoordinatorDelegate?

    var autoplayEnabled: Bool = true

    private let queueManager = QueueManager.shared
    private let backendAPI = BackendAPI.shared
    private let keychain = KeychainManager.shared
    private let convexService = ConvexService.shared

    // ⚡ NEW: State-of-the-art caching services
    private let streamCache = StreamURLCache.shared
    private let itemCache = PreloadedItemCache.shared

    private let player = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var currentContext: PlaybackContext?
    private var nextPreloadedContext: PlaybackContext?
    private var nextPreloadedItem: AVPlayerItem?
    private var itemContextMap: [AVPlayerItem: PlaybackContext] = [:]

    /// Tracks whether the next track has been preloaded for the current track
    private var hasPreloadedForCurrentTrack = false

    /// ⚡ OPTIMIZED: Preload at 50% instead of 75% for better UX
    private let preloadTriggerProgress: Double = 0.50

    /// Cancellables for Combine observers
    private var cancellables = Set<AnyCancellable>()

    /// Track playback readiness for status updates
    private var readinessObservation: NSKeyValueObservation?

    private var status: PlayerState.PlaybackStatus = .idle {
        didSet {
            Task { @MainActor in
                publishSnapshot()
            }
        }
    }

    /// Prevent spam clicking on play button
    private var isPreparingPlayback = false

    /// Track recently failed tracks to prevent infinite retry loops
    private var recentlyFailedTracks: [String: Date] = [:]

    private override init() {
        super.init()

        // ⚡ CRITICAL: Disable automatic stall waiting for instant playback
        // This is the #1 most important optimization for reducing startup latency
        player.automaticallyWaitsToMinimizeStalling = false

        player.actionAtItemEnd = .advance
        addTimeObserver()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        #if DEBUG
        print("🚀 PlaybackCoordinator initialized with SOTA optimizations")
        print("   ✅ automaticallyWaitsToMinimizeStalling = false")
        print("   ✅ Preload trigger = 50%")
        print("   ✅ Stream URL caching enabled")
        print("   ✅ AVPlayerItem preloading enabled")
        #endif
    }

    // MARK: - Public Controls

    var hasLoadedItems: Bool {
        !player.items().isEmpty
    }

    func play(track: Track, soundCloudTrack: SoundCloudTrack?, queueIndex: Int?, startTime: Double? = nil) {
        // ⚡ CRITICAL: Prevent spam clicking
        guard !isPreparingPlayback else {
            #if DEBUG
            print("⚠️ Playback already in progress, ignoring duplicate request")
            #endif
            return
        }

        // ⚡ CRITICAL: Check if track recently failed
        if let failedDate = recentlyFailedTracks[track.id] {
            let timeSinceFailure = Date().timeIntervalSince(failedDate)
            if timeSinceFailure < 5.0 {
                #if DEBUG
                print("⚠️ Track \(track.title) recently failed (\(String(format: "%.1f", timeSinceFailure))s ago), skipping retry")
                #endif
                // Still allow retry after 5 seconds
                return
            } else {
                // Clear old failure
                recentlyFailedTracks.removeValue(forKey: track.id)
            }
        }

        let context = PlaybackContext(track: track, soundCloudTrack: soundCloudTrack, queueIndex: queueIndex)
        Task {
            await startPlayback(with: context, startTime: startTime)
        }
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        player.pause()
        status = .paused
        Task { @MainActor in
            publishSnapshot()
        }
    }

    func resume() {
        guard player.items().isEmpty == false else { return }
        player.play()
        status = .playing
        Task { @MainActor in
            publishSnapshot()
        }
    }

    func seek(to time: Double) {
        // ⚡ CRITICAL: Preserve playing state before seeking
        let wasPlaying = player.timeControlStatus == .playing

        let target = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        // Use zero tolerance for precise seeking
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }
            Task { @MainActor in
                // ⚡ CRITICAL: Restore playing state after seek
                if wasPlaying {
                    self.player.play()
                }

                self.publishSnapshot()

                #if DEBUG
                print("✅ Seek completed to \(String(format: "%.1f", time))s, restored playing: \(wasPlaying)")
                #endif
            }
        }
    }

    func setVolume(_ value: Double) {
        player.volume = Float(value)
    }

    func playNext(manual: Bool = false) {
        guard let currentContext else {
            if let first = queueManager.queueTracks.first {
                play(track: first, soundCloudTrack: queueManager.soundCloudTrack(for: first.id), queueIndex: 0)
            }
            return
        }

        if player.items().count > 1 {
            player.advanceToNextItem()
            adoptCurrentItemContext()
        } else if let next = queueManager.nextTrack(after: currentContext.queueIndex ?? queueManager.indexOfTrack(withId: currentContext.track.id) ?? -1) {
            play(track: next.track, soundCloudTrack: queueManager.soundCloudTrack(for: next.track.id), queueIndex: next.index)
        }

        if manual {
            HapticManager.selection()
        }
    }

    func playPrevious() {
        guard let currentContext else {
            playNext(manual: true)
            return
        }

        if let previous = queueManager.previousTrack(before: currentContext.queueIndex ?? queueManager.indexOfTrack(withId: currentContext.track.id) ?? 0) {
            play(track: previous.track, soundCloudTrack: queueManager.soundCloudTrack(for: previous.track.id), queueIndex: previous.index)
        } else {
            seek(to: 0)
        }
    }

    // MARK: - Playback Pipeline (SOTA Optimized)

    /// ⚡ OPTIMIZED: Instant playback with aggressive caching
    /// CRITICAL: Only updates currentContext AFTER successful playback start
    private func startPlayback(with context: PlaybackContext, startTime: Double? = nil) async {
        // ⚡ CRITICAL FIX: Set preparing flag to prevent spam
        isPreparingPlayback = true
        defer {
            isPreparingPlayback = false
        }

        // ⚡ CRITICAL FIX: Store pending context, don't update currentContext yet
        // This ensures UI shows actual playing track, not attempted track
        let pendingContext = context
        status = .loading

        #if DEBUG
        let startTime_debug = CFAbsoluteTimeGetCurrent()
        #endif

        do {
            // ⚡ STEP 1: Try to get preloaded AVPlayerItem (instant if cached)
            var playerItem: AVPlayerItem?
            var usedPreloadedItem = false

            if let (preloadedItem, _) = itemCache.getPreloadedItem(for: pendingContext.track.id) {
                #if DEBUG
                print("⚡ INSTANT PLAYBACK: Using preloaded AVPlayerItem")
                #endif
                playerItem = preloadedItem
                usedPreloadedItem = true
            } else {
                // ⚡ STEP 2: Fallback - fetch stream URL (try cache first)
                #if DEBUG
                print("⚠️ No preloaded item, fetching stream URL...")
                #endif
                playerItem = try await prepareItemOptimized(for: pendingContext)
            }

            guard let item = playerItem else {
                throw PlayerState.PlaybackError.invalidStreamURL
            }

            // Clear old items
            player.removeAllItems()
            itemContextMap.removeAll()
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            hasPreloadedForCurrentTrack = false

            // Insert new item
            player.insert(item, after: nil)
            itemContextMap[item] = pendingContext

            // Monitor playback readiness for smooth status transitions
            observePlaybackReadiness(for: item)

            // ⚡ CRITICAL FIX: Wait for item status to be ready before playing
            // This prevents HLS parsing errors (err=-12642) when using automaticallyWaitsToMinimizeStalling = false
            if item.status != .readyToPlay {
                #if DEBUG
                print("⏳ Waiting for item to be ready...")
                #endif

                // Wait up to 3 seconds for item to become ready
                let timeoutDate = Date().addingTimeInterval(3)
                while item.status == .unknown && Date() < timeoutDate {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }

                if item.status == .failed {
                    if let error = item.error {
                        throw error
                    }
                    throw PlayerState.PlaybackError.invalidStreamURL
                }
            }

            // Seek if needed
            if let startTime = startTime, startTime > 0 {
                await player.seek(to: CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
            }

            // ⚡ PLAY IMMEDIATELY - Now that item is ready
            player.play()

            // ⚡ CRITICAL FIX: Only NOW set currentContext after playback successfully started
            // This ensures UI is tightly coupled with actual playback state
            currentContext = pendingContext

            // Consume preloaded item only after successful use
            if usedPreloadedItem {
                itemCache.consumePreloadedItem(for: pendingContext.track.id)
            }

            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime_debug) * 1000
            print("⚡ Playback started in \(String(format: "%.0f", elapsed))ms")
            #endif

            // ⚡ OPTIMIZATION: Increase buffer after playback starts for smooth playback
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                item.preferredForwardBufferDuration = 8
                #if DEBUG
                print("✅ Increased buffer to 8s for smooth playback")
                #endif
            }

            // Log play to history
            if let userId = AuthManager.shared.currentUserId,
               autoplayEnabled,
               let scTrack = pendingContext.soundCloudTrack {
                Task {
                    do {
                        try await convexService.addPlay(userId: userId, track: scTrack)
                    } catch {
                        print("Failed to log play history: \(error)")
                    }
                }
            }

            // ⚡ AGGRESSIVE: Trigger preload earlier (50% instead of 75%)
            // This happens in time observer now

        } catch {
            // ⚡ CRITICAL: Track failure to prevent spam retries
            recentlyFailedTracks[pendingContext.track.id] = Date()

            // ⚡ CRITICAL: Don't update currentContext on failure
            // UI will continue showing the actual playing track (or idle state)
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)

            #if DEBUG
            print("❌ Playback failed for track \(pendingContext.track.title): \(error)")
            print("⏱️ Track marked as failed, retry blocked for 5 seconds")
            #endif
        }
    }

    /// ⚡ OPTIMIZED: Prepare AVPlayerItem with cache-first strategy
    private func prepareItemOptimized(for context: PlaybackContext) async throws -> AVPlayerItem {
        var streamURL: String?

        // Try cache first (instant if cached)
        if let cached = streamCache.getCachedStreamURL(for: context.track.id) {
            streamURL = cached.stream_url
            #if DEBUG
            print("✅ Using cached stream URL")
            #endif
        } else {
            // Fallback: fetch from backend
            #if DEBUG
            print("⬇️ Fetching stream URL from backend...")
            #endif
            let response = try await backendAPI.getStreamURL(trackId: context.track.id)
            streamURL = response.stream_url

            // Cache for next time
            await streamCache.prefetchStreamURL(for: context.track.id)
        }

        guard let urlString = streamURL, let url = URL(string: urlString) else {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        // Create asset with auth headers
        var options: [String: Any] = [:]
        if let token = keychain.getAccessToken() {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": "Bearer \(token)"]
        }

        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)

        // ⚡ CRITICAL: Start with minimal buffer (1s) for instant playback
        // This will be increased to 8s after playback starts
        item.preferredForwardBufferDuration = 1

        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        return item
    }

    /// ⚡ OPTIMIZED: Aggressive preloading of next track
    private func preloadNextItem(from context: PlaybackContext) async {
        guard let next = nextContext(after: context) else {
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            return
        }

        #if DEBUG
        print("🔥 Aggressively preloading next track: \(next.track.title)")
        #endif

        do {
            // Remove old preloaded item
            if let existingItem = nextPreloadedItem {
                player.remove(existingItem)
                itemContextMap.removeValue(forKey: existingItem)
            }

            // ⚡ STEP 1: Ensure stream URL is cached
            if streamCache.getCachedStreamURL(for: next.track.id) == nil {
                await streamCache.prefetchStreamURL(for: next.track.id)
            }

            // ⚡ STEP 2: Try to get preloaded AVPlayerItem
            var item: AVPlayerItem?

            if let (preloadedItem, _) = itemCache.getPreloadedItem(for: next.track.id) {
                #if DEBUG
                print("⚡ Using preloaded AVPlayerItem for next track")
                #endif
                item = preloadedItem
            } else {
                // Fallback: prepare now
                item = try await prepareItemOptimized(for: next)
            }

            guard let playerItem = item else { return }

            nextPreloadedContext = next
            nextPreloadedItem = playerItem
            player.insert(playerItem, after: player.items().last)
            itemContextMap[playerItem] = next

            #if DEBUG
            print("✅ Next track preloaded and queued")
            #endif

        } catch {
            #if DEBUG
            print("❌ Preload failed (non-fatal): \(error)")
            #endif
            // Preload failures shouldn't break current playback
        }
    }

    private func nextContext(after context: PlaybackContext) -> PlaybackContext? {
        let index = context.queueIndex ?? queueManager.indexOfTrack(withId: context.track.id)
        guard let index else { return nil }

        guard let next = queueManager.nextTrack(after: index) else { return nil }

        return PlaybackContext(
            track: next.track,
            soundCloudTrack: queueManager.soundCloudTrack(for: next.track.id),
            queueIndex: next.index
        )
    }

    // MARK: - Playback Readiness Observer

    /// ⚡ NEW: Monitor playbackLikelyToKeepUp for accurate status updates
    private func observePlaybackReadiness(for item: AVPlayerItem) {
        // Cancel previous observation
        readinessObservation?.invalidate()

        // Observe playbackLikelyToKeepUp property
        readinessObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, change in
            guard let self = self else { return }
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    if self.status == .loading || self.player.timeControlStatus == .playing {
                        self.status = .playing
                        #if DEBUG
                        print("✅ Playback ready - likely to keep up")
                        #endif
                    }
                }
            }
        }
    }

    // MARK: - Observers

    /// ⚡ OPTIMIZED: Time observer with aggressive preloading at 50%
    private func addTimeObserver() {
        guard timeObserverToken == nil else { return }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                let duration = CMTimeGetSeconds(self.player.currentItem?.duration ?? .invalid)

                // ⚡ OPTIMIZED: Trigger at 50% instead of 75% for better UX
                if !self.hasPreloadedForCurrentTrack,
                   currentTime.isFinite,
                   duration.isFinite,
                   duration > 0 {
                    let progress = currentTime / duration

                    if progress >= self.preloadTriggerProgress,
                       let current = self.currentContext {
                        self.hasPreloadedForCurrentTrack = true

                        #if DEBUG
                        print("⚡ Reached 50% - triggering aggressive preload")
                        #endif

                        await self.preloadNextItem(from: current)
                    }
                }

                // Publish snapshot for UI updates
                Task { @MainActor in
                    self.publishSnapshot()
                }
            }
        }
    }

    @objc private func handleItemDidFinish(_ notification: Notification) {
        guard
            let finishedItem = notification.object as? AVPlayerItem,
            let finishedContext = itemContextMap[finishedItem]
        else { return }

        itemContextMap.removeValue(forKey: finishedItem)

        if autoplayEnabled,
           let preloadedContext = nextPreloadedContext,
           preloadedContext == nextContext(after: finishedContext) {
            currentContext = preloadedContext
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            hasPreloadedForCurrentTrack = false
            Task { @MainActor in
                publishSnapshot()
            }

            // Log auto-advanced track to play history
            if let userId = AuthManager.shared.currentUserId,
               let scTrack = preloadedContext.soundCloudTrack {
                Task { [convexService] in
                    do {
                        try await convexService.addPlay(userId: userId, track: scTrack)
                    } catch {
                        print("Failed to log play history: \(error)")
                    }
                }
            }

            Task { [weak self] in
                guard let self, let current = self.currentContext else { return }
                await self.preloadNextItem(from: current)
            }
            return
        }

        adoptCurrentItemContext()
    }

    private func adoptCurrentItemContext() {
        if let currentItem = player.currentItem,
           let context = itemContextMap[currentItem] {
            currentContext = context
            hasPreloadedForCurrentTrack = false
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            Task { @MainActor in
                publishSnapshot()
            }
        } else {
            currentContext = nil
            status = .ready
            Task { @MainActor in
                publishSnapshot()
            }
        }
    }

    private func publishSnapshot() {
        let currentTime = CMTimeGetSeconds(player.currentTime()).isFinite ? CMTimeGetSeconds(player.currentTime()) : 0
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)

        let effectiveStatus: PlayerState.PlaybackStatus = {
            if case .failed = status {
                return status
            }

            switch player.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                // Still show loading if waiting to play
                return .loading
            case .playing:
                return .playing
            case .paused:
                return .paused
            @unknown default:
                return status
            }
        }()

        let snapshot = PlaybackSnapshot(
            track: currentContext?.track,
            queueIndex: currentContext?.queueIndex,
            status: effectiveStatus,
            isPlaying: player.timeControlStatus == .playing,
            currentTime: currentTime,
            duration: duration.isFinite ? duration : (currentContext?.track.duration ?? 0)
        )

        delegate?.playbackCoordinator(self, didUpdate: snapshot)
    }

    // MARK: - Public Prefetching API

    /// ⚡ NEW: Trigger aggressive prefetching for queue
    /// Call this when queue loads or changes
    func prefetchQueue() {
        let tracks = queueManager.queueTracks
        guard !tracks.isEmpty else { return }

        Task {
            #if DEBUG
            print("🔥 Aggressive queue prefetching started")
            #endif

            // Step 1: Prefetch stream URLs for first 5 tracks
            await streamCache.prefetchUpcoming(tracks: tracks, lookAhead: 5)

            // Step 2: Preload AVPlayerItems for first 3 tracks
            let tracksToPreload = Array(tracks.prefix(3))
            for track in tracksToPreload {
                if let streamResponse = streamCache.getCachedStreamURL(for: track.id) {
                    let scTrack = queueManager.soundCloudTrack(for: track.id)
                    await itemCache.preloadItem(for: track, soundCloudTrack: scTrack, streamURL: streamResponse.stream_url)
                }
            }

            #if DEBUG
            print("✅ Queue prefetching completed")
            #endif
        }
    }

    /// ⚡ NEW: Prefetch specific track and neighbors
    /// Call this when user hovers or scrolls near a track
    func prefetchTrack(_ track: Track, with soundCloudTrack: SoundCloudTrack?) {
        Task {
            // Prefetch stream URL
            await streamCache.prefetchStreamURL(for: track.id)

            // If we have the URL, preload the item
            if let streamResponse = streamCache.getCachedStreamURL(for: track.id) {
                await itemCache.preloadItem(for: track, soundCloudTrack: soundCloudTrack, streamURL: streamResponse.stream_url)
            }
        }
    }

    deinit {
        readinessObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
