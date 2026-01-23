import AVFoundation
import Foundation
import MixBridgeDJ

enum UnifiedMixBackend: Sendable {
    case streaming
    case dj
}

enum UnifiedMixObservabilityEvent: Sendable, Equatable {
    case prewarmStart(backend: UnifiedMixBackend, trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case prewarmReady(backend: UnifiedMixBackend, trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeScheduled(backend: UnifiedMixBackend, trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeStart(backend: UnifiedMixBackend, trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeComplete(backend: UnifiedMixBackend, trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeAbort(backend: UnifiedMixBackend, trackId: String, nextTrackId: String?, crossfadeSeconds: Double, reason: String)
}

@MainActor
protocol UnifiedMixEngineDelegate: AnyObject {
    func unifiedMixEngine(_ engine: UnifiedMixEngine, didEmit event: UnifiedMixObservabilityEvent)
    func unifiedMixEngine(_ engine: UnifiedMixEngine, didCompleteTransitionTo track: Track, context: PlaybackContext)
    func unifiedMixEngine(_ engine: UnifiedMixEngine, didAbortWithFallback track: Track?, context: PlaybackContext?)
    func unifiedMixEngineDidFinishTrack(_ engine: UnifiedMixEngine, track: Track, context: PlaybackContext)
    func unifiedMixEngineDidUpdateTime(_ engine: UnifiedMixEngine, currentTime: Double, duration: Double)
    func unifiedMixEngineDidUpdateCrossfadeProgress(_ engine: UnifiedMixEngine, progress: Double, nextTrack: Track?)
}

@MainActor
final class UnifiedMixEngine {
    weak var delegate: UnifiedMixEngineDelegate?

    var crossfadeSeconds: Double = 6 {
        didSet {
            streamingEngine.crossfadeSeconds = crossfadeSeconds
            djEngine.crossfadeSeconds = crossfadeSeconds
        }
    }

    var prewarmSeconds: Double = 15 {
        didSet {
            streamingEngine.prewarmSeconds = prewarmSeconds
            djEngine.prewarmSeconds = prewarmSeconds
        }
    }

    var fadeCurve: DJCrossfadeCurve = .equalPower {
        didSet {
            streamingEngine.fadeCurve = fadeCurve
            djEngine.fadeCurve = fadeCurve
        }
    }

    private(set) var backend: UnifiedMixBackend = .streaming

    var isPlaying: Bool {
        switch backend {
        case .streaming: return streamingEngine.isPlaying
        case .dj: return djEngine.isPlaying
        }
    }

    var currentTime: Double {
        switch backend {
        case .streaming: return streamingEngine.currentTime
        case .dj: return djEngine.currentTime
        }
    }

    var duration: Double {
        switch backend {
        case .streaming: return streamingEngine.duration
        case .dj: return djEngine.duration
        }
    }

    var nextTime: Double {
        switch backend {
        case .streaming: return streamingEngine.nextTime
        case .dj: return djEngine.nextTime
        }
    }

    var nextDuration: Double {
        switch backend {
        case .streaming: return streamingEngine.nextDuration
        case .dj: return djEngine.nextDuration
        }
    }

    private let streamingEngine = MixPlaybackEngine()
    private let djEngine = DJMixPlaybackEngine()

    init() {
        streamingEngine.delegate = self
        djEngine.delegate = self
    }

    func play(
        context: PlaybackContext,
        streamData: CachedStreamData?,
        fileURL: URL?,
        analysis: DJAnalysisResult?,
        startTime: Double? = nil
    ) {
        if let fileURL, let analysis {
            backend = .dj
            djEngine.play(context: context, fileURL: fileURL, analysis: analysis, startTime: startTime)
        } else if let streamData {
            backend = .streaming
            streamingEngine.play(context: context, streamData: streamData, startTime: startTime)
        }
    }

    func pause() {
        streamingEngine.pause()
        djEngine.pause()
    }

    func resume() {
        switch backend {
        case .streaming:
            streamingEngine.resume()
        case .dj:
            djEngine.resume()
        }
    }

    func seek(to time: Double) {
        switch backend {
        case .streaming:
            streamingEngine.seek(to: time)
        case .dj:
            djEngine.seek(to: time)
        }
    }

    func setVolume(_ volume: Double) {
        switch backend {
        case .streaming:
            streamingEngine.setVolume(volume)
        case .dj:
            djEngine.setVolume(volume)
        }
    }

    func triggerInstantMix() -> Bool {
        switch backend {
        case .streaming:
            return streamingEngine.triggerInstantMix()
        case .dj:
            return djEngine.triggerInstantMix()
        }
    }

    func handleQueueChanged() {
        streamingEngine.handleQueueChanged()
        djEngine.handleQueueChanged()
    }

    func stop() {
        streamingEngine.stop()
        djEngine.stop()
    }
}

// MARK: - MixPlaybackEngineDelegate

extension UnifiedMixEngine: MixPlaybackEngineDelegate {
    fileprivate func mixEngine(_ engine: MixPlaybackEngine, didEmit event: MixObservabilityEvent) {
        switch event {
        case .prewarmStart(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .prewarmStart(backend: .streaming, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .prewarmReady(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .prewarmReady(backend: .streaming, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeStart(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .fadeStart(backend: .streaming, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeComplete(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .fadeComplete(backend: .streaming, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeAbort(let trackId, let nextTrackId, let crossfadeSeconds, let reason):
            delegate?.unifiedMixEngine(self, didEmit: .fadeAbort(backend: .streaming, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds, reason: reason))
        }
    }

    fileprivate func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngine(self, didCompleteTransitionTo: track, context: context)
    }

    fileprivate func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        delegate?.unifiedMixEngine(self, didAbortWithFallback: track, context: context)
    }

    fileprivate func mixEngineDidFinishTrack(_ engine: MixPlaybackEngine, track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngineDidFinishTrack(self, track: track, context: context)
    }

    fileprivate func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double) {
        delegate?.unifiedMixEngineDidUpdateTime(self, currentTime: currentTime, duration: duration)
    }

    fileprivate func mixEngineDidUpdateCrossfadeProgress(_ engine: MixPlaybackEngine, progress: Double, nextTrack: Track?) {
        delegate?.unifiedMixEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextTrack)
    }
}

// MARK: - DJMixPlaybackEngineDelegate

extension UnifiedMixEngine: DJMixPlaybackEngineDelegate {
    fileprivate func djEngine(_ engine: DJMixPlaybackEngine, didEmit event: DJMixObservabilityEvent) {
        switch event {
        case .prewarmStart(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .prewarmStart(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .prewarmReady(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .prewarmReady(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeScheduled(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .fadeScheduled(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeStart(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .fadeStart(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeComplete(let trackId, let nextTrackId, let crossfadeSeconds):
            delegate?.unifiedMixEngine(self, didEmit: .fadeComplete(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds))
        case .fadeAbort(let trackId, let nextTrackId, let crossfadeSeconds, let reason):
            delegate?.unifiedMixEngine(self, didEmit: .fadeAbort(backend: .dj, trackId: trackId, nextTrackId: nextTrackId, crossfadeSeconds: crossfadeSeconds, reason: reason))
        }
    }

    fileprivate func djEngine(_ engine: DJMixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngine(self, didCompleteTransitionTo: track, context: context)
    }

    fileprivate func djEngine(_ engine: DJMixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        delegate?.unifiedMixEngine(self, didAbortWithFallback: track, context: context)
    }

    fileprivate func djEngineDidFinishTrack(_ engine: DJMixPlaybackEngine, track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngineDidFinishTrack(self, track: track, context: context)
    }

    fileprivate func djEngineDidUpdateTime(_ engine: DJMixPlaybackEngine, currentTime: Double, duration: Double) {
        delegate?.unifiedMixEngineDidUpdateTime(self, currentTime: currentTime, duration: duration)
    }

    fileprivate func djEngineDidUpdateCrossfadeProgress(_ engine: DJMixPlaybackEngine, progress: Double, nextTrack: Track?) {
        delegate?.unifiedMixEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextTrack)
    }
}

// MARK: - Streaming Mix Engine

// Import MixCore types from the local package
// Note: When integrated, these will be imported from MixbridgeMixCore

/// Observability events for Mix Mode
fileprivate enum MixObservabilityEvent {
    case prewarmStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case prewarmReady(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeComplete(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeAbort(trackId: String, nextTrackId: String?, crossfadeSeconds: Double, reason: String)
}

/// Delegate for MixPlaybackEngine events
@MainActor
fileprivate protocol MixPlaybackEngineDelegate: AnyObject {
    func mixEngine(_ engine: MixPlaybackEngine, didEmit event: MixObservabilityEvent)
    func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext)
    func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?)
    func mixEngineDidFinishTrack(_ engine: MixPlaybackEngine, track: Track, context: PlaybackContext)
    func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double)
    func mixEngineDidUpdateCrossfadeProgress(_ engine: MixPlaybackEngine, progress: Double, nextTrack: Track?)
}

/// Context for mix playback (reuses PlaybackContext from PlaybackCoordinator)
fileprivate typealias MixTrackContext = PlaybackContext

/// Mix Mode playback engine using two AVPlayers
/// Handles prewarm and crossfade transitions
@MainActor
fileprivate final class MixPlaybackEngine {

    // MARK: - Public Properties

    weak var delegate: MixPlaybackEngineDelegate?

    var crossfadeSeconds: Double = 6
    var prewarmSeconds: Double = 15
    var fadeCurve: DJCrossfadeCurve = .equalPower

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

                    // Fall back to streaming
                    let streamData = try await streamCache.ensureStream(for: nextTrack.id, priority: .userInitiated)
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

                // Fall back to streaming - check if we need to refresh
                let deadline = Date().addingTimeInterval(crossfadeSeconds + 15)
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
        let currentGain = Float(fadeCurve.fadeOutGain(progress: progress))
        let nextGain = Float(fadeCurve.fadeInGain(progress: progress))

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
        if streamData.streamType == "local" {
            // Local file - no headers needed
            asset = AVURLAsset(url: url)
        } else {
            // Remote stream - add OAuth headers
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
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 {
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


// MARK: - DJ Mix Engine

private enum DJMixObservabilityEvent: Sendable, Equatable {
    case prewarmStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case prewarmReady(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeScheduled(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeComplete(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeAbort(trackId: String, nextTrackId: String?, crossfadeSeconds: Double, reason: String)
}

@MainActor
fileprivate protocol DJMixPlaybackEngineDelegate: AnyObject {
    func djEngine(_ engine: DJMixPlaybackEngine, didEmit event: DJMixObservabilityEvent)
    func djEngine(_ engine: DJMixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext)
    func djEngine(_ engine: DJMixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?)
    func djEngineDidFinishTrack(_ engine: DJMixPlaybackEngine, track: Track, context: PlaybackContext)
    func djEngineDidUpdateTime(_ engine: DJMixPlaybackEngine, currentTime: Double, duration: Double)
    func djEngineDidUpdateCrossfadeProgress(_ engine: DJMixPlaybackEngine, progress: Double, nextTrack: Track?)
}

@MainActor
fileprivate final class DJMixPlaybackEngine {
    weak var delegate: DJMixPlaybackEngineDelegate?

    var crossfadeSeconds: Double = 6 {
        didSet { updatePrePlannerSettings() }
    }

    var prewarmSeconds: Double = 15
    var fadeCurve: DJCrossfadeCurve = .equalPower {
        didSet { updatePrePlannerSettings() }
    }

    var isPlaying: Bool { isIntendedToPlay && state != .stopped }

    var currentTime: Double { engine?.currentTime(for: activeDeck) ?? 0 }

    var duration: Double { currentDurationSeconds }

    var nextTime: Double {
        guard let engine, let nextDeck else { return 0 }
        return engine.currentTime(for: nextDeck)
    }

    var nextDuration: Double { nextDurationSeconds }

    // MARK: - Private

    private enum EngineState {
        case idle
        case singlePlaying
        case prewarmingNext
        case scheduledTransition
        case crossfading
        case stopped
    }

    private var state: EngineState = .idle
    private var isIntendedToPlay: Bool = false

    private var engine: DJMixerEngine?
    private var activeDeck: DJDeck = .a
    private var nextDeck: DJDeck?

    private var currentContext: PlaybackContext?
    private var nextContext: PlaybackContext?

    private var currentAnalysis: DJAnalysisResult?
    private var nextAnalysis: DJAnalysisResult?

    private var currentDurationSeconds: Double = 0
    private var nextDurationSeconds: Double = 0

    private var schedule: MixScheduleInfo?

    private var tickTimer: Timer?
    private var lastProgress: Double = 0

    private let queueManager = QueueManager.shared
    private let downloadManager = DownloadManager.shared
    private let analysisManager = DJAnalysisManager.shared
    private let prePlanner = AIDJPrePlanner.shared

    private struct MixScheduleInfo {
        let effectiveCrossfade: Double
        let fadeStartTime: Double
        let prewarmStartTime: Double
        let duration: Double
        let isCrossfadeEnabled: Bool
    }

    // MARK: - Public API

    func play(context: PlaybackContext, fileURL: URL, analysis: DJAnalysisResult, startTime: Double? = nil) {
        cleanup()

        currentContext = context
        currentAnalysis = analysis
        activeDeck = .a
        nextDeck = nil
        state = .idle
        isIntendedToPlay = true

        do {
            let durationSeconds = try computeDurationSeconds(for: fileURL, fallback: context.soundCloudTrack)
            currentDurationSeconds = durationSeconds
            schedule = computeSchedule(durationSeconds: durationSeconds)

            let mixer = DJMixerEngine(config: .realtime)
            engine = mixer

            try mixer.start()
            try mixer.loadTrack(url: fileURL, deck: .a, timing: analysis.toTrackTiming())

            try mixer.play(deck: .a, fromSeconds: startTime ?? 0)
            state = .singlePlaying

            startTicking()

            // Pre-plan the next transition early
            Task { await preplanNextTransition() }
        } catch {
            logError(.dj, "DJMixPlaybackEngine: failed to start: \(error)")
            abortMixTransition(reason: "start_failed", shouldFallbackToNext: false)
        }
    }

    func pause() {
        isIntendedToPlay = false
        tickTimer?.invalidate()
        tickTimer = nil
        engine?.pause()
    }

    func resume() {
        isIntendedToPlay = true
        engine?.resume()
        startTicking()
    }

    func stop() {
        cleanup()
        state = .stopped
    }

    func seek(to time: Double) {
        guard let engine else { return }

        // Only abort transition if seeking before prewarm time or during active crossfade.
        // This allows scrubbing within the track without cancelling a scheduled mix.
        let shouldAbort: Bool = {
            switch state {
            case .crossfading:
                // Always abort if actively crossfading - can't seek during mix
                return true
            case .prewarmingNext, .scheduledTransition:
                // Only abort if seeking before prewarm start
                if let schedule, time < schedule.prewarmStartTime {
                    return true
                }
                return false
            case .singlePlaying, .idle, .stopped:
                return false
            }
        }()

        if shouldAbort {
            abortMixTransition(reason: "seek_cancelled", shouldFallbackToNext: false)
        }

        do {
            try engine.play(deck: activeDeck, fromSeconds: time)
            if shouldAbort {
                state = .singlePlaying
            }
            schedule = computeSchedule(durationSeconds: currentDurationSeconds)
        } catch {
            logWarning(.dj, "DJMixPlaybackEngine: seek failed: \(error)")
        }
    }

    func setVolume(_ volume: Double) {
        guard let engine else { return }
        if state != .crossfading {
            engine.setVolume(Float(volume), for: activeDeck)
        }
    }

    /// Instant mix trigger when user manually presses forward.
    /// Returns true if it could snap to the next deck, false if caller should fall back to normal skip.
    func triggerInstantMix() -> Bool {
        switch state {
        case .crossfading, .scheduledTransition:
            return snapToNextIfPossible()
        case .prewarmingNext:
            // If prewarmed, schedule a short transition now.
            if nextContext != nil, nextAnalysis != nil {
                Task { [weak self] in
                    guard let self else { return }
                    await self.scheduleInstantTransition(isManualSkip: true)
                }
                return true
            }
            return false
        case .singlePlaying:
            // Try to prewarm and schedule immediately.
            Task { [weak self] in
                guard let self else { return }
                await self.prewarmNextIfNeeded(force: true)
            }
            return true
        case .idle, .stopped:
            return false
        }
    }

    func handleQueueChanged() {
        // Cancel any pending prewarm/schedule; we always look at queue.peek() at prewarm time.
        if state == .prewarmingNext || state == .scheduledTransition {
            nextContext = nil
            nextDeck = nil
            nextAnalysis = nil
            nextDurationSeconds = 0
            state = .singlePlaying
        }

        // Pre-plan the new next transition
        Task { await preplanNextTransition() }
    }

    // MARK: - Pre-Planning

    private func updatePrePlannerSettings() {
        prePlanner.configure(
            fadeDuration: crossfadeSeconds,
            curve: fadeCurve
        )
    }

    /// Pre-plan the transition to the next track in queue.
    /// Called when playback starts or queue changes.
    private func preplanNextTransition() async {
        guard let currentCtx = currentContext,
              let currentAnalysis else { return }

        // Get next track from queue
        guard let nextItem = queueManager.queue.peek() else { return }

        let nextTrack = nextItem.track

        // Get analysis for next track (from prep service or analyze)
        guard let fileURL = await downloadManager.getLocalFileURL(trackId: nextTrack.id) else {
            logDebug(.dj, "DJMixPlaybackEngine: next track not downloaded, skipping pre-plan")
            return
        }

        let nextAnalysis: DJAnalysisResult
        if let prepped = DJPrepService.shared.getAnalysis(trackId: nextTrack.id) {
            nextAnalysis = prepped
        } else {
            do {
                nextAnalysis = try await analysisManager.analyze(url: fileURL, trackId: nextTrack.id)
            } catch {
                logWarning(.dj, "DJMixPlaybackEngine: analysis failed for pre-plan: \(error)")
                return
            }
        }

        // Pre-plan the transition (runs in background, caches result)
        await prePlanner.preplan(
            outgoing: currentCtx.track,
            outgoingAnalysis: currentAnalysis,
            incoming: nextTrack,
            incomingAnalysis: nextAnalysis
        )
    }

    // MARK: - Tick Loop

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        guard isIntendedToPlay, let engine, let currentCtx = currentContext else { return }

        let t = engine.currentTime(for: activeDeck)
        delegate?.djEngineDidUpdateTime(self, currentTime: t, duration: currentDurationSeconds)

        // Start prewarm when we're close enough.
        if let schedule, state == .singlePlaying {
            if t >= schedule.prewarmStartTime, schedule.isCrossfadeEnabled {
                state = .prewarmingNext
                Task { [weak self] in
                    guard let self else { return }
                    await self.prewarmNextIfNeeded(force: false)
                }
            }
        }

        // Drive transition progress if we have one scheduled/running.
        if state == .scheduledTransition || state == .crossfading {
            let progress = engine.tick() ?? 0
            let isNowCrossfading = progress > 0 && progress < 1

            if isNowCrossfading, state != .crossfading {
                state = .crossfading
                if let next = nextContext {
                    delegate?.djEngineDidUpdateCrossfadeProgress(self, progress: 0, nextTrack: next.track)
                    delegate?.djEngine(self, didEmit: .fadeStart(
                        trackId: currentCtx.track.id,
                        nextTrackId: next.track.id,
                        crossfadeSeconds: crossfadeSeconds
                    ))
                }
            }

            if abs(progress - lastProgress) > 0.0001 {
                delegate?.djEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextContext?.track)
                lastProgress = progress
            }

            if progress >= 1.0 {
                completeTransition()
                // Return early - don't run track-end check with stale `t` value from old deck.
                // Next tick will use the correct time from the new active deck.
                return
            }
        }

        // Track end handling when no transition is possible.
        if t >= max(0, currentDurationSeconds - 0.1), state == .singlePlaying {
            delegate?.djEngineDidFinishTrack(self, track: currentCtx.track, context: currentCtx)
        }
    }

    // MARK: - Prewarm / Plan / Transition

    private func computeSchedule(durationSeconds: Double) -> MixScheduleInfo? {
        let clampedCrossfade = max(0, min(20, crossfadeSeconds))
        let clampedPrewarm = max(0, min(60, prewarmSeconds))
        let effectiveCrossfade = min(clampedCrossfade, durationSeconds)
        let prewarmLeadTime = max(clampedPrewarm, effectiveCrossfade)
        let prewarmStartTime = max(0, durationSeconds - prewarmLeadTime)
        let fadeStartTime = max(0, durationSeconds - effectiveCrossfade)

        return MixScheduleInfo(
            effectiveCrossfade: effectiveCrossfade,
            fadeStartTime: fadeStartTime,
            prewarmStartTime: prewarmStartTime,
            duration: durationSeconds,
            isCrossfadeEnabled: clampedCrossfade > 0.1
        )
    }

    private func prewarmNextIfNeeded(force _: Bool) async {
        guard let currentCtx = currentContext, let schedule else { return }

        // Get next track (queue.peek) — current track is never in queue.
        guard let nextItem = queueManager.queue.peek() else {
            state = .singlePlaying
            return
        }

        let nextTrack = nextItem.track
        nextContext = PlaybackContext(track: nextTrack, soundCloudTrack: nextItem.soundCloudTrack, queueIndex: 0)
        nextDeck = activeDeck == .a ? .b : .a

        delegate?.djEngine(self, didEmit: .prewarmStart(
            trackId: currentCtx.track.id,
            nextTrackId: nextTrack.id,
            crossfadeSeconds: crossfadeSeconds
        ))

        guard let fileURL = await downloadManager.getLocalFileURL(trackId: nextTrack.id) else {
            abortMixTransition(reason: "next_not_downloaded", shouldFallbackToNext: false)
            return
        }

        do {
            let durationSeconds = try computeDurationSeconds(for: fileURL, fallback: nextContext?.soundCloudTrack)
            nextDurationSeconds = durationSeconds

            // Prefer prepped analysis if available (fast path).
            let analysis: DJAnalysisResult
            if let prepped = DJPrepService.shared.getAnalysis(trackId: nextTrack.id) {
                analysis = prepped
            } else {
                analysis = try await analysisManager.analyze(url: fileURL, trackId: nextTrack.id)
            }
            nextAnalysis = analysis

            guard let engine, let nextDeck else { return }
            try engine.loadTrack(url: fileURL, deck: nextDeck, timing: analysis.toTrackTiming())

            delegate?.djEngine(self, didEmit: .prewarmReady(
                trackId: currentCtx.track.id,
                nextTrackId: nextTrack.id,
                crossfadeSeconds: crossfadeSeconds
            ))

            // Schedule transition using cached plan (instant, no network wait)
            await scheduleTransition(schedule: schedule, isManualSkip: false)
        } catch {
            logError(.dj, "DJMixPlaybackEngine: prewarm failed: \(error)")
            abortMixTransition(reason: "prewarm_failed", shouldFallbackToNext: false)
        }
    }

    private func scheduleTransition(schedule _: MixScheduleInfo, isManualSkip _: Bool) async {
        guard let engine,
              let currentCtx = currentContext,
              let nextCtx = nextContext,
              let currentAnalysis,
              let nextAnalysis
        else {
            abortMixTransition(reason: "not_ready", shouldFallbackToNext: false)
            return
        }

        // Get plan from cache (instant) or generate fallback
        let cachedPlan = await prePlanner.getPlanOrFallback(
            outgoingId: currentCtx.track.id,
            outgoingDuration: currentDurationSeconds,
            outgoingAnalysis: currentAnalysis,
            incomingId: nextCtx.track.id,
            incomingDuration: nextDurationSeconds,
            incomingAnalysis: nextAnalysis
        )

        // Validate and clamp the plan to current schedule
        let djPlan = cachedPlan.plan.clamped(outgoingDuration: currentDurationSeconds)

        logInfo(.dj, "DJMixPlaybackEngine: using \(cachedPlan.isFallback ? "fallback" : "AI") plan, age=\(String(format: "%.1f", cachedPlan.age))s")

        guard currentContext?.track.id == currentCtx.track.id,
              nextContext?.track.id == nextCtx.track.id
        else {
            return
        }

        let fadeEnd = djPlan.fadeStartSeconds + djPlan.fadeDurationSeconds
        logInfo(.dj, "DJMixPlaybackEngine: scheduling transition - fadeStart=\(String(format: "%.2f", djPlan.fadeStartSeconds))s, fadeEnd=\(String(format: "%.2f", fadeEnd))s, duration=\(String(format: "%.2f", djPlan.fadeDurationSeconds))s, currentTime=\(String(format: "%.2f", currentTime))s")
        logInfo(.dj, "DJMixPlaybackEngine: outgoing BPM=\(String(format: "%.2f", currentAnalysis.bpm)), incoming BPM=\(String(format: "%.2f", nextAnalysis.bpm)), tempoMatch=\(djPlan.tempoMatch.enabled ? String(format: "%.2f", djPlan.tempoMatch.targetBPM) : "disabled"), beatAlign=\(djPlan.beatAlignment)")
        logPlanDetails(djPlan, fadeDuration: djPlan.fadeDurationSeconds, incomingBPM: nextAnalysis.bpm)

        do {
            try engine.executeTransition(plan: djPlan)
            state = .scheduledTransition
            logInfo(.dj, "DJMixPlaybackEngine: transition scheduled successfully, activeDeck=\(activeDeck), nextDeck=\(String(describing: nextDeck))")
            delegate?.djEngine(self, didEmit: .fadeScheduled(
                trackId: currentCtx.track.id,
                nextTrackId: nextCtx.track.id,
                crossfadeSeconds: crossfadeSeconds
            ))
        } catch {
            logError(.dj, "DJMixPlaybackEngine: failed to schedule transition: \(error)")
            abortMixTransition(reason: "transition_schedule_failed", shouldFallbackToNext: false)
        }
    }

    private func scheduleInstantTransition(isManualSkip: Bool) async {
        guard let schedule else { return }
        let now = currentTime
        let instant = MixScheduleInfo(
            effectiveCrossfade: min(2.0, schedule.effectiveCrossfade),
            fadeStartTime: now,
            prewarmStartTime: now,
            duration: schedule.duration,
            isCrossfadeEnabled: true
        )
        await scheduleTransition(schedule: instant, isManualSkip: isManualSkip)
    }

    private func logPlanDetails(_ plan: DJTransitionPlan, fadeDuration: Double, incomingBPM: Double) {
        if plan.tempoMatch.enabled {
            let rate = plan.tempoMatch.computeRate(incomingBPM: incomingBPM)
            logDebug(.dj, "DJMixPlaybackEngine: plan curve=\(plan.crossfadeCurve), beatAlignment=\(plan.beatAlignment), tempoMatch=enabled, targetBPM=\(String(format: "%.2f", plan.tempoMatch.targetBPM)), rate=\(String(format: "%.3f", rate)), maxRateAdj=\(String(format: "%.3f", plan.tempoMatch.maxRateAdjustment))")
        } else {
            logDebug(.dj, "DJMixPlaybackEngine: plan curve=\(plan.crossfadeCurve), beatAlignment=\(plan.beatAlignment), tempoMatch=disabled, maxRateAdj=\(String(format: "%.3f", plan.tempoMatch.maxRateAdjustment))")
        }
        logEQCurves(plan.outgoingEQCurves, label: "outgoing", fadeDuration: fadeDuration)
        logEQCurves(plan.incomingEQCurves, label: "incoming", fadeDuration: fadeDuration)
    }

    private func logEQCurves(_ curves: [DJEQCurve], label: String, fadeDuration: Double) {
        guard !curves.isEmpty else {
            logDebug(.dj, "DJMixPlaybackEngine: \(label) EQ: none")
            return
        }

        let formatted = curves.map { curve -> String in
            let points = curve.keyframes.map { keyframe -> String in
                let time = keyframe.progress * fadeDuration
                return "\(String(format: "%.2f", time))s:\(String(format: "%.1f", keyframe.gainDB))dB"
            }
            return "\(curve.band)=[" + points.joined(separator: ", ") + "]"
        }.joined(separator: " | ")

        logDebug(.dj, "DJMixPlaybackEngine: \(label) EQ: \(formatted)")
    }

    private func snapToNextIfPossible() -> Bool {
        guard let engine, let nextCtx = nextContext, let nextDeck else { return false }
        engine.cutToDeck(nextDeck)
        completeTransition()
        delegate?.djEngine(self, didEmit: .fadeComplete(
            trackId: currentContext?.track.id ?? "",
            nextTrackId: nextCtx.track.id,
            crossfadeSeconds: crossfadeSeconds
        ))
        return true
    }

    private func completeTransition() {
        guard let nextCtx = nextContext else { return }

        logInfo(.dj, "DJMixPlaybackEngine: completing transition to \(nextCtx.track.title)")

        // Promote next to current.
        currentContext = nextCtx
        currentAnalysis = nextAnalysis
        currentDurationSeconds = nextDurationSeconds
        activeDeck = nextDeck ?? activeDeck

        // Clear next.
        nextContext = nil
        nextAnalysis = nil
        nextDeck = nil
        nextDurationSeconds = 0
        lastProgress = 0

        // Reset state to single playing so next transition can be scheduled.
        state = .singlePlaying
        schedule = computeSchedule(durationSeconds: currentDurationSeconds)

        delegate?.djEngine(self, didCompleteTransitionTo: nextCtx.track, context: nextCtx)

        // Pre-plan the next transition
        Task { await preplanNextTransition() }
    }

    private func abortMixTransition(reason: String, shouldFallbackToNext: Bool) {
        let current = currentContext
        let next = shouldFallbackToNext ? nextContext : nil

        delegate?.djEngine(self, didEmit: .fadeAbort(
            trackId: current?.track.id ?? "",
            nextTrackId: next?.track.id,
            crossfadeSeconds: crossfadeSeconds,
            reason: reason
        ))

        nextContext = nil
        nextAnalysis = nil
        nextDeck = nil
        nextDurationSeconds = 0
        lastProgress = 0

        if shouldFallbackToNext, let next {
            delegate?.djEngine(self, didAbortWithFallback: next.track, context: next)
        } else {
            delegate?.djEngine(self, didAbortWithFallback: nil, context: nil)
        }

        state = .singlePlaying
    }

    private func cleanup() {
        tickTimer?.invalidate()
        tickTimer = nil

        engine?.stop()
        engine = nil

        currentContext = nil
        nextContext = nil
        currentAnalysis = nil
        nextAnalysis = nil
        currentDurationSeconds = 0
        nextDurationSeconds = 0
        schedule = nil

        lastProgress = 0
        isIntendedToPlay = false
    }

    private func computeDurationSeconds(for url: URL, fallback: SoundCloudTrack?) throws -> Double {
        if let fallback, fallback.duration > 0 {
            return Double(fallback.duration) / 1000.0
        }
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
