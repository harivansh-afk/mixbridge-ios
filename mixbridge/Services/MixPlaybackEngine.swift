//
//  MixPlaybackEngine.swift
//  mixbridge
//
//  Mix Mode playback engine using two concurrent AVPlayers.
//  Handles prewarm, crossfade, and observability events.
//

import AVFoundation
import Foundation

// Import MixCore types from the local package
// Note: When integrated, these will be imported from MixbridgeMixCore

/// Observability events for Mix Mode
enum MixObservabilityEvent {
    case prewarmStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case prewarmReady(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeComplete(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeAbort(trackId: String, nextTrackId: String?, crossfadeSeconds: Double, reason: String)
}

/// Delegate for MixPlaybackEngine events
@MainActor
protocol MixPlaybackEngineDelegate: AnyObject {
    func mixEngine(_ engine: MixPlaybackEngine, didEmit event: MixObservabilityEvent)
    func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext)
    func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?)
    func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double)
    func mixEngineDidUpdateCrossfadeProgress(_ engine: MixPlaybackEngine, progress: Double, nextTrack: Track?)
}

/// Context for mix playback (reuses PlaybackContext from PlaybackCoordinator)
typealias MixTrackContext = PlaybackContext

/// Mix Mode playback engine using two AVPlayers
/// Handles prewarm and crossfade transitions
@MainActor
final class MixPlaybackEngine {

    // MARK: - Public Properties

    weak var delegate: MixPlaybackEngineDelegate?

    var crossfadeSeconds: Double = 6
    var prewarmSeconds: Double = 15
    var fadeCurve: FadeCurve = .equalPower

    var isPlaying: Bool {
        currentPlayer.timeControlStatus == .playing
    }

    var currentTime: Double {
        CMTimeGetSeconds(currentPlayer.currentTime())
    }

    var duration: Double {
        guard let item = currentPlayer.currentItem else { return 0 }
        let dur = CMTimeGetSeconds(item.duration)
        return dur.isFinite ? dur : 0
    }

    /// Next track's current time (during crossfade)
    var nextTime: Double {
        guard let player = nextPlayer else { return 0 }
        return CMTimeGetSeconds(player.currentTime())
    }

    /// Next track's duration (during crossfade)
    var nextDuration: Double {
        guard let player = nextPlayer, let item = player.currentItem else { return 0 }
        let dur = CMTimeGetSeconds(item.duration)
        return dur.isFinite ? dur : 0
    }

    // MARK: - Private Properties

    private var currentPlayer = AVPlayer()
    private var nextPlayer: AVPlayer?

    private var currentContext: MixTrackContext?
    private var nextContext: MixTrackContext?

    private var state: MixModeState = .singlePlaying
    private var isNextReady = false

    private var timeObserverToken: Any?
    private var currentItemObservation: NSKeyValueObservation?
    private var nextItemObservation: NSKeyValueObservation?
    private var nextReadinessObservation: NSKeyValueObservation?

    private let streamCache = StreamURLCache.shared
    private let queueManager = QueueManager.shared

    private var fadeDisplayLink: CADisplayLink?
    private var fadeStartTime: Date?
    private var effectiveCrossfadeDuration: Double = 0

    // MARK: - State

    private enum MixModeState {
        case singlePlaying
        case prewarmingNext
        case crossfading
    }

    // MARK: - Initialization

    init() {
        currentPlayer.automaticallyWaitsToMinimizeStalling = true
        setupTimeObserver()
    }

    // MARK: - Public API

