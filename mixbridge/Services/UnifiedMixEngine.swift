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

    var fadeCurve: FadeCurve = .equalPower {
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
    func mixEngine(_ engine: MixPlaybackEngine, didEmit event: MixObservabilityEvent) {
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

    func mixEngine(_ engine: MixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngine(self, didCompleteTransitionTo: track, context: context)
    }

    func mixEngine(_ engine: MixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        delegate?.unifiedMixEngine(self, didAbortWithFallback: track, context: context)
    }

    func mixEngineDidFinishTrack(_ engine: MixPlaybackEngine, track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngineDidFinishTrack(self, track: track, context: context)
    }

    func mixEngineDidUpdateTime(_ engine: MixPlaybackEngine, currentTime: Double, duration: Double) {
        delegate?.unifiedMixEngineDidUpdateTime(self, currentTime: currentTime, duration: duration)
    }

    func mixEngineDidUpdateCrossfadeProgress(_ engine: MixPlaybackEngine, progress: Double, nextTrack: Track?) {
        delegate?.unifiedMixEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextTrack)
    }
}

// MARK: - DJMixPlaybackEngineDelegate

extension UnifiedMixEngine: DJMixPlaybackEngineDelegate {
    func djEngine(_ engine: DJMixPlaybackEngine, didEmit event: DJMixObservabilityEvent) {
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

    func djEngine(_ engine: DJMixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngine(self, didCompleteTransitionTo: track, context: context)
    }

    func djEngine(_ engine: DJMixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?) {
        delegate?.unifiedMixEngine(self, didAbortWithFallback: track, context: context)
    }

    func djEngineDidFinishTrack(_ engine: DJMixPlaybackEngine, track: Track, context: PlaybackContext) {
        delegate?.unifiedMixEngineDidFinishTrack(self, track: track, context: context)
    }

    func djEngineDidUpdateTime(_ engine: DJMixPlaybackEngine, currentTime: Double, duration: Double) {
        delegate?.unifiedMixEngineDidUpdateTime(self, currentTime: currentTime, duration: duration)
    }

    func djEngineDidUpdateCrossfadeProgress(_ engine: DJMixPlaybackEngine, progress: Double, nextTrack: Track?) {
        delegate?.unifiedMixEngineDidUpdateCrossfadeProgress(self, progress: progress, nextTrack: nextTrack)
    }
}
