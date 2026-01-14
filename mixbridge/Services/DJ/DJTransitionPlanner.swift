//
//  DJTransitionPlanner.swift
//  mixbridge
//
//  Deterministic planner that converts analysis + user settings into a MixBridgeDJ transition plan.
//

import Foundation
import MixBridgeDJ

struct DJTransitionPlannerSettings: Sendable, Equatable {
    var crossfadeSeconds: Double
    var fadeCurve: FadeCurve

    var beatSyncEnabled: Bool
    var tempoMatchEnabled: Bool
    var eqPolishEnabled: Bool

    /// If true, prefer aligning to bar boundaries (downbeat). Otherwise align to beats.
    var preferBarSync: Bool

    /// Confidence threshold required to enable beat sync / tempo matching.
    var confidenceThreshold: Double

    static func fromPlayerState() -> DJTransitionPlannerSettings {
        DJTransitionPlannerSettings(
            crossfadeSeconds: PlayerState.shared.crossfadeSeconds,
            fadeCurve: PlayerState.shared.fadeCurve,
            beatSyncEnabled: true,
            tempoMatchEnabled: true,
            eqPolishEnabled: true,
            preferBarSync: true,
            confidenceThreshold: 0.6
        )
    }
}

enum DJTransitionPlanner {
    static func makePlan(
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

        let crossfadeCurve: DJCrossfadeCurve
        switch settings.fadeCurve {
        case .linear:
            crossfadeCurve = .linear
        case .equalPower:
            crossfadeCurve = .equalPower
        case .sCurve:
            crossfadeCurve = .constantPower
        case .exponential:
            crossfadeCurve = .linear
        }

        let outgoingEQ: [DJEQCurve]
        let incomingEQ: [DJEQCurve]

        if settings.eqPolishEnabled {
            // Minimal “DJ polish”:
            // - incoming: high duck early, restore by end
            // - outgoing: gentle high cut near the end for a smoother handoff
            incomingEQ = [
                .highDuckIncoming(band: .high),
            ]
            outgoingEQ = [
                DJEQCurve(band: .high, keyframes: [
                    DJEQKeyframe(progress: 0.0, gainDB: 0.0),
                    DJEQKeyframe(progress: 0.8, gainDB: 0.0),
                    DJEQKeyframe(progress: 1.0, gainDB: -6.0),
                ])
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

