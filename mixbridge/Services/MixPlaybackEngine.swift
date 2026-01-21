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
    func mixEngineDidFinishTrack(_ engine: MixPlaybackEngine, track: Track, context: PlaybackContext)
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
    var allowAutoAdvance: Bool = true
    var loopCurrentTrack: Bool = false

    var isPlaying: Bool {
        currentPlayer.timeControlStatus == .playing
    }

    var currentTime: Double {
        CMTimeGetSeconds(currentPlayer.currentTime())
    }

    var duration: Double {
        // Spotify streams via YouTube report incorrect (doubled) duration from AVPlayer.
        // Always trust track metadata duration for Spotify tracks.
        if let ctx = currentContext,
           ctx.soundCloudTrack?.permalink_url?.contains("spotify") == true {
            return ctx.track.duration
        }
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
        // Spotify streams via YouTube report incorrect (doubled) duration from AVPlayer.
        if let ctx = nextContext,
           ctx.soundCloudTrack?.permalink_url?.contains("spotify") == true {
            return ctx.track.duration
        }
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

    private var fadeTimer: Timer?
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
                abortMixTransition(reason: "seek_cancelled", shouldFallbackToNext: false)
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

    /// Trigger an instant mix transition when user manually presses forward.
    /// Handles all states: singlePlaying, prewarmingNext, and crossfading.
    /// Returns true if instant mix was triggered, false if caller should fall back to normal skip.
    func triggerInstantMix() -> Bool {
        switch state {
        case .crossfading:
            // Already crossfading - snap to the end
            skipToNext()
            return true

        case .prewarmingNext:
            // Next track is prewarming - start instant crossfade if ready
            if isNextReady {
                let instantSchedule = MixScheduleInfo(
                    effectiveCrossfade: 2.0,
                    fadeStartTime: currentTime,
                    prewarmStartTime: currentTime,
                    duration: duration,
                    isCrossfadeEnabled: true
                )
                startCrossfade(schedule: instantSchedule)
                return true
            } else {
                // Not ready yet - fall back to normal skip
                return false
            }

        case .singlePlaying:
            // Need to prewarm and crossfade immediately
            guard let currentCtx = currentContext,
                  let nextItem = queueManager.queue.peek() else {
                return false
            }

            let nextTrack = nextItem.track
            nextContext = MixTrackContext(track: nextTrack, soundCloudTrack: nextItem.soundCloudTrack, queueIndex: 0)

            state = .prewarmingNext
            isNextReady = false

            emitEvent(.prewarmStart(
                trackId: currentCtx.track.id,
                nextTrackId: nextTrack.id,
                crossfadeSeconds: 2.0
            ))

            logInfo(.playback, "[MixEngine] instant_mix_triggered: prewarming \(nextTrack.title)")

            let scTrack = nextItem.soundCloudTrack
            Task {
                do {
                    // Check for downloaded file first - instant offline playback
                    if let localURL = await DownloadManager.shared.getLocalFileURL(trackId: nextTrack.id) {
                        logInfo(.playback, "[MixEngine] Instant mix from local file: \(nextTrack.title)")
                        let localStream = CachedStreamData(
                            url: localURL.absoluteString,
                            streamType: "local",
                            accessToken: ""
                        )
                        await prepareAndStartInstantCrossfade(with: localStream)
                        return
                    }

                    // Determine if this is a Spotify track
                    let spotifyUrl = scTrack?.permalink_url.flatMap { url in
                        (url.contains("spotify.com") || url.contains("spotify:")) ? url : nil
                    }

                    // Fall back to streaming
                    let streamData = try await streamCache.ensureStream(
                        for: nextTrack.id,
                        spotifyUrl: spotifyUrl,
                        priority: .userInitiated
                    )
                    await prepareAndStartInstantCrossfade(with: streamData)
                } catch {
                    logError(.playback, "[MixEngine] Instant mix prewarm failed: \(error)")
                    abortMixTransition(reason: "instant_mix_failed", shouldFallbackToNext: true)
                }
            }
            return true
        }
    }

    private func prepareAndStartInstantCrossfade(with streamData: CachedStreamData) async {
        guard state == .prewarmingNext else { return }

        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 0

        let item = createPlayerItem(from: streamData)
        player.replaceCurrentItem(with: item)
        nextPlayer = player

        // Wait for readiness with timeout
        let startTime = Date()
        let timeout: TimeInterval = 5.0

        while !item.isPlaybackLikelyToKeepUp && item.status != .failed {
            if Date().timeIntervalSince(startTime) > timeout {
                logWarning(.playback, "[MixEngine] Instant mix timeout waiting for readiness")
                abortMixTransition(reason: "instant_mix_timeout", shouldFallbackToNext: true)
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        guard item.status == .readyToPlay else {
            abortMixTransition(reason: "instant_mix_not_ready", shouldFallbackToNext: true)
            return
        }

        isNextReady = true

        let instantSchedule = MixScheduleInfo(
            effectiveCrossfade: 2.0,
            fadeStartTime: currentTime,
            prewarmStartTime: currentTime,
            duration: duration,
            isCrossfadeEnabled: true
        )
        startCrossfade(schedule: instantSchedule)
    }

    func handleQueueChanged() {
        if state != .singlePlaying {
            abortMixTransition(reason: "queue_changed", shouldFallbackToNext: false)
        }
    }

    func handleMixDisabled() {
        if state != .singlePlaying {
            abortMixTransition(reason: "disabled", shouldFallbackToNext: false)
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
                guard let self else { return }
                self.handleTimeUpdate()
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
            if (allowAutoAdvance || loopCurrentTrack),
               currentTime >= schedule.prewarmStartTime && schedule.isCrossfadeEnabled {
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

        if loopCurrentTrack {
            let nextTrack = currentCtx.track
            let scTrack = currentCtx.soundCloudTrack
            nextContext = MixTrackContext(track: nextTrack, soundCloudTrack: scTrack, queueIndex: currentCtx.queueIndex)

            state = .prewarmingNext
            isNextReady = false

            emitEvent(.prewarmStart(
                trackId: currentCtx.track.id,
                nextTrackId: nextTrack.id,
                crossfadeSeconds: crossfadeSeconds
            ))

            logInfo(.playback, "[MixEngine] mix_prewarm_start(loop): \(nextTrack.title)")

            Task {
                do {
                    // Check for downloaded file first - instant offline playback
                    if let localURL = await DownloadManager.shared.getLocalFileURL(trackId: nextTrack.id) {
                        logInfo(.playback, "[MixEngine] Prewarming from local file: \(nextTrack.title)")
                        let localStream = CachedStreamData(
                            url: localURL.absoluteString,
                            streamType: "local",
                            accessToken: ""
                        )
                        prepareNextPlayer(with: localStream)
                        return
                    }

                    // Determine if this is a Spotify track
                    let spotifyUrl = scTrack?.permalink_url.flatMap { url in
                        (url.contains("spotify.com") || url.contains("spotify:")) ? url : nil
                    }

                    // Fall back to streaming - check if we need to refresh
                    let deadline = Date().addingTimeInterval(crossfadeSeconds + 15)
                    let needsRefresh = await streamCache.isStreamExpiring(for: nextTrack.id, before: deadline)
                    let streamData: CachedStreamData

                    if needsRefresh {
                        // Force refresh (pass spotifyUrl for Spotify tracks)
                        guard let refreshed = await streamCache.forceRefresh(for: nextTrack.id, spotifyUrl: spotifyUrl) else {
                            throw NSError(domain: "MixEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stream refresh failed"])
                        }
                        streamData = refreshed
                    } else {
                        // Get cached or fetch fresh
                        streamData = try await streamCache.ensureStream(
                            for: nextTrack.id,
                            spotifyUrl: spotifyUrl,
                            priority: .userInitiated
                        )
                    }

                    prepareNextPlayer(with: streamData)
                } catch {
                    logError(.playback, "[MixEngine] Prewarm failed: \(error)")
                    // Prewarm failures should not abruptly skip tracks; just cancel the transition.
                    abortMixTransition(reason: "stream_refresh_failed", shouldFallbackToNext: false)
                }
            }
            return
        }

        // Get next track from queue - always queue.peek()
        // The current track is never in the queue (invariant)
        guard let nextItem = queueManager.queue.peek() else {
            // No next track - no prewarm needed
            return
        }

        let nextTrack = nextItem.track
        nextContext = MixTrackContext(track: nextTrack, soundCloudTrack: nextItem.soundCloudTrack, queueIndex: 0)

        state = .prewarmingNext
        isNextReady = false

        emitEvent(.prewarmStart(
            trackId: currentCtx.track.id,
            nextTrackId: nextTrack.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo(.playback, "[MixEngine] mix_prewarm_start: \(nextTrack.title)")

        let scTrack = nextItem.soundCloudTrack
        Task {
            do {
                // Check for downloaded file first - instant offline playback
                if let localURL = await DownloadManager.shared.getLocalFileURL(trackId: nextTrack.id) {
                    logInfo(.playback, "[MixEngine] Prewarming from local file: \(nextTrack.title)")
                    let localStream = CachedStreamData(
                        url: localURL.absoluteString,
                        streamType: "local",
                        accessToken: ""
                    )
                    prepareNextPlayer(with: localStream)
                    return
                }

                // Determine if this is a Spotify track
                let spotifyUrl = scTrack?.permalink_url.flatMap { url in
                    (url.contains("spotify.com") || url.contains("spotify:")) ? url : nil
                }

                // Fall back to streaming - check if we need to refresh
                let deadline = Date().addingTimeInterval(crossfadeSeconds + 15)
                let needsRefresh = await streamCache.isStreamExpiring(for: nextTrack.id, before: deadline)
                let streamData: CachedStreamData

                if needsRefresh {
                    // Force refresh (pass spotifyUrl for Spotify tracks)
                    guard let refreshed = await streamCache.forceRefresh(for: nextTrack.id, spotifyUrl: spotifyUrl) else {
                        throw NSError(domain: "MixEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stream refresh failed"])
                    }
                    streamData = refreshed
                } else {
                    // Get cached or fetch fresh
                    streamData = try await streamCache.ensureStream(
                        for: nextTrack.id,
                        spotifyUrl: spotifyUrl,
                        priority: .userInitiated
                    )
                }

                prepareNextPlayer(with: streamData)
            } catch {
                logError(.playback, "[MixEngine] Prewarm failed: \(error)")
                // Prewarm failures should not abruptly skip tracks; just cancel the transition.
                abortMixTransition(reason: "stream_refresh_failed", shouldFallbackToNext: false)
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
                guard let self else { return }
                self.handleNextItemStatusChange(item)
            }
        }

        nextReadinessObservation?.invalidate()
        nextReadinessObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    guard let self else { return }
                    self.handleNextReady()
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
            logError(.playback, "[MixEngine] Next item failed: \(item.error?.localizedDescription ?? "unknown")")
            // Don't skip; keep current playing and let coordinator advance at end.
            abortMixTransition(reason: "not_ready", shouldFallbackToNext: false)
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

        logInfo(.playback, "[MixEngine] mix_prewarm_ready: \(nextCtx.track.title)")
    }

    // MARK: - Crossfade

    private func startCrossfade(schedule: MixScheduleInfo) {
        guard let currentCtx = currentContext,
              let nextCtx = nextContext,
              let nextPlayer = nextPlayer else {
            abortMixTransition(reason: "not_ready", shouldFallbackToNext: false)
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

        logInfo(.playback, "[MixEngine] mix_fade_start: crossfading to \(nextCtx.track.title)")

        // Initialize crossfade progress for visual transition
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: 0, nextTrack: nextCtx.track)

        // Start timer for smooth volume ramping (Timer works when screen is off, CADisplayLink doesn't)
        startFadeTimer()
    }

    private func startFadeTimer() {
        fadeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateFade()
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func updateFade() {
        guard state == .crossfading,
              let fadeStart = fadeStartTime,
              let nextPlayer = nextPlayer else {
            fadeTimer?.invalidate()
            fadeTimer = nil
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
        fadeTimer?.invalidate()
        fadeTimer = nil

        guard let currentCtx = currentContext, let nextCtx = nextContext else { return }

        // Signal crossfade complete for visual transition
        delegate?.mixEngineDidUpdateCrossfadeProgress(self, progress: 1.0, nextTrack: nextCtx.track)

        emitEvent(.fadeComplete(
            trackId: currentCtx.track.id,
            nextTrackId: nextCtx.track.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        logInfo(.playback, "[MixEngine] mix_fade_complete: now playing \(nextCtx.track.title)")

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

    private func abortMixTransition(reason: String, shouldFallbackToNext: Bool) {
        guard state != .singlePlaying else { return }

        fadeTimer?.invalidate()
        fadeTimer = nil

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

        logInfo(.playback, "[MixEngine] mix_fade_abort(\(reason))")

        // Optionally notify delegate for fallback handling.
        // Most aborts (queue changes, seeks, user toggles) should *not* change tracks.
        if shouldFallbackToNext, let nextCtx = nextContext {
            let playbackContext = PlaybackContext(track: nextCtx.track, soundCloudTrack: nextCtx.soundCloudTrack, queueIndex: nextCtx.queueIndex)
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

        let asset: AVURLAsset
        if streamData.streamType == "local" || streamData.accessToken.isEmpty {
            // Local file or Spotify stream - no OAuth headers needed
            asset = AVURLAsset(url: url)
        } else {
            // SoundCloud remote stream - add OAuth headers
            let headers = ["Authorization": "OAuth \(streamData.accessToken)"]
            asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ])
        }

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
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    // Duration is now available - notify delegate for UI update
                    // Use self.duration which handles Spotify duration override
                    let dur = self.duration
                    if dur > 0 {
                        self.delegate?.mixEngineDidUpdateTime(self, currentTime: self.currentTime, duration: dur)
                    }
                case .failed:
                    logError(.playback, "[MixEngine] Current item failed: \(item.error?.localizedDescription ?? "unknown")")
                case .unknown:
                    break
                @unknown default:
                    break
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

        // If we're not crossfading and the track ended, ask the coordinator to advance.
        if state == .singlePlaying, let ctx = currentContext {
            let playbackContext = PlaybackContext(track: ctx.track, soundCloudTrack: ctx.soundCloudTrack, queueIndex: ctx.queueIndex)
            delegate?.mixEngineDidFinishTrack(self, track: ctx.track, context: playbackContext)
        }
    }

    private func emitEvent(_ event: MixObservabilityEvent) {
        delegate?.mixEngine(self, didEmit: event)
    }

    private func cleanup() {
        fadeTimer?.invalidate()
        fadeTimer = nil

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
