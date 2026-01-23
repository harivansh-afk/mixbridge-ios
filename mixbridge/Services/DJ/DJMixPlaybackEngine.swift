//
//  DJMixPlaybackEngine.swift
//  mixbridge
//
//  Downloaded-track DJ automix engine using MixBridgeDJ (AVAudioEngine).
//  Provides beat-synced, BPM-matched transitions with EQ + crossfade control.
//
//  Uses pre-planning: AI endpoint is called when tracks are identified,
//  not at prewarm time, eliminating network latency during playback.
//

import AVFoundation
import Foundation
import MixBridgeDJ

enum DJMixObservabilityEvent: Sendable, Equatable {
    case prewarmStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case prewarmReady(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeScheduled(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeStart(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeComplete(trackId: String, nextTrackId: String, crossfadeSeconds: Double)
    case fadeAbort(trackId: String, nextTrackId: String?, crossfadeSeconds: Double, reason: String)
}

@MainActor
protocol DJMixPlaybackEngineDelegate: AnyObject {
    func djEngine(_ engine: DJMixPlaybackEngine, didEmit event: DJMixObservabilityEvent)
    func djEngine(_ engine: DJMixPlaybackEngine, didCompleteTransitionTo track: Track, context: PlaybackContext)
    func djEngine(_ engine: DJMixPlaybackEngine, didAbortWithFallback track: Track?, context: PlaybackContext?)
    func djEngineDidFinishTrack(_ engine: DJMixPlaybackEngine, track: Track, context: PlaybackContext)
    func djEngineDidUpdateTime(_ engine: DJMixPlaybackEngine, currentTime: Double, duration: Double)
    func djEngineDidUpdateCrossfadeProgress(_ engine: DJMixPlaybackEngine, progress: Double, nextTrack: Track?)
}

@MainActor
final class DJMixPlaybackEngine {
    weak var delegate: DJMixPlaybackEngineDelegate?

    var crossfadeSeconds: Double = 6 {
        didSet { updatePrePlannerSettings() }
    }

    var prewarmSeconds: Double = 15
    var fadeCurve: FadeCurve = .equalPower {
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
            curve: AIDJCrossfadeCurve(from: fadeCurve)
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
        let clampedPlan = cachedPlan.plan.clamped(
            outgoingDuration: currentDurationSeconds,
            incomingDuration: nextDurationSeconds
        )

        let djPlan = clampedPlan.toDJTransitionPlan()

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