    func play(context: MixTrackContext, streamData: CachedStreamData, startTime: Double? = nil) {
        cleanup()

        currentContext = context
        state = .singlePlaying
        isNextReady = false

        let item = createPlayerItem(from: streamData)
        currentPlayer.replaceCurrentItem(with: item)

        if let startTime = startTime, startTime > 0 {
            let time = CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            currentPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        currentPlayer.volume = 1.0
        currentPlayer.play()

        // Re-add time observer after cleanup removed it
        setupTimeObserver()
        observeCurrentItem(item)
    }

    func pause() {
        currentPlayer.pause()
        nextPlayer?.pause()
    }

    func resume() {
        currentPlayer.play()
        if state == .crossfading {
            nextPlayer?.play()
        }
    }

    func seek(to time: Double) {
        let wasPlaying = currentPlayer.timeControlStatus == .playing

        // Abort any active mix transition if seeking before prewarm start
        if state != .singlePlaying {
            let schedule = computeSchedule()
            if let schedule = schedule, time < schedule.prewarmStartTime {
                abortMixTransition(reason: "seek_cancelled")
            }
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        currentPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished, wasPlaying else { return }
            Task { @MainActor in
                self.currentPlayer.play()
            }
        }
    }

    func setVolume(_ volume: Double) {
        // Only set volume on current player if not in crossfade
        if state != .crossfading {
            currentPlayer.volume = Float(volume)
        }
    }

    func skipToNext() {
        if state == .crossfading, let nextPlayer = nextPlayer {
            // Snap to next: set next to full volume, stop current
            nextPlayer.volume = 1.0
            currentPlayer.pause()
            currentPlayer.volume = 0

            promotNextToCurrent()
            emitEvent(.fadeComplete(
                trackId: currentContext?.track.id ?? "",
                nextTrackId: nextContext?.track.id ?? "",
                crossfadeSeconds: crossfadeSeconds
            ))
        }
    }

    func handleQueueChanged() {
        if state != .singlePlaying {
            abortMixTransition(reason: "queue_changed")
        }
    }

    func handleMixDisabled() {
        if state != .singlePlaying {
            abortMixTransition(reason: "disabled")
        }
    }

    func stop() {
        cleanup()
    }

    // MARK: - Private Methods

    private func setupTimeObserver() {
        timeObserverToken = currentPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimeUpdate()
            }
        }
    }

    private func handleTimeUpdate() {
        let currentTime = self.currentTime
        let duration = self.duration

        // Always notify delegate for UI updates
        delegate?.mixEngineDidUpdateTime(self, currentTime: currentTime, duration: duration)

        guard let schedule = computeSchedule() else { return }

        switch state {
        case .singlePlaying:
            // Check if we should start prewarming
            if currentTime >= schedule.prewarmStartTime && schedule.isCrossfadeEnabled {
                startPrewarm(schedule: schedule)
            }

        case .prewarmingNext:
            // Check if we should start crossfading
            if isNextReady && currentTime >= schedule.fadeStartTime {
                startCrossfade(schedule: schedule)
            }

        case .crossfading:
            // Crossfade is handled by display link
            break
        }
    }

    private func computeSchedule() -> MixScheduleInfo? {
        guard duration > 0 else { return nil }

        let clampedCrossfade = max(0, min(12, crossfadeSeconds))
        let clampedPrewarm = max(0, min(60, prewarmSeconds))

        let effectiveCrossfade = min(clampedCrossfade, floor(duration / 2))
        let fadeStartTime = max(0, duration - effectiveCrossfade)
        let prewarmLeadTime = max(clampedPrewarm, effectiveCrossfade)
        let prewarmStartTime = max(0, duration - prewarmLeadTime)

        return MixScheduleInfo(
            effectiveCrossfade: effectiveCrossfade,
            fadeStartTime: fadeStartTime,
            prewarmStartTime: prewarmStartTime,
            duration: duration,
            isCrossfadeEnabled: effectiveCrossfade > 0
        )
    }

    private struct MixScheduleInfo {
        let effectiveCrossfade: Double
        let fadeStartTime: Double
        let prewarmStartTime: Double
        let duration: Double
        let isCrossfadeEnabled: Bool
    }

    // MARK: - Prewarm

    private func startPrewarm(schedule: MixScheduleInfo) {
        guard let currentCtx = currentContext else { return }

        // Get next track from queue
        // Note: The currently playing track may have been removed from queue,
        // so we check if it's still there to determine the correct "next" track
        let next: (track: Track, index: Int)?
        if let trackIndex = queueManager.indexOfTrack(withId: currentCtx.track.id) {
            // Current track is still in queue, get the one after it
            next = queueManager.nextTrack(after: trackIndex)
        } else {
            // Current track was removed from queue, first track in queue is the "next"
            if let firstTrack = queueManager.queueTracks.first {
                next = (firstTrack, 0)
            } else {
                next = nil
            }
        }

        guard let next = next else {
            // No next track - no prewarm needed
            return
        }

        let nextTrack = next.track
        let nextSCTrack = queueManager.soundCloudTrack(for: nextTrack.id)
        nextContext = MixTrackContext(track: nextTrack, soundCloudTrack: nextSCTrack, queueIndex: next.index)

        state = .prewarmingNext
        isNextReady = false

        emitEvent(.prewarmStart(
            trackId: currentCtx.track.id,
            nextTrackId: nextTrack.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo("[MixEngine] mix_prewarm_start: \(nextTrack.title)")

        // Check if we need to refresh the stream
        let deadline = Date().addingTimeInterval(crossfadeSeconds + 15)

        Task {
            do {
                // Force refresh if stream is expiring
                let needsRefresh = await streamCache.isStreamExpiring(for: nextTrack.id, before: deadline)
                let streamData: CachedStreamData

                if needsRefresh {
                    // Force refresh
                    guard let refreshed = await streamCache.forceRefresh(for: nextTrack.id) else {
                        throw NSError(domain: "MixEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stream refresh failed"])
                    }
                    streamData = refreshed
                } else {
                    // Get cached or fetch fresh
                    streamData = try await streamCache.ensureStream(for: nextTrack.id, priority: .userInitiated)
                }

                await prepareNextPlayer(with: streamData)
            } catch {
                logError("[MixEngine] Prewarm failed: \(error)")
                abortMixTransition(reason: "stream_refresh_failed")
            }
        }
    }

    private func prepareNextPlayer(with streamData: CachedStreamData) {
        guard state == .prewarmingNext else { return }

        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 0 // Start silent

        let item = createPlayerItem(from: streamData)
        player.replaceCurrentItem(with: item)

        nextPlayer = player

        // Observe readiness
        nextItemObservation?.invalidate()
        nextItemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleNextItemStatusChange(item)
            }
        }

        nextReadinessObservation?.invalidate()
        nextReadinessObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    self?.handleNextReady()
                }
            }
        }
    }

    private func handleNextItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            if item.isPlaybackLikelyToKeepUp {
                handleNextReady()
            }
        case .failed:
            logError("[MixEngine] Next item failed: \(item.error?.localizedDescription ?? "unknown")")
            abortMixTransition(reason: "not_ready")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleNextReady() {
        guard state == .prewarmingNext, !isNextReady else { return }
        isNextReady = true

        guard let currentCtx = currentContext, let nextCtx = nextContext else { return }

        emitEvent(.prewarmReady(
            trackId: currentCtx.track.id,
            nextTrackId: nextCtx.track.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo("[MixEngine] mix_prewarm_ready: \(nextCtx.track.title)")
    }

    // MARK: - Crossfade

    private func startCrossfade(schedule: MixScheduleInfo) {
        guard let currentCtx = currentContext,
              let nextCtx = nextContext,
              let nextPlayer = nextPlayer else {
            abortMixTransition(reason: "not_ready")
            return
        }

        state = .crossfading
        effectiveCrossfadeDuration = schedule.effectiveCrossfade
        fadeStartTime = Date()

        // Start next player
        nextPlayer.play()

        emitEvent(.fadeStart(
            trackId: currentCtx.track.id,
            nextTrackId: nextCtx.track.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo("[MixEngine] mix_fade_start: crossfading to \(nextCtx.track.title)")

        // Initialize crossfade progress for visual transition
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: 0, nextTrack: nextCtx.track)

        // Start display link for smooth volume ramping
        startFadeDisplayLink()
    }

    private func startFadeDisplayLink() {
        fadeDisplayLink?.invalidate()
        fadeDisplayLink = CADisplayLink(target: self, selector: #selector(updateFade))
        fadeDisplayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateFade() {
        guard state == .crossfading,
              let fadeStart = fadeStartTime,
              let nextPlayer = nextPlayer else {
            fadeDisplayLink?.invalidate()
            fadeDisplayLink = nil
            return
        }

        let elapsed = Date().timeIntervalSince(fadeStart)
        let progress = min(1.0, elapsed / effectiveCrossfadeDuration)

        // Notify delegate of crossfade progress for visual transitions
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextContext?.track)

        // Apply selected fade curve
        let currentGain = fadeCurve.fadeOutGain(progress: progress)
        let nextGain = fadeCurve.fadeInGain(progress: progress)

        currentPlayer.volume = currentGain
        nextPlayer.volume = nextGain

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    private func completeCrossfade() {
        fadeDisplayLink?.invalidate()
        fadeDisplayLink = nil

        guard let currentCtx = currentContext, let nextCtx = nextContext else { return }

        // Signal crossfade complete for visual transition
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: 1.0, nextTrack: nextCtx.track)

        emitEvent(.fadeComplete(
            trackId: currentCtx.track.id,
            nextTrackId: nextCtx.track.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo("[MixEngine] mix_fade_complete: now playing \(nextCtx.track.title)")

        promotNextToCurrent()
    }

    private func promotNextToCurrent() {
        // Remove time observer from OLD player before swapping
        if let token = timeObserverToken {
            currentPlayer.removeTimeObserver(token)
            timeObserverToken = nil
        }

        // Stop and release old current player
        currentPlayer.pause()
        currentItemObservation?.invalidate()

        // Promote next to current
        if let nextPlayer = nextPlayer {
            currentPlayer = nextPlayer
            currentPlayer.volume = 1.0

            // Re-add time observer to NEW currentPlayer
            setupTimeObserver()
            observeCurrentItem(currentPlayer.currentItem)
        }

        // Update context
        if let nextCtx = nextContext {
            let playbackContext = PlaybackContext(
                track: nextCtx.track,
                soundCloudTrack: nextCtx.soundCloudTrack,
                queueIndex: nextCtx.queueIndex
            )
            currentContext = nextCtx
            delegate?.mixEngine(self, didCompleteTransitionTo: nextCtx.track, context: playbackContext)
        }

        // Clear next state
        self.nextPlayer = nil
        nextContext = nil
        nextItemObservation?.invalidate()
        nextReadinessObservation?.invalidate()
        isNextReady = false
        state = .singlePlaying
    }

    private func abortMixTransition(reason: String) {
        guard state != .singlePlaying else { return }

        fadeDisplayLink?.invalidate()
        fadeDisplayLink = nil

        // Reset crossfade progress for visual transition
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: 0, nextTrack: nil)

        // Restore current player volume
        currentPlayer.volume = 1.0

        // Stop and release next player
        nextPlayer?.pause()
        nextPlayer = nil
        nextItemObservation?.invalidate()
        nextReadinessObservation?.invalidate()

        let currentTrackId = currentContext?.track.id ?? ""
        let nextTrackId = nextContext?.track.id

        emitEvent(.fadeAbort(
            trackId: currentTrackId,
            nextTrackId: nextTrackId,
            crossfadeSeconds: crossfadeSeconds,
            reason: reason
        ))

        logInfo("[MixEngine] mix_fade_abort(\(reason))")

        // Notify delegate for fallback handling
        if let nextCtx = nextContext {
            let playbackContext = PlaybackContext(
                track: nextCtx.track,
                soundCloudTrack: nextCtx.soundCloudTrack,
                queueIndex: nextCtx.queueIndex
            )
            delegate?.mixEngine(self, didAbortWithFallback: nextCtx.track, context: playbackContext)
        }

        nextContext = nil
        isNextReady = false
        state = .singlePlaying
    }

    // MARK: - Helpers

    private func createPlayerItem(from streamData: CachedStreamData) -> AVPlayerItem {
        guard let url = URL(string: streamData.url) else {
            // Return an empty item - will fail on play
            return AVPlayerItem(url: URL(string: "about:blank")!)
        }

        let headers = ["Authorization": "OAuth \(streamData.accessToken)"]
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        return item
    }

    private func observeCurrentItem(_ item: AVPlayerItem?) {
        currentItemObservation?.invalidate()
        guard let item = item else { return }

        currentItemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    logError("[MixEngine] Current item failed: \(item.error?.localizedDescription ?? "unknown")")
                }
            }
        }

        // Observe end of track
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentItemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc private func handleCurrentItemDidEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item == currentPlayer.currentItem else { return }

        // If we're not crossfading and track ended, the coordinator handles next
        if state == .singlePlaying {
            // Normal end - coordinator will handle
        }
    }

    private func emitEvent(_ event: MixObservabilityEvent) {
        delegate?.mixEngine(self, didEmit: event)
    }

    private func cleanup() {
        fadeDisplayLink?.invalidate()
        fadeDisplayLink = nil

        if let token = timeObserverToken {
            currentPlayer.removeTimeObserver(token)
            timeObserverToken = nil
        }

        currentItemObservation?.invalidate()
        nextItemObservation?.invalidate()
        nextReadinessObservation?.invalidate()

        currentPlayer.pause()
        nextPlayer?.pause()
        nextPlayer = nil

        NotificationCenter.default.removeObserver(self)

        currentContext = nil
        nextContext = nil
        state = .singlePlaying
        isNextReady = false
    }
}
