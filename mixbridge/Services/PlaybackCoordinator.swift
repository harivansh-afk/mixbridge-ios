//
//  PlaybackCoordinator.swift
//  mixbridge
//
//  Clean audio playback using AVPlayer's native buffering.
//  AVPlayer handles stalls/recovery automatically when automaticallyWaitsToMinimizeStalling = true
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

struct PlaybackContext: Equatable {
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

    // MARK: - Mix Mode Settings

    /// Enable automatic crossfade between tracks
    var mixEnabled: Bool = false

    /// Crossfade duration in seconds
    var crossfadeSeconds: Double = 6

    /// Prewarm lead time in seconds
    var prewarmSeconds: Double = 15

    /// Fade curve type for crossfade transitions
    var fadeCurve: FadeCurve = .equalPower

    private let queueManager = QueueManager.shared
    private let keychain = KeychainManager.shared
    private let convexService = ConvexService.shared
    private let streamCache = StreamURLCache.shared
    private let positionTracker = PlaybackPositionTracker.shared
    private let dataStore = PreloadedDataStore.shared
    private let dataPreloader = AppDataPreloader.shared

    // MARK: - Mix Mode Engine

    /// Lazy-initialized mix engine for crossfade playback
    private lazy var mixEngine: MixPlaybackEngine = {
        let engine = MixPlaybackEngine()
        engine.delegate = self
        return engine
    }()

    /// Whether we're currently using mix mode for playback
    private var isUsingMixMode: Bool = false

    private let player = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var currentContext: PlaybackContext?
    private var nextPreloadedContext: PlaybackContext?
    private var nextPreloadedItem: AVPlayerItem?
    private var itemContextMap: [AVPlayerItem: PlaybackContext] = [:]
    private var hasPreloadedForCurrentTrack = false
    private let preloadTriggerProgress: Double = 0.50
    private var readinessObservation: NSKeyValueObservation?

    private var status: PlayerState.PlaybackStatus = .idle {
        didSet { publishSnapshot() }
    }

    private var isPreparingPlayback = false

    /// Track retry attempts with exponential backoff
    private var retryAttempts: [String: RetryMetadata] = [:]

    private struct RetryMetadata {
        var attemptCount: Int = 0
        var lastAttemptTime: Date = Date()
        let maxAttempts = 3

        /// Exponential backoff: 2s, 4s, 8s
        var nextRetryDelay: TimeInterval {
            pow(2, Double(attemptCount + 1))
        }

        var canRetryNow: Bool {
            attemptCount < maxAttempts &&
            Date().timeIntervalSince(lastAttemptTime) >= nextRetryDelay
        }

        var hasRetriesRemaining: Bool {
            attemptCount < maxAttempts
        }
    }

