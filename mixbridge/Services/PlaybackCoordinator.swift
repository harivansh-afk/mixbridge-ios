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
    private let streamCache = StreamURLCache.shared
    private let itemCache = PreloadedItemCache.shared
    private let positionTracker = PlaybackPositionTracker.shared

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
        let maxAttempts = 5

        /// Exponential backoff: 1s, 2s, 4s, 8s, 16s
        var nextRetryDelay: TimeInterval {
            pow(2, Double(attemptCount))
        }

        var canRetryNow: Bool {
            attemptCount < maxAttempts &&
            Date().timeIntervalSince(lastAttemptTime) >= nextRetryDelay
        }
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
        !player.items().isEmpty
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
        isIntendedToPlay = false
        player.pause()
        status = .paused
        positionTracker.flush()  // Save current position immediately
    }

    func resume() {
        guard !player.items().isEmpty else { return }
        isIntendedToPlay = true
        player.play()
        status = .playing
    }

    func seek(to time: Double) {
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

    // MARK: - Playback Pipeline

    private func startPlayback(with context: PlaybackContext, startTime: Double? = nil) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        let pendingContext = context
        status = .loading

        do {
            logDebug("Fetching stream URL...")
            let item = try await prepareItem(for: pendingContext)

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
            currentContext = pendingContext

            logInfo("Playback started: \(pendingContext.track.title)")

            // Clear retry metadata on success
            retryAttempts.removeValue(forKey: pendingContext.track.id)

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
                }
            }

        } catch {
            // Update retry metadata with exponential backoff
            var metadata = retryAttempts[pendingContext.track.id] ?? RetryMetadata()
            metadata.attemptCount += 1
            metadata.lastAttemptTime = Date()
            retryAttempts[pendingContext.track.id] = metadata

            isIntendedToPlay = false
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)
            logError("Playback failed (attempt \(metadata.attemptCount)/\(metadata.maxAttempts)): \(error)")
        }
    }

    private func prepareItem(for context: PlaybackContext) async throws -> AVPlayerItem {
        // Use Convex action for direct CDN access (faster than Next.js API)
        let response = try await convexService.getDirectStreamURL(trackId: context.track.id)

        guard let url = URL(string: response.stream_url) else {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        // Use SoundCloud OAuth token directly for CDN access
        // This bypasses the HLS proxy, saving ~200-400ms
        let headers = ["Authorization": "OAuth \(response.access_token)"]
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
                currentContext = preloadedContext
                nextPreloadedContext = nil
                nextPreloadedItem = nil
                hasPreloadedForCurrentTrack = false
                publishSnapshot()

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
            currentContext = context
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
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)

        let effectiveStatus: PlayerState.PlaybackStatus = {
            if case .failed = status { return status }

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

            for track in tracks.prefix(3) {
                if let streamResponse = streamCache.getCachedStreamURL(for: track.id) {
                    let scTrack = queueManager.soundCloudTrack(for: track.id)
                    await itemCache.preloadItem(for: track, soundCloudTrack: scTrack, streamURL: streamResponse.stream_url)
                }
            }
        }
    }

    func prefetchTrack(_ track: Track, with soundCloudTrack: SoundCloudTrack?) {
        Task {
            await streamCache.prefetchStreamURL(for: track.id)
            if let streamResponse = streamCache.getCachedStreamURL(for: track.id) {
                await itemCache.preloadItem(for: track, soundCloudTrack: soundCloudTrack, streamURL: streamResponse.stream_url)
            }
        }
    }

    deinit {
        readinessObservation?.invalidate()
        waitingReasonObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
