//
//  DJTransitionPlanner.swift
//  MixBridgeDJ
//
//  Deterministic planner that converts analysis + user settings into a transition plan.
//

import Foundation

/// Settings for the transition planner.
public struct DJTransitionPlannerSettings: Sendable, Equatable {
    public var crossfadeSeconds: Double
    public var fadeCurve: DJCrossfadeCurve

    public var beatSyncEnabled: Bool
    public var tempoMatchEnabled: Bool
    public var eqPolishEnabled: Bool

    /// If true, prefer aligning to bar boundaries (downbeat). Otherwise align to beats.
    public var preferBarSync: Bool

    /// Confidence threshold required to enable beat sync / tempo matching.
    public var confidenceThreshold: Double

    public init(
        crossfadeSeconds: Double,
        fadeCurve: DJCrossfadeCurve,
        beatSyncEnabled: Bool,
        tempoMatchEnabled: Bool,
        eqPolishEnabled: Bool,
        preferBarSync: Bool,
        confidenceThreshold: Double
    ) {
        self.crossfadeSeconds = crossfadeSeconds
        self.fadeCurve = fadeCurve
        self.beatSyncEnabled = beatSyncEnabled
        self.tempoMatchEnabled = tempoMatchEnabled
        self.eqPolishEnabled = eqPolishEnabled
        self.preferBarSync = preferBarSync
        self.confidenceThreshold = confidenceThreshold
    }
}

/// Deterministic planner that creates transition plans from analysis results.
public enum DJTransitionPlanner {
    /// Create a transition plan from analysis results and settings.
    public static func makePlan(
        outgoing: DJAnalysisResult,
        incoming: DJAnalysisResult,
        fadeStartSeconds: Double,
        fadeDurationSeconds: Double,
        settings: DJTransitionPlannerSettings
    ) -> DJTransitionPlan {
        let fadeDuration = max(1.0, min(20.0, fadeDurationSeconds))
        let fadeStart = max(0.0, fadeStartSeconds)

        let outgoingUsable = outgoing.isUsableForBeatSync(threshold: settings.confidenceThreshold)
        let incomingUsable = incoming.isUsableForBeatSync(threshold: settings.confidenceThreshold)
        let canBeatSync = settings.beatSyncEnabled && outgoingUsable && incomingUsable
        let canTempoMatch = settings.tempoMatchEnabled && outgoingUsable && incomingUsable

        let beatAlignment: DJBeatAlignmentMode
        if canBeatSync {
            beatAlignment = settings.preferBarSync ? .bar : .beat
        } else {
            beatAlignment = .none
        }

        let tempoMatch = DJTempoMatchConfig(
            enabled: canTempoMatch,
            targetBPM: outgoing.bpm,
            maxRateAdjustment: 0.08,
            preservePitch: true
        )

        let crossfadeCurve = settings.fadeCurve

        let outgoingEQ: [DJEQCurve]
        let incomingEQ: [DJEQCurve]

        if settings.eqPolishEnabled {
            // Full DJ-style EQ transition with bass swap at ~45% mark.
            //
            // The key technique: incoming bass stays killed until the swap point,
            // then outgoing bass cuts while incoming bass comes in. This creates
            // the characteristic "DJ blend" sound rather than muddy overlap.
            //
            // Timeline:
            //   0%        45% (bass swap)              100%
            //   |-----------|---------------------------|
            //
            // OUTGOING:
            //   Bass:  [FULL]----[FULL]---[CUT]--------[CUT]
            //   Mids:  [FULL]----[FULL]-------[fade]---[CUT]
            //   Highs: [FULL]--------[fade]------------[CUT]
            //
            // INCOMING:
            //   Bass:  [CUT]-----[CUT]----[FULL]------[FULL]
            //   Mids:  [CUT]-------[fade in]----------[FULL]
            //   Highs: [-6dB]-----[fade in]-----------[FULL]

            let bassSwapPoint = 0.45  // Where the bass swap happens
            let bassKill: Double = -24.0  // Full bass cut

            // INCOMING TRACK EQ
            incomingEQ = [
                // Bass: killed until swap point, then full
                DJEQCurve(band: .low, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: bassKill),
                    DJEQKeyframe(progress: bassSwapPoint - 0.05, gainDB: bassKill),
                    DJEQKeyframe(progress: bassSwapPoint + 0.05, gainDB: 0.0),
                    DJEQKeyframe(progress: 1.0, gainDB: 0.0),
                ]),
                // Mids: start cut, gradually bring in
                DJEQCurve(band: .mid, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: -12.0),
                    DJEQKeyframe(progress: 0.3, gainDB: -8.0),
                    DJEQKeyframe(progress: 0.6, gainDB: -3.0),
                    DJEQKeyframe(progress: 1.0, gainDB: 0.0),
                ]),
                // Highs: start ducked, gradually bring in
                DJEQCurve(band: .high, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: -6.0),
                    DJEQKeyframe(progress: 0.4, gainDB: -3.0),
                    DJEQKeyframe(progress: 0.8, gainDB: 0.0),
                    DJEQKeyframe(progress: 1.0, gainDB: 0.0),
                ]),
            ]

            // OUTGOING TRACK EQ
            outgoingEQ = [
                // Bass: full until swap point, then cut
                DJEQCurve(band: .low, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: 0.0),
                    DJEQKeyframe(progress: bassSwapPoint - 0.05, gainDB: 0.0),
                    DJEQKeyframe(progress: bassSwapPoint + 0.05, gainDB: bassKill),
                    DJEQKeyframe(progress: 1.0, gainDB: bassKill),
                ]),
                // Mids: hold then fade out
                DJEQCurve(band: .mid, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: 0.0),
                    DJEQKeyframe(progress: 0.5, gainDB: 0.0),
                    DJEQKeyframe(progress: 0.8, gainDB: -6.0),
                    DJEQKeyframe(progress: 1.0, gainDB: -12.0),
                ]),
                // Highs: gradual fade out
                DJEQCurve(band: .high, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: 0.0),
                    DJEQKeyframe(progress: 0.4, gainDB: 0.0),
                    DJEQKeyframe(progress: 0.7, gainDB: -3.0),
                    DJEQKeyframe(progress: 1.0, gainDB: -6.0),
                ]),
            ]
        } else {
            outgoingEQ = []
            incomingEQ = []
        }

        return DJTransitionPlan(
            fadeDurationSeconds: fadeDuration,
            fadeStartSeconds: fadeStart,
            crossfadeCurve: crossfadeCurve,
            outgoingEQCurves: outgoingEQ,
            incomingEQCurves: incomingEQ,
            tempoMatch: tempoMatch,
            beatAlignment: beatAlignment,
            isFallback: false
        )
    }
}
