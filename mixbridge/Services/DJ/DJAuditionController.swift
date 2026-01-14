//
//  DJAuditionController.swift
//  mixbridge
//
//  Controls the DJMixerEngine lifecycle for dev-only auditioning.
//  Used by DJLabView to test DJ transitions without affecting production playback.
//

import Combine
import Foundation
import AVFoundation
import MixBridgeDJ

/// Engine state for the audition controller.
enum DJAuditionState: Equatable {
    case idle
    case loadedDeckA
    case loadedBoth
    case playing
    case transitioning
    case error(String)
}

/// Controller for dev-only DJ auditioning.
/// Manages the DJMixerEngine lifecycle and provides a simple API for testing transitions.
@MainActor
final class DJAuditionController: ObservableObject {
    /// Current state of the audition engine.
    @Published private(set) var state: DJAuditionState = .idle

    /// Current playback time of deck A in seconds.
    @Published private(set) var currentTimeA: Double = 0

    /// Analysis result for deck A track.
    @Published private(set) var analysisA: DJAnalysisResult?

    /// Analysis result for deck B track.
    @Published private(set) var analysisB: DJAnalysisResult?

    /// Track info for deck A.
    @Published private(set) var trackA: Track?

    /// Track info for deck B.
    @Published private(set) var trackB: Track?

    /// The underlying DJ mixer engine.
    private var engine: DJMixerEngine?

    /// Timer for updating current playback time.
    private var timeUpdateTimer: Timer?

    private let analysisManager = DJAnalysisManager.shared

    init() {
        logInfo(.dj, "DJAuditionController: initialized")
    }

    deinit {
        timeUpdateTimer?.invalidate()
    }

    // MARK: - Public API

    /// Loads a track onto deck A.
    /// - Parameters:
    ///   - track: The track to load.
    ///   - fileURL: Local file URL of the downloaded audio.
    func loadDeckA(track: Track, fileURL: URL) async {
        do {
            // Analyze the track
            let result = try await analysisManager.analyze(url: fileURL, trackId: track.id)
            analysisA = result

            // Create engine if needed
            if engine == nil {
                engine = DJMixerEngine(config: .realtime)
            }

            // Load track onto deck A
            try engine?.loadTrack(
                url: fileURL,
                deck: .a,
                timing: result.toTrackTiming()
            )

            trackA = track
            state = .loadedDeckA
            logInfo(.dj, "DJAuditionController: loaded deck A - \(track.title)")
        } catch {
            state = .error("Failed to load deck A: \(error.localizedDescription)")
            logError(.dj, "DJAuditionController: failed to load deck A: \(error)")
        }
    }

    /// Loads a track onto deck B.
    /// - Parameters:
    ///   - track: The track to load.
    ///   - fileURL: Local file URL of the downloaded audio.
    func loadDeckB(track: Track, fileURL: URL) async {
        guard state == .loadedDeckA || state == .loadedBoth || state == .playing else {
            state = .error("Must load deck A first")
            return
        }

        do {
            // Analyze the track
            let result = try await analysisManager.analyze(url: fileURL, trackId: track.id)
            analysisB = result

            // Load track onto deck B
            try engine?.loadTrack(
                url: fileURL,
                deck: .b,
                timing: result.toTrackTiming()
            )

            trackB = track
            state = .loadedBoth
            logInfo(.dj, "DJAuditionController: loaded deck B - \(track.title)")
        } catch {
            state = .error("Failed to load deck B: \(error.localizedDescription)")
            logError(.dj, "DJAuditionController: failed to load deck B: \(error)")
        }
    }

    /// Starts playback on deck A.
    func play() {
        guard let engine, state == .loadedDeckA || state == .loadedBoth else {
            state = .error("No track loaded")
            return
        }

        do {
            try engine.start()
            try engine.playDeckA()
            state = .playing
            startTimeUpdates()
            logInfo(.dj, "DJAuditionController: playback started")
        } catch {
            state = .error("Playback failed: \(error.localizedDescription)")
            logError(.dj, "DJAuditionController: playback failed: \(error)")
        }
    }

    /// Stops playback and resets the engine.
    func stop() {
        engine?.stop()
        stopTimeUpdates()
        state = .idle
        currentTimeA = 0
        analysisA = nil
        analysisB = nil
        trackA = nil
        trackB = nil
        engine = nil
        logInfo(.dj, "DJAuditionController: stopped")
    }

    /// Executes a transition from deck A to deck B using the specified plan.
    func executeTransition(plan: DJTransitionPlan) {
        guard let engine, state == .playing || state == .loadedBoth else {
            state = .error("Not ready for transition")
            return
        }

        guard analysisB != nil else {
            state = .error("Deck B not loaded")
            return
        }

        do {
            try engine.executeTransition(plan: plan)
            state = .transitioning
            logInfo(.dj, "DJAuditionController: transition started")
        } catch {
            state = .error("Transition failed: \(error.localizedDescription)")
            logError(.dj, "DJAuditionController: transition failed: \(error)")
        }
    }

    /// Creates a default transition plan based on the current analysis results.
    func createDefaultTransitionPlan() -> DJTransitionPlan? {
        guard let analysisA, let analysisB else { return nil }

        // Create a simple 8-second crossfade starting 10 seconds before end
        // (In real use, this would be based on track duration)
        let fadeDuration = 8.0
        let fadeStart = max(0, currentTimeA + 5) // Start 5 seconds from now

        // Create tempo match config
        let tempoMatch = DJTempoMatchConfig(
            enabled: analysisA.isUsableForBeatSync && analysisB.isUsableForBeatSync,
            targetBPM: analysisA.bpm,
            maxRateAdjustment: 0.08,
            preservePitch: true
        )

        return DJTransitionPlan(
            fadeDurationSeconds: fadeDuration,
            fadeStartSeconds: fadeStart,
            crossfadeCurve: .equalPower,
            outgoingEQCurves: [], // Use defaults
            incomingEQCurves: [],
            tempoMatch: tempoMatch,
            beatAlignment: .bar,
            isFallback: false
        )
    }

    // MARK: - Private

    private func startTimeUpdates() {
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateCurrentTime() {
        guard let engine else { return }
        currentTimeA = engine.currentTimeA()
    }
}
