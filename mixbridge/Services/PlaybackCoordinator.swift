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
import MusicKit

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
    let appleMusicTrack: AppleMusicTrack?
    let queueIndex: Int?

    init(track: Track, soundCloudTrack: SoundCloudTrack?, queueIndex: Int?) {
        self.track = track
        self.soundCloudTrack = soundCloudTrack
        self.appleMusicTrack = nil
        self.queueIndex = queueIndex
    }

    init(track: Track, appleMusicTrack: AppleMusicTrack?, queueIndex: Int?) {
        self.track = track
        self.soundCloudTrack = nil
        self.appleMusicTrack = appleMusicTrack
        self.queueIndex = queueIndex
    }

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
    var mixEnabled: Bool = false {
        didSet {
            // If mix mode is disabled while active, just cancel pending crossfades
            // Let the current track finish playing - next track will use AVQueuePlayer
            if !mixEnabled && isUsingMixMode {
                mixEngine.handleMixDisabled()
            }
        }
    }

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
    private let historySync = HistorySync.shared

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
    private var playbackTask: Task<Void, Never>?
    private var activeRequestId: UUID = UUID()

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

        logInfo(.playback, "PlaybackCoordinator initialized")
    }

    // MARK: - Public Controls

    var hasLoadedItems: Bool {
        if isUsingMixMode {
            return mixEngine.duration > 0
        }
        return !player.items().isEmpty
    }

    func play(track: Track, soundCloudTrack: SoundCloudTrack?, queueIndex: Int?, startTime: Double? = nil) {
        // Cancel any in-flight preparation so rapid taps feel instantaneous.
        playbackTask?.cancel()
        isIntendedToPlay = true
        let requestId = UUID()
        activeRequestId = requestId

        // Stop current audio immediately so UI never "bounces" between old/new tracks.
        if isUsingMixMode {
            mixEngine.stop()
            isUsingMixMode = false
        } else {
            player.pause()
        }
        // Stop Apple Music playback if it was playing
        stopAppleMusicPlayback()

        PlayerState.shared.crossfadeFromArtwork = ""
        PlayerState.shared.crossfadeProgress = 0
        PlayerState.shared.isCrossfading = false
        PlayerState.shared.crossfadeNextTrack = nil
        PlayerState.shared.crossfadeNextPosition = 0
        PlayerState.shared.crossfadeNextDuration = 0

        // Check if track can be retried (exponential backoff)
        if let metadata = retryAttempts[track.id] {
            if !metadata.canRetryNow {
                let waitTime = metadata.nextRetryDelay - Date().timeIntervalSince(metadata.lastAttemptTime)
                logWarning(.playback, "Track \(track.title) in backoff, retry in \(String(format: "%.1f", max(0, waitTime)))s")
                return
            }
        }

        let effectiveQueueIndex = queueIndex ?? queueManager.indexOfTrack(withId: track.id)
        let context = PlaybackContext(track: track, soundCloudTrack: soundCloudTrack, queueIndex: effectiveQueueIndex)

        // Immediate UI: publish selected track + loading state synchronously.
        currentContext = context
        status = .loading

        playbackTask = Task { [weak self] in
            guard let self else { return }
            if self.mixEnabled {
                await self.startMixPlayback(with: context, requestId: requestId, startTime: startTime)
            } else {
                await self.startPlayback(with: context, requestId: requestId, startTime: startTime)
            }
        }
    }

    /// Play an Apple Music track using MusicKit
    func playAppleMusicTrack(_ appleMusicTrack: AppleMusicTrack, queueIndex: Int?, startTime: Double? = nil) {
        // Cancel any in-flight preparation
        playbackTask?.cancel()
        isIntendedToPlay = true
        let requestId = UUID()
        activeRequestId = requestId

        // Stop AVPlayer playback
        if isUsingMixMode {
            mixEngine.stop()
            isUsingMixMode = false
        } else {
            player.pause()
        }

        PlayerState.shared.crossfadeFromArtwork = ""
        PlayerState.shared.crossfadeProgress = 0
        PlayerState.shared.isCrossfading = false
        PlayerState.shared.crossfadeNextTrack = nil
        PlayerState.shared.crossfadeNextPosition = 0
        PlayerState.shared.crossfadeNextDuration = 0

        let effectiveQueueIndex = queueIndex ?? queueManager.indexOfTrack(withId: appleMusicTrack.id)
        let track = appleMusicTrack.toTrack()
        let context = PlaybackContext(track: track, appleMusicTrack: appleMusicTrack, queueIndex: effectiveQueueIndex)

        currentContext = context
        status = .loading

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.startAppleMusicPlayback(with: context, requestId: requestId, startTime: startTime)
        }
    }

    /// Start Apple Music playback using SystemMusicPlayer
    private func startAppleMusicPlayback(with context: PlaybackContext, requestId: UUID, startTime: Double? = nil) async {
        guard activeRequestId == requestId else { return }

        do {
            guard let appleMusicTrack = context.appleMusicTrack else {
                throw AppleMusicServiceError.invalidId
            }

            // Get the Song from MusicKit
            let song = try await AppleMusicService.shared.getSongForPlayback(trackId: appleMusicTrack.id)

            guard activeRequestId == requestId, !Task.isCancelled else { return }

            // Use SystemMusicPlayer for Apple Music playback
            let musicPlayer = SystemMusicPlayer.shared
            musicPlayer.queue = [song]

            if let startTime = startTime, startTime > 0 {
                musicPlayer.playbackTime = startTime
            }

            guard isIntendedToPlay else {
                status = .paused
                return
            }

            try await musicPlayer.play()

            handleTrackStartedPlaying(context: context)
            status = .playing

            logInfo(.playback, "[AppleMusic] Playback started: \(context.track.title)")

            // Start position tracking
            if let userId = AuthManager.shared.currentUserId, autoplayEnabled {
                _ = positionTracker.startSession(
                    trackId: context.track.id,
                    queueIndex: context.queueIndex,
                    duration: appleMusicTrack.duration
                )
            }

        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }

            isIntendedToPlay = false
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)
            logError(.playback, "[AppleMusic] Playback failed: \(error)")
        }
    }

    /// Stop Apple Music playback
    private func stopAppleMusicPlayback() {
        Task {
            let musicPlayer = SystemMusicPlayer.shared
            musicPlayer.stop()
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
        playbackTask?.cancel()
        playbackTask = nil
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
        logInfo(.queue, "playNext called (manual=\(manual))")

        // If manual forward in mix mode, trigger instant mix instead of normal skip
        if manual && mixEnabled && isUsingMixMode {
            if mixEngine.triggerInstantMix() {
                logInfo(.queue, "playNext: triggered instant mix")
                HapticManager.selection()
                return
            }
            // Fall through to normal skip if instant mix failed
        }

        // Pop the next track from queue BEFORE playing
        // This enforces the invariant: current track is never in the queue
        guard let nextItem = queueManager.popNext() else {
            logWarning(.queue, "playNext: queue empty, nothing to play")
            if manual {
                HapticManager.selection()
            }
            return
        }

        logInfo(.queue, "playNext: playing '\(nextItem.track.title)'")

        if isUsingMixMode {
            mixEngine.stop()
            isUsingMixMode = false
        }

        play(track: nextItem.track, soundCloudTrack: nextItem.soundCloudTrack, queueIndex: nil)

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

    /// Called when the app queue changes (reorder/insert/remove).
    /// Keeps internal preloads/prewarms from diverging from the queue's "top of cue" policy.
    func handleQueueChanged() {
        logDebug(.queue, "handleQueueChanged: mixMode=\(isUsingMixMode)")
        if isUsingMixMode {
            mixEngine.handleQueueChanged()
            return
        }

        // Non-mix: drop any stale preloaded "next" item so Next/autoplay always reflects the latest queue.
        if let item = nextPreloadedItem {
            if player.items().contains(item) {
                player.remove(item)
            }
            itemContextMap.removeValue(forKey: item)
        }
        nextPreloadedItem = nil
        nextPreloadedContext = nil
        hasPreloadedForCurrentTrack = false
    }

    // MARK: - Playback Pipeline

    /// Called when a track successfully starts playing. Updates context.
    /// Note: Track removal from queue happens BEFORE play() is called (via popNext),
    /// so we don't need to remove here.
    private func handleTrackStartedPlaying(context: PlaybackContext) {
        currentContext = context
        Analytics.shared.track(
            "track_played",
            properties: [
                "track_id": context.track.id,
                "track_title": context.track.title,
                "artist_name": context.track.artist,
                "duration_seconds": context.track.duration
            ]
        )
    }

    private func startPlayback(with context: PlaybackContext, requestId: UUID, startTime: Double? = nil, forceRefreshURL: Bool = false) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        guard activeRequestId == requestId else { return }

        // Ensure mix engine is fully stopped before starting AVQueuePlayer playback.
        // Without this, it's possible to end up with mixEngine still playing while the queue player starts,
        // which sounds like "previous song playing latently in the background".
        if isUsingMixMode {
            mixEngine.stop()
            isUsingMixMode = false
        }

        let pendingContext = context
        status = .loading

        do {
            logDebug(.playback, "Fetching stream URL\(forceRefreshURL ? " (force refresh)" : "")...")
            let item = try await prepareItem(for: pendingContext, forceRefresh: forceRefreshURL)
            guard activeRequestId == requestId, !Task.isCancelled else { return }

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
            guard activeRequestId == requestId, !Task.isCancelled else { return }

            // Only start audio if the user still intends to play (e.g., they didn’t pause mid-load).
            guard isIntendedToPlay else {
                status = .paused
                return
            }
            player.play()
            handleTrackStartedPlaying(context: pendingContext)

            logInfo(.playback, "Playback started: \(pendingContext.track.title)")

            // Clear retry metadata on success
            retryAttempts.removeValue(forKey: pendingContext.track.id)

            // Start position tracking session and add to history (optimistic update)
            if let userId = AuthManager.shared.currentUserId,
               autoplayEnabled,
               let scTrack = pendingContext.soundCloudTrack {
                let sessionId = positionTracker.startSession(
                    trackId: pendingContext.track.id,
                    queueIndex: pendingContext.queueIndex,
                    duration: Double(scTrack.duration) / 1000.0  // Convert ms to seconds
                )
                // Add to local history immediately (optimistic), sync to backend in background
                Task(priority: .utility) {
                    try? await HistorySync.shared.addToHistory(
                        scTrack,
                        userId: userId,
                        sessionId: sessionId,
                        queueIndex: pendingContext.queueIndex
                    )
                }
            }

        } catch {
            if Task.isCancelled || error is CancellationError {
                // User initiated another action; don't show failures for cancelled work.
                return
            }
            // Check if this is a recoverable error (timeout, server error, expired URL)
            let metadata = retryAttempts[pendingContext.track.id] ?? RetryMetadata()

            if isRecoverableError(error) && metadata.hasRetriesRemaining && !forceRefreshURL {
                // First failure with cached URL - retry immediately with fresh URL
                logWarning(.playback, "Recoverable error, retrying with fresh URL: \(error.localizedDescription)")

                // Invalidate the cached URL
                await streamCache.invalidate(trackId: pendingContext.track.id)

                // Retry with force refresh (don't increment counter yet)
                await startPlayback(with: pendingContext, requestId: requestId, startTime: startTime, forceRefreshURL: true)
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
            logError(.playback, "Playback failed (attempt \(updatedMetadata.attemptCount)/\(updatedMetadata.maxAttempts)): \(error)")
        }
    }

    // MARK: - Mix Mode Playback

    private func startMixPlayback(with context: PlaybackContext, requestId: UUID, startTime: Double? = nil, forceRefreshURL: Bool = false) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        guard activeRequestId == requestId else { return }

        status = .loading

        do {
            // Check for downloaded file first - use local file with fake stream data
            if let localURL = await DownloadManager.shared.getLocalFileURL(trackId: context.track.id) {
                logInfo(.playback, "[MixMode] Playing from local file: \(context.track.title)")

                // Create a pseudo CachedStreamData for local file
                let localStream = CachedStreamData(
                    url: localURL.absoluteString,
                    streamType: "local",
                    accessToken: ""
                )

                // Stop regular playback and switch to mix mode
                player.pause()
                player.removeAllItems()
                itemContextMap.removeAll()

                mixEngine.crossfadeSeconds = crossfadeSeconds
                mixEngine.prewarmSeconds = prewarmSeconds
                mixEngine.fadeCurve = fadeCurve

                guard isIntendedToPlay else {
                    status = .paused
                    return
                }

                mixEngine.play(context: context, streamData: localStream, startTime: startTime)
                isUsingMixMode = true
                currentContext = context
                handleTrackStartedPlaying(context: context)
                retryAttempts.removeValue(forKey: context.track.id)
                
                // Publish snapshot immediately so UI reflects the new track
                status = .playing
                publishSnapshot()

                if let userId = AuthManager.shared.currentUserId,
                   autoplayEnabled,
                   let scTrack = context.soundCloudTrack {
                    let sessionId = positionTracker.startSession(
                        trackId: context.track.id,
                        queueIndex: context.queueIndex,
                        duration: Double(scTrack.duration) / 1000.0
                    )
                    Task(priority: .utility) {
                        try? await HistorySync.shared.addToHistory(
                            scTrack,
                            userId: userId,
                            sessionId: sessionId,
                            queueIndex: context.queueIndex
                        )
                    }
                }
                return
            }

            // Determine if this is a Spotify track
            let permalinkUrl = context.soundCloudTrack?.permalink_url
            logInfo(.playback, "[MixMode] trackId=\(context.track.id), permalink_url=\(permalinkUrl ?? "nil"), soundCloudTrack=\(context.soundCloudTrack != nil)")
            
            let spotifyUrl = permalinkUrl.flatMap { url in
                (url.contains("spotify.com") || url.contains("spotify:")) ? url : nil
            }
            logInfo(.playback, "[MixMode] spotifyUrl=\(spotifyUrl ?? "nil")")

            let stream: CachedStreamData
            if forceRefreshURL {
                guard let freshStream = await streamCache.forceRefresh(for: context.track.id, spotifyUrl: spotifyUrl) else {
                    throw PlayerState.PlaybackError.invalidStreamURL
                }
                stream = freshStream
            } else {
                // Check if cached stream is expiring soon
                let deadline = Date().addingTimeInterval(30)
                let needsRefresh = await streamCache.isStreamExpiring(for: context.track.id, before: deadline)

                if needsRefresh {
                    guard let refreshedStream = await streamCache.forceRefresh(for: context.track.id, spotifyUrl: spotifyUrl) else {
                        throw PlayerState.PlaybackError.invalidStreamURL
                    }
                    stream = refreshedStream
                } else {
                    stream = try await streamCache.ensureStream(
                        for: context.track.id,
                        spotifyUrl: spotifyUrl,
                        priority: .userInitiated
                    )
                }
            }
            guard activeRequestId == requestId, !Task.isCancelled else { return }

            // Stop regular playback and switch to mix mode
            player.pause()
            player.removeAllItems()
            itemContextMap.removeAll()

            // Configure mix engine
            mixEngine.crossfadeSeconds = crossfadeSeconds
            mixEngine.prewarmSeconds = prewarmSeconds
            mixEngine.fadeCurve = fadeCurve

            // Only start audio if the user still intends to play (e.g., they didn’t pause mid-load).
            guard isIntendedToPlay else {
                status = .paused
                return
            }

            // Start mix playback
            mixEngine.play(context: context, streamData: stream, startTime: startTime)
            isUsingMixMode = true

            currentContext = context
            handleTrackStartedPlaying(context: context)

            logInfo(.playback, "[MixMode] Playback started: \(context.track.title)")

            // Clear retry metadata on success
            retryAttempts.removeValue(forKey: context.track.id)

            // Start position tracking and add to history (optimistic update)
            if let userId = AuthManager.shared.currentUserId,
               autoplayEnabled,
               let scTrack = context.soundCloudTrack {
                let sessionId = positionTracker.startSession(
                    trackId: context.track.id,
                    queueIndex: context.queueIndex,
                    duration: Double(scTrack.duration) / 1000.0
                )
                // Add to local history immediately (optimistic), sync to backend in background
                Task(priority: .utility) {
                    try? await HistorySync.shared.addToHistory(
                        scTrack,
                        userId: userId,
                        sessionId: sessionId,
                        queueIndex: context.queueIndex
                    )
                }
            }

            status = .playing
            
            // Publish snapshot immediately so UI reflects the new track
            publishSnapshot()

        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            // Check if this is a recoverable error
            let metadata = retryAttempts[context.track.id] ?? RetryMetadata()

            if isRecoverableError(error) && metadata.hasRetriesRemaining && !forceRefreshURL {
                logWarning(.playback, "[MixMode] Recoverable error, retrying with fresh URL: \(error.localizedDescription)")
                await streamCache.invalidate(trackId: context.track.id)
                await startMixPlayback(with: context, requestId: requestId, startTime: startTime, forceRefreshURL: true)
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
            logError(.playback, "[MixMode] Playback failed (attempt \(updatedMetadata.attemptCount)/\(updatedMetadata.maxAttempts)): \(error)")
        }
    }

    private func prepareItem(for context: PlaybackContext, forceRefresh: Bool = false) async throws -> AVPlayerItem {
        // Check for downloaded file first - instant offline playback
        if let localURL = await DownloadManager.shared.getLocalFileURL(trackId: context.track.id) {
            logInfo(.playback, "Playing from local file: \(context.track.title)")
            let asset = AVURLAsset(url: localURL)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 10
            return item
        }

        // Determine if this is a Spotify track (permalink_url contains spotify.com)
        let permalinkUrl = context.soundCloudTrack?.permalink_url
        logInfo(.playback, "[prepareItem] trackId=\(context.track.id), permalink_url=\(permalinkUrl ?? "nil")")
        
        let spotifyUrl = permalinkUrl.flatMap { url in
            (url.contains("spotify.com") || url.contains("spotify:")) ? url : nil
        }

        // Fall back to streaming
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
                logDebug(.playback, "Cached stream expiring soon, fetching fresh URL...")
                guard let refreshedStream = await streamCache.forceRefresh(for: context.track.id) else {
                    throw PlayerState.PlaybackError.invalidStreamURL
                }
                stream = refreshedStream
            } else {
                stream = try await streamCache.ensureStream(
                    for: context.track.id,
                    spotifyUrl: spotifyUrl,
                    priority: .userInitiated
                )
            }
        }

        guard let url = URL(string: stream.url) else {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        let asset: AVURLAsset
        if spotifyUrl != nil || stream.accessToken.isEmpty {
            // Spotify streams don't need OAuth headers
            asset = AVURLAsset(url: url)
        } else {
            // SoundCloud: Use OAuth token directly for CDN access
            let headers = ["Authorization": "OAuth \(stream.accessToken)"]
            asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ])
        }

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
        // Next is always queue.peek() - no index arithmetic needed
        // The current track is never in the queue (invariant)
        guard let nextItem = queueManager.queue.peek() else {
            return nil
        }

        return PlaybackContext(
            track: nextItem.track,
            soundCloudTrack: nextItem.soundCloudTrack,
            queueIndex: 0
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

                    logDebug(.playback, "Player waiting: \(reason.rawValue)")
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
                
                // For Spotify tracks, use track metadata duration (AVPlayer reports incorrect doubled duration)
                let isSpotifyTrack = self.currentContext?.soundCloudTrack?.permalink_url?.contains("spotify") == true
                let duration: Double = isSpotifyTrack
                    ? (self.currentContext?.track.duration ?? 0)
                    : CMTimeGetSeconds(self.player.currentItem?.duration ?? .invalid)

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
        Analytics.shared.track(
            "track_completed",
            properties: [
                "track_id": finishedContext.track.id,
                "duration_seconds": finishedContext.track.duration
            ]
        )

        itemContextMap.removeValue(forKey: finishedItem)

        if autoplayEnabled,
           let preloadedContext = nextPreloadedContext,
           let preloadedItem = nextPreloadedItem,
           preloadedContext == nextContext(after: finishedContext) {

            if preloadedItem.status == .readyToPlay {
                // Pop from queue since this track is now playing
                queueManager.popNext()

                handleTrackStartedPlaying(context: preloadedContext)
                nextPreloadedContext = nil
                nextPreloadedItem = nil
                hasPreloadedForCurrentTrack = false
                publishSnapshot()

                // Add to history (optimistic update) for autoplay transition
                if let userId = AuthManager.shared.currentUserId,
                   let scTrack = preloadedContext.soundCloudTrack {
                    let sessionId = positionTracker.startSession(
                        trackId: preloadedContext.track.id,
                        queueIndex: preloadedContext.queueIndex,
                        duration: Double(scTrack.duration) / 1000.0
                    )
                    Task(priority: .utility) {
                        try? await HistorySync.shared.addToHistory(
                            scTrack,
                            userId: userId,
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
                // Pop from queue since this track is about to play
                queueManager.popNext()

                player.remove(preloadedItem)
                nextPreloadedContext = nil
                nextPreloadedItem = nil
                itemContextMap.removeValue(forKey: preloadedItem)

                let requestId = activeRequestId
                Task {
                    await startPlayback(with: preloadedContext, requestId: requestId)
                }
                return
            }
        }

        adoptCurrentItemContext()
    }

    private func adoptCurrentItemContext() {
        if let currentItem = player.currentItem,
           let context = itemContextMap[currentItem] {
            // Pop from queue since this track is now playing
            queueManager.popNext()

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

        // When switching tracks, avoid reporting the previous item's time/duration during the loading gap.
        let isLoading = (status == .loading)
        let effectiveTime = isLoading ? 0 : (currentTime.isFinite ? currentTime : 0)
        
        // Spotify streams via YouTube have unreliable AVPlayer duration (often doubled).
        // Always trust the API-provided duration for Spotify tracks.
        let isSpotifyTrack = currentContext?.soundCloudTrack?.permalink_url?.contains("spotify") == true
        
        let effectiveDuration: Double = {
            if isLoading || isSpotifyTrack {
                return currentContext?.track.duration ?? 0
            }
            return duration.isFinite && duration > 0 ? duration : (currentContext?.track.duration ?? 0)
        }()

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
            currentTime: effectiveTime,
            duration: effectiveDuration
        )

        delegate?.playbackCoordinator(self, didUpdate: snapshot)
    }

    // MARK: - Prefetching

    func prefetchQueue() {
        let items = queueManager.queueItems
        guard !items.isEmpty else { return }

        let tracks = items.map { $0.track }
        let spotifyUrls = items.reduce(into: [String: String]()) { dict, item in
            if let url = item.soundCloudTrack?.permalink_url, url.contains("spotify") {
                dict[item.track.id] = url
            }
        }

        Task(priority: .utility) { [tracks, spotifyUrls] in
            await StreamURLCache.shared.prefetchUpcoming(tracks: tracks, spotifyUrls: spotifyUrls, lookAhead: 5)
        }
    }

    func prefetchTrack(_ track: Track, with soundCloudTrack: SoundCloudTrack?) {
        let spotifyUrl = soundCloudTrack?.permalink_url?.contains("spotify") == true
            ? soundCloudTrack?.permalink_url
            : nil
        Task(priority: .utility) { [trackId = track.id, spotifyUrl] in
            await StreamURLCache.shared.prefetchStreamURL(for: trackId, spotifyUrl: spotifyUrl)
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
            logInfo(.playback, "[MixObservability] mix_prewarm_start: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .prewarmReady(let trackId, let nextTrackId, let crossfade):
            logInfo(.playback, "[MixObservability] mix_prewarm_ready: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeStart(let trackId, let nextTrackId, let crossfade):
            logInfo(.playback, "[MixObservability] mix_fade_start: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeComplete(let trackId, let nextTrackId, let crossfade):
            logInfo(.playback, "[MixObservability] mix_fade_complete: \(trackId) -> \(nextTrackId), crossfade=\(crossfade)s")
        case .fadeAbort(let trackId, let nextTrackId, let crossfade, let reason):
            logWarning(.playback, "[MixObservability] mix_fade_abort(\(reason)): \(trackId) -> \(nextTrackId ?? "nil"), crossfade=\(crossfade)s")
        }
    }

    func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        // End position tracking for previous track
        positionTracker.endSession()

        // Pop from queue since this track is now playing
        queueManager.popNext()

        // Update current context
        currentContext = context
        handleTrackStartedPlaying(context: context)

        logInfo(.playback, "[MixMode] Transition complete: now playing \(track.title)")

        // Start position tracking and add to history (optimistic update)
        if let userId = AuthManager.shared.currentUserId,
           autoplayEnabled,
           let scTrack = context.soundCloudTrack {
            let sessionId = positionTracker.startSession(
                trackId: context.track.id,
                queueIndex: context.queueIndex,
                duration: Double(scTrack.duration) / 1000.0
            )
            Task(priority: .utility) {
                try? await HistorySync.shared.addToHistory(
                    scTrack,
                    userId: userId,
                    sessionId: sessionId,
                    queueIndex: context.queueIndex
                )
            }
        }

        publishSnapshot()

        // Reset crossfade visual state AFTER PlayerState.currentTrack updates via snapshot.
        // This prevents a 1-frame flicker back to the old artwork when the Metal overlay is removed.
        PlayerState.shared.crossfadeFromArtwork = ""
        PlayerState.shared.crossfadeProgress = 0
        PlayerState.shared.isCrossfading = false
        PlayerState.shared.crossfadeNextTrack = nil
        PlayerState.shared.crossfadeNextPosition = 0
        PlayerState.shared.crossfadeNextDuration = 0
    }

    func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        // Mix transition aborted - fallback to normal playback
        logWarning(.playback, "[MixMode] Transition aborted, falling back to normal playback")

        // Stop mix audio immediately before starting AVQueuePlayer playback to avoid overlap.
        engine.stop()

        // Reset crossfade visual state
        PlayerState.shared.crossfadeFromArtwork = ""
        PlayerState.shared.crossfadeProgress = 0
        PlayerState.shared.isCrossfading = false
        PlayerState.shared.crossfadeNextTrack = nil
        PlayerState.shared.crossfadeNextPosition = 0
        PlayerState.shared.crossfadeNextDuration = 0

        // If we have a next track context, try normal playback
        if let context = context {
            let requestId = activeRequestId
            Task {
                // Switch back to non-mix mode for fallback
                isUsingMixMode = false
                await startPlayback(with: context, requestId: requestId)
            }
        }
    }

    func mixEngineDidFinishTrack(_ engine: MixPlaybackEngine, track: Track, context: PlaybackContext) {
        // End position tracking for finished track
        positionTracker.endSession()

        guard autoplayEnabled else {
            isIntendedToPlay = false
            status = .ready
            publishSnapshot()
            return
        }

        // Advance using the same "top of cue" logic as manual Next.
        playNext(manual: false)
    }

    func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double) {
        // Track position for periodic flush
        if currentTime.isFinite && duration.isFinite {
            positionTracker.updatePosition(currentTime, duration: duration)
        }

        // Publish snapshot to update UI
        publishSnapshot()
    }

    func mixEngineDidUpdateCrossfadeProgress(_ engine: MixPlaybackEngine, progress: Double, nextTrack: Track?) {
        // Capture and prefetch crossfade artwork at the very start so visuals never
        // briefly render with a missing `nextTrack` or a changing `from` artwork.
        if progress <= 0.0001 {
            if let nextTrack {
                if PlayerState.shared.crossfadeFromArtwork.isEmpty {
                    PlayerState.shared.crossfadeFromArtwork = PlayerState.shared.currentTrack.artwork
                }
                Task(priority: .utility) {
                    await preloadCrossfadeArtwork(from: PlayerState.shared.crossfadeFromArtwork, to: nextTrack.artwork)
                }
            } else {
                PlayerState.shared.crossfadeFromArtwork = ""
            }
        }

        // Update PlayerState for visual transitions (order matters to avoid transient flicker):
        // set nextTrack first, then progress, then isCrossfading last.
        PlayerState.shared.crossfadeNextTrack = nextTrack
        PlayerState.shared.crossfadeNextPosition = engine.nextTime
        PlayerState.shared.crossfadeNextDuration = engine.nextDuration
        PlayerState.shared.crossfadeProgress = progress

        // Keep isCrossfading true at progress=1.0 to prevent flicker; we reset after track swap.
        PlayerState.shared.isCrossfading = progress > 0 && progress <= 1.0
    }
}

// MARK: - Crossfade Artwork Prefetch

@MainActor
private func preloadCrossfadeArtwork(from: String, to: String) async {
    // Fill MemoryImageCache so SwiftUI and Metal can both render without placeholders.
    if from.starts(with: "http"), let url = URL(string: from) {
        _ = await ImageCacheManager.shared.getImage(for: url)
    }
    if to.starts(with: "http"), let url = URL(string: to) {
        _ = await ImageCacheManager.shared.getImage(for: url)
    }
}