    /// Errors that should trigger an automatic retry with fresh URL
    private func isRecoverableError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // Network timeout errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,           // -1001
                 NSURLErrorNetworkConnectionLost, // -1005
                 NSURLErrorNotConnectedToInternet, // -1009
                 NSURLErrorCannotConnectToHost,   // -1004
                 NSURLErrorSecureConnectionFailed: // -1200
                return true
            default:
                break
            }
        }

        // Server errors from Convex (expired URLs return server errors)
        let errorString = error.localizedDescription.lowercased()
        if errorString.contains("server error") ||
           errorString.contains("expired") ||
           errorString.contains("forbidden") ||
           errorString.contains("unauthorized") {
            return true
        }

        return false
    }

    /// Track user's playback intent (not transient player states)
    /// UI shows "playing" during buffering instead of flickering to "paused"
    private var isIntendedToPlay: Bool = false

    /// Observer for player waiting reason
    private var waitingReasonObservation: NSKeyValueObservation?

    private override init() {
        super.init()

        // Let AVPlayer handle buffering automatically
        // When true: waits when buffer low, auto-resumes when ready
        // When false: pauses randomly when buffer empties (the bug!)
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .advance

        addTimeObserver()
        observeWaitingReason()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )

        logInfo("PlaybackCoordinator initialized")
    }

    // MARK: - Public Controls

    var hasLoadedItems: Bool {
        if isUsingMixMode {
            return mixEngine.duration > 0
        }
        return !player.items().isEmpty
    }

    func play(track: Track, soundCloudTrack: SoundCloudTrack?, queueIndex: Int?, startTime: Double? = nil) {
        guard !isPreparingPlayback else {
            logWarning("Playback already in progress, ignoring duplicate request")
            return
        }

        // Check if track can be retried (exponential backoff)
        if let metadata = retryAttempts[track.id] {
            if !metadata.canRetryNow {
                let waitTime = metadata.nextRetryDelay - Date().timeIntervalSince(metadata.lastAttemptTime)
                logWarning("Track \(track.title) in backoff, retry in \(String(format: "%.1f", max(0, waitTime)))s")
                return
            }
        }

        let effectiveQueueIndex = queueIndex ?? queueManager.indexOfTrack(withId: track.id)
        let context = PlaybackContext(track: track, soundCloudTrack: soundCloudTrack, queueIndex: effectiveQueueIndex)

        Task {
            if mixEnabled {
                await startMixPlayback(with: context, startTime: startTime)
            } else {
                await startPlayback(with: context, startTime: startTime)
            }
        }
    }

    func togglePlayback() {
        if isUsingMixMode {
            if mixEngine.isPlaying {
                pause()
            } else {
                resume()
            }
        } else {
            if player.timeControlStatus == .playing {
                pause()
            } else {
                resume()
            }
        }
    }

    func pause() {
        isIntendedToPlay = false
        if isUsingMixMode {
            mixEngine.pause()
        } else {
            player.pause()
        }
        status = .paused
        positionTracker.flush()  // Save current position immediately
    }

    func resume() {
        if isUsingMixMode {
            isIntendedToPlay = true
            mixEngine.resume()
            status = .playing
        } else {
            guard !player.items().isEmpty else { return }
            isIntendedToPlay = true
            player.play()
            status = .playing
        }
    }

    func seek(to time: Double) {
        if isUsingMixMode {
            mixEngine.seek(to: time)
            publishSnapshot()
        } else {
            let wasPlaying = player.timeControlStatus == .playing
            let target = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard let self = self, finished else { return }
                Task { @MainActor in
                    if wasPlaying {
                        self.player.play()
                    }
                    self.publishSnapshot()
                }
            }
        }
    }

    func setVolume(_ value: Double) {
        if isUsingMixMode {
            mixEngine.setVolume(value)
        } else {
            player.volume = Float(value)
        }
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

    // MARK: - Playback Pipeline

    /// Called when a track successfully starts playing. Removes it from queue and updates context.
    private func handleTrackStartedPlaying(context: PlaybackContext) {
        let shouldRemove = queueManager.isInQueue(context.track.id)

        // Set context with appropriate queue index (-1 if removed from queue)
        currentContext = PlaybackContext(
            track: context.track,
            soundCloudTrack: context.soundCloudTrack,
            queueIndex: shouldRemove ? -1 : context.queueIndex
        )

        // Remove from queue in background (silently, no haptic feedback)
        if shouldRemove {
            let trackToRemove = context.track
            Task {
                try? await queueManager.removeTrack(trackToRemove, silent: true)
            }
        }
    }

    private func startPlayback(with context: PlaybackContext, startTime: Double? = nil, forceRefreshURL: Bool = false) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        let pendingContext = context
        status = .loading

        do {
            logDebug("Fetching stream URL\(forceRefreshURL ? " (force refresh)" : "")...")
            let item = try await prepareItem(for: pendingContext, forceRefresh: forceRefreshURL)

            // Clear old items
            player.removeAllItems()
            itemContextMap.removeAll()
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            hasPreloadedForCurrentTrack = false

            // Insert new item
            player.insert(item, after: nil)
            itemContextMap[item] = pendingContext

            observePlaybackReadiness(for: item)

            // Check for immediate failure (bad URL, etc.)
            if item.status == .failed {
                throw item.error ?? PlayerState.PlaybackError.invalidStreamURL
            }

            // Seek if needed
            if let startTime = startTime, startTime > 0 {
                await player.seek(to: CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero)
            }

            // Play
            isIntendedToPlay = true
            player.play()
            handleTrackStartedPlaying(context: pendingContext)

            logInfo("Playback started: \(pendingContext.track.title)")

            // Clear retry metadata on success
            retryAttempts.removeValue(forKey: pendingContext.track.id)

            // Optimistic UI update: add/move track to top of recently played
            if let scTrack = pendingContext.soundCloudTrack {
                let item = TrackItem(soundCloudTrack: scTrack)
                dataStore.prependOrMovePlayHistoryTrack(item)
            }

            // Start position tracking session and log play to history
            if let userId = AuthManager.shared.currentUserId,
               autoplayEnabled,
               let scTrack = pendingContext.soundCloudTrack {
                let sessionId = positionTracker.startSession(
                    trackId: pendingContext.track.id,
                    queueIndex: pendingContext.queueIndex,
                    duration: Double(scTrack.duration) / 1000.0  // Convert ms to seconds
                )
                Task {
                    try? await convexService.addPlay(
                        userId: userId,
                        track: scTrack,
                        sessionId: sessionId,
                        queueIndex: pendingContext.queueIndex
                    )
                    // Background refresh to sync with Convex source of truth
                    await dataPreloader.forceRefreshPlayHistory(userId: userId)
                }
            }

        } catch {
            // Check if this is a recoverable error (timeout, server error, expired URL)
            let metadata = retryAttempts[pendingContext.track.id] ?? RetryMetadata()

            if isRecoverableError(error) && metadata.hasRetriesRemaining && !forceRefreshURL {
                // First failure with cached URL - retry immediately with fresh URL
                logWarning("Recoverable error, retrying with fresh URL: \(error.localizedDescription)")

                // Invalidate the cached URL
                await streamCache.invalidate(trackId: pendingContext.track.id)

                // Retry with force refresh (don't increment counter yet)
                await startPlayback(with: pendingContext, startTime: startTime, forceRefreshURL: true)
                return
            }

            // Update retry metadata - only count failures after fresh URL attempt
            var updatedMetadata = metadata
            updatedMetadata.attemptCount += 1
            updatedMetadata.lastAttemptTime = Date()
            retryAttempts[pendingContext.track.id] = updatedMetadata

            isIntendedToPlay = false
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)
            logError("Playback failed (attempt \(updatedMetadata.attemptCount)/\(updatedMetadata.maxAttempts)): \(error)")
        }
    }

    // MARK: - Mix Mode Playback

    private func startMixPlayback(with context: PlaybackContext, startTime: Double? = nil, forceRefreshURL: Bool = false) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        status = .loading

        do {
            logDebug("[MixMode] Fetching stream URL\(forceRefreshURL ? " (force refresh)" : "")...")

            let stream: CachedStreamData
            if forceRefreshURL {
                guard let freshStream = await streamCache.forceRefresh(for: context.track.id) else {
                    throw PlayerState.PlaybackError.invalidStreamURL
                }
                stream = freshStream
            } else {
                // Check if cached stream is expiring soon
                let deadline = Date().addingTimeInterval(30)
                let needsRefresh = await streamCache.isStreamExpiring(for: context.track.id, before: deadline)

                if needsRefresh {
                    guard let refreshedStream = await streamCache.forceRefresh(for: context.track.id) else {
                        throw PlayerState.PlaybackError.invalidStreamURL
                    }
                    stream = refreshedStream
                } else {
                    stream = try await streamCache.ensureStream(for: context.track.id, priority: .userInitiated)
                }
            }

            // Stop regular playback and switch to mix mode
            player.pause()
            player.removeAllItems()
            itemContextMap.removeAll()

            // Configure mix engine
            mixEngine.crossfadeSeconds = crossfadeSeconds
            mixEngine.prewarmSeconds = prewarmSeconds
            mixEngine.fadeCurve = fadeCurve

            // Start mix playback
            mixEngine.play(context: context, streamData: stream, startTime: startTime)
            isUsingMixMode = true

            isIntendedToPlay = true
            currentContext = context
            handleTrackStartedPlaying(context: context)

            logInfo("[MixMode] Playback started: \(context.track.title)")

            // Clear retry metadata on success
            retryAttempts.removeValue(forKey: context.track.id)

            // Optimistic UI update
            if let scTrack = context.soundCloudTrack {
                let item = TrackItem(soundCloudTrack: scTrack)
                dataStore.prependOrMovePlayHistoryTrack(item)
            }

            // Start position tracking
            if let userId = AuthManager.shared.currentUserId,
               autoplayEnabled,
               let scTrack = context.soundCloudTrack {
                let sessionId = positionTracker.startSession(
                    trackId: context.track.id,
                    queueIndex: context.queueIndex,
                    duration: Double(scTrack.duration) / 1000.0
                )
                Task {
                    try? await convexService.addPlay(
                        userId: userId,
                        track: scTrack,
                        sessionId: sessionId,
                        queueIndex: context.queueIndex
                    )
                    await dataPreloader.forceRefreshPlayHistory(userId: userId)
                }
            }

            status = .playing

        } catch {
            // Check if this is a recoverable error
            let metadata = retryAttempts[context.track.id] ?? RetryMetadata()

            if isRecoverableError(error) && metadata.hasRetriesRemaining && !forceRefreshURL {
                logWarning("[MixMode] Recoverable error, retrying with fresh URL: \(error.localizedDescription)")
                await streamCache.invalidate(trackId: context.track.id)
                await startMixPlayback(with: context, startTime: startTime, forceRefreshURL: true)
                return
            }

            var updatedMetadata = metadata
            updatedMetadata.attemptCount += 1
            updatedMetadata.lastAttemptTime = Date()
            retryAttempts[context.track.id] = updatedMetadata

            isIntendedToPlay = false
            isUsingMixMode = false
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)
            logError("[MixMode] Playback failed (attempt \(updatedMetadata.attemptCount)/\(updatedMetadata.maxAttempts)): \(error)")
        }
    }

    private func prepareItem(for context: PlaybackContext, forceRefresh: Bool = false) async throws -> AVPlayerItem {
        let stream: CachedStreamData

        if forceRefresh {
            // Force refresh - invalidate cache and fetch fresh URL
            guard let freshStream = await streamCache.forceRefresh(for: context.track.id) else {
                throw PlayerState.PlaybackError.invalidStreamURL
            }
            stream = freshStream
        } else {
            // Check if cached stream is expiring soon (within 30 seconds)
            // This mirrors what MixPlaybackEngine does for prewarm
            let deadline = Date().addingTimeInterval(30)
            let needsRefresh = await streamCache.isStreamExpiring(for: context.track.id, before: deadline)

            if needsRefresh {
                logDebug("Cached stream expiring soon, fetching fresh URL...")
                guard let refreshedStream = await streamCache.forceRefresh(for: context.track.id) else {
                    throw PlayerState.PlaybackError.invalidStreamURL
                }
                stream = refreshedStream
            } else {
                stream = try await streamCache.ensureStream(for: context.track.id, priority: .userInitiated)
            }
        }

        guard let url = URL(string: stream.url) else {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        // Use SoundCloud OAuth token directly for CDN access
        // This bypasses the HLS proxy, saving ~200-400ms
        let headers = ["Authorization": "OAuth \(stream.accessToken)"]
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])

        let item = AVPlayerItem(asset: asset)

        // Buffer 10 seconds ahead - prevents micro-stalls from network hiccups
        item.preferredForwardBufferDuration = 10
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        return item
    }

    private func preloadNextItem(from context: PlaybackContext) async {
        guard let next = nextContext(after: context) else {
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            return
        }

        do {
            if let existingItem = nextPreloadedItem {
                player.remove(existingItem)
                itemContextMap.removeValue(forKey: existingItem)
            }

            let item = try await prepareItem(for: next)
            nextPreloadedContext = next
            nextPreloadedItem = item
            player.insert(item, after: player.items().last)
            itemContextMap[item] = next

        } catch {
            // Preload failures are non-fatal
        }
    }

    private func nextContext(after context: PlaybackContext) -> PlaybackContext? {
        let index = context.queueIndex ?? queueManager.indexOfTrack(withId: context.track.id)
        guard let index, let next = queueManager.nextTrack(after: index) else { return nil }

        return PlaybackContext(
            track: next.track,
            soundCloudTrack: queueManager.soundCloudTrack(for: next.track.id),
            queueIndex: next.index
        )
    }

    // MARK: - Observers

    /// Monitor why player is waiting - shows loading spinner during buffering
    private func observeWaitingReason() {
        waitingReasonObservation = player.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }

            Task { @MainActor in
                if let reason = player.reasonForWaitingToPlay {
                    // Player is waiting - show loading state
                    switch reason {
                    case .toMinimizeStalls:
                        // Buffering to prevent future stalls
                        if self.isIntendedToPlay {
                            self.status = .loading
                        }
                    case .evaluatingBufferingRate:
                        // Evaluating network speed
                        if self.isIntendedToPlay {
                            self.status = .loading
                        }
                    case .noItemToPlay:
                        // No content loaded
                        break
                    default:
                        break
                    }

                    #if DEBUG
                    print("⏳ Player waiting: \(reason.rawValue)")
                    #endif
                } else if self.isIntendedToPlay && self.player.timeControlStatus == .playing {
                    // No longer waiting - update to playing
                    self.status = .playing
                }
            }
        }
    }

    private func observePlaybackReadiness(for item: AVPlayerItem) {
        readinessObservation?.invalidate()

        readinessObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp && (self.status == .loading || self.player.timeControlStatus == .playing) {
                    self.status = .playing
                }
            }
        }
    }

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

                // Track position for periodic flush (every 10 seconds)
                if currentTime.isFinite && duration.isFinite {
                    self.positionTracker.updatePosition(currentTime, duration: duration)
                }

                // Preload at 50%
                if !self.hasPreloadedForCurrentTrack,
                   currentTime.isFinite, duration.isFinite, duration > 0,
                   currentTime / duration >= self.preloadTriggerProgress,
                   let current = self.currentContext {
                    self.hasPreloadedForCurrentTrack = true
                    await self.preloadNextItem(from: current)
                }

                self.publishSnapshot()
            }
        }
    }

    @objc private func handleItemDidFinish(_ notification: Notification) {
        guard
            let finishedItem = notification.object as? AVPlayerItem,
            let finishedContext = itemContextMap[finishedItem]
        else { return }

        // End position tracking for finished track
        positionTracker.endSession()

        itemContextMap.removeValue(forKey: finishedItem)

        if autoplayEnabled,
           let preloadedContext = nextPreloadedContext,
           let preloadedItem = nextPreloadedItem,
           preloadedContext == nextContext(after: finishedContext) {

            if preloadedItem.status == .readyToPlay {
                handleTrackStartedPlaying(context: preloadedContext)
                nextPreloadedContext = nil
                nextPreloadedItem = nil
                hasPreloadedForCurrentTrack = false
                publishSnapshot()

                // Optimistic UI update for autoplay transition
                if let scTrack = preloadedContext.soundCloudTrack {
                    let item = TrackItem(soundCloudTrack: scTrack)
                    dataStore.prependOrMovePlayHistoryTrack(item)
                }

                if let userId = AuthManager.shared.currentUserId,
                   let scTrack = preloadedContext.soundCloudTrack {
                    let sessionId = positionTracker.startSession(
                        trackId: preloadedContext.track.id,
                        queueIndex: preloadedContext.queueIndex,
                        duration: Double(scTrack.duration) / 1000.0
                    )
                    Task {
                        try? await convexService.addPlay(
                            userId: userId,
                            track: scTrack,
                            sessionId: sessionId,
                            queueIndex: preloadedContext.queueIndex
                        )
                        // Background refresh to sync with Convex source of truth
                        await dataPreloader.forceRefreshPlayHistory(userId: userId)
                    }
                }

                Task {
                    await preloadNextItem(from: preloadedContext)
                }
                return

            } else {
                // Preloaded item not ready, play fresh
                player.remove(preloadedItem)
                nextPreloadedContext = nil
                nextPreloadedItem = nil
                itemContextMap.removeValue(forKey: preloadedItem)

                Task {
                    await startPlayback(with: preloadedContext)
                }
                return
            }
        }

        adoptCurrentItemContext()
    }

    private func adoptCurrentItemContext() {
        if let currentItem = player.currentItem,
           let context = itemContextMap[currentItem] {
            handleTrackStartedPlaying(context: context)
            hasPreloadedForCurrentTrack = false
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            publishSnapshot()
        } else {
            currentContext = nil
            status = .ready
            publishSnapshot()
        }
    }

    private func publishSnapshot() {
        let currentTime: Double
        let duration: Double

        if isUsingMixMode {
            currentTime = mixEngine.currentTime
            duration = mixEngine.duration
        } else {
            currentTime = CMTimeGetSeconds(player.currentTime())
            duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        }

        let effectiveStatus: PlayerState.PlaybackStatus = {
            if case .failed = status { return status }

            if isUsingMixMode {
                return mixEngine.isPlaying ? .playing : (isIntendedToPlay ? .loading : .paused)
            }

            switch player.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                return .loading
            case .playing:
                return .playing
            case .paused:
                return isIntendedToPlay ? .loading : .paused
            @unknown default:
                return status
            }
        }()

        let effectiveIsPlaying: Bool = {
            if case .failed = status { return false }
            return isIntendedToPlay
        }()

        let snapshot = PlaybackSnapshot(
            track: currentContext?.track,
            queueIndex: currentContext?.queueIndex,
            status: effectiveStatus,
            isPlaying: effectiveIsPlaying,
            currentTime: currentTime.isFinite ? currentTime : 0,
            duration: duration.isFinite ? duration : (currentContext?.track.duration ?? 0)
        )

        delegate?.playbackCoordinator(self, didUpdate: snapshot)
    }

    // MARK: - Prefetching

    func prefetchQueue() {
        let tracks = queueManager.queueTracks
        guard !tracks.isEmpty else { return }

        Task {
            await streamCache.prefetchUpcoming(tracks: tracks, lookAhead: 5)
        }
    }

    func prefetchTrack(_ track: Track, with soundCloudTrack: SoundCloudTrack?) {
        Task {
            await streamCache.prefetchStreamURL(for: track.id)
        }
    }

    deinit {
        readinessObservation?.invalidate()
        waitingReasonObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - MixPlaybackEngineDelegate

extension PlaybackCoordinator: MixPlaybackEngineDelegate {
    func mixEngine(_ engine: MixPlaybackEngine, didEmit event: MixObservabilityEvent) {
        // Log observability events
        switch event {
        case .prewarmStart(let trackId, let nextTrackId, let crossfade):
            logInfo("[MixObservability] mix_prewarm_start: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .prewarmReady(let trackId, let nextTrackId, let crossfade):
            logInfo("[MixObservability] mix_prewarm_ready: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeStart(let trackId, let nextTrackId, let crossfade):
            logInfo("[MixObservability] mix_fade_start: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeComplete(let trackId, let nextTrackId, let crossfade):
            logInfo("[MixObservability] mix_fade_complete: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeAbort(let trackId, let nextTrackId, let crossfade, let reason):
            logWarning("[MixObservability] mix_fade_abort(\(reason)): \(trackId) -> \(nextTrackId ?? "nil"), crossfade=\(crossfade)s")
        }
    }

    func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        // End position tracking for previous track
        positionTracker.endSession()

        // Update current context
        currentContext = context
        handleTrackStartedPlaying(context: context)

        logInfo("[MixMode] Transition complete: now playing \(track.title)")

        // Optimistic UI update
        if let scTrack = context.soundCloudTrack {
            let item = TrackItem(soundCloudTrack: scTrack)
            dataStore.prependOrMovePlayHistoryTrack(item)
        }

        // Start position tracking for new track
        if let userId = AuthManager.shared.currentUserId,
           autoplayEnabled,
           let scTrack = context.soundCloudTrack {
            let sessionId = positionTracker.startSession(
                trackId: context.track.id,
                queueIndex: context.queueIndex,
                duration: Double(scTrack.duration) / 1000.0
            )
            Task {
                try? await convexService.addPlay(
                    userId: userId,
                    track: scTrack,
                    sessionId: sessionId,
                    queueIndex: context.queueIndex
                )
                await dataPreloader.forceRefreshPlayHistory(userId: userId)
            }
        }

        publishSnapshot()
    }

    func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        // Mix transition aborted - fallback to normal playback
        logWarning("[MixMode] Transition aborted, falling back to normal playback")

        // If we have a next track context, try normal playback
        if let context = context {
            Task {
                // Switch back to non-mix mode for fallback
                isUsingMixMode = false
                await startPlayback(with: context)
            }
        }
    }

    func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double) {
        // Track position for periodic flush
        if currentTime.isFinite && duration.isFinite {
            positionTracker.updatePosition(currentTime, duration: duration)
        }

        // Publish snapshot to update UI
        publishSnapshot()
    }
}
