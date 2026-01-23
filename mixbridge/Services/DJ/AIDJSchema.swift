import Foundation
import MixBridgeDJ

// MARK: - Track Info (Simplified)

/// Track information for AI DJ planning. All times are absolute (seconds from track start).
struct AIDJTrackInfo: Codable, Sendable, Equatable {
    let trackId: String
    let title: String?
    let artist: String?
    let durationSeconds: Double
    let bpm: Double?
    let beatOffsetSeconds: Double?
    let timingConfidence: Double?
}

// MARK: - Mix Settings

/// User preferences for the mix. No playback-position-dependent fields.
struct AIDJMixSettings: Codable, Sendable, Equatable {
    let preferredFadeDurationSeconds: Double
    let preferredCurve: DJCrossfadeCurve?
    let allowTempoMatch: Bool
    let allowBeatSync: Bool
    let allowEQPolish: Bool

    static let `default` = AIDJMixSettings(
        preferredFadeDurationSeconds: 6.0,
        preferredCurve: .equalPower,
        allowTempoMatch: true,
        allowBeatSync: true,
        allowEQPolish: true
    )
}

// MARK: - Plan Request (Simplified)

/// Request for AI DJ mix planning. No current time or remaining time - planning is position-independent.
struct AIDJPlanRequest: Codable, Sendable, Equatable {
    let outgoingTrack: AIDJTrackInfo
    let incomingTrack: AIDJTrackInfo
    let settings: AIDJMixSettings

    /// Create a plan request from tracks and analysis results.
    static func from(
        outgoing: Track,
        outgoingAnalysis: DJAnalysisResult,
        incoming: Track,
        incomingAnalysis: DJAnalysisResult,
        settings: AIDJMixSettings
    ) -> AIDJPlanRequest {
        AIDJPlanRequest(
            outgoingTrack: AIDJTrackInfo(
                trackId: outgoing.id,
                title: outgoing.title,
                artist: outgoing.artist,
                durationSeconds: outgoing.duration,
                bpm: outgoingAnalysis.bpm,
                beatOffsetSeconds: outgoingAnalysis.beatOffsetSeconds,
                timingConfidence: outgoingAnalysis.confidence
            ),
            incomingTrack: AIDJTrackInfo(
                trackId: incoming.id,
                title: incoming.title,
                artist: incoming.artist,
                durationSeconds: incoming.duration,
                bpm: incomingAnalysis.bpm,
                beatOffsetSeconds: incomingAnalysis.beatOffsetSeconds,
                timingConfidence: incomingAnalysis.confidence
            ),
            settings: settings
        )
    }
}

// MARK: - Backend API Types

/// Backend request format for mixbridge.app/api/dj/plan
struct AIDJBackendRequest: Codable, Sendable, Equatable {
    let outgoingTrack: AIDJBackendTrackInfo
    let incomingTrack: AIDJBackendTrackInfo
    let settings: AIDJBackendSettings
}

struct AIDJBackendTrackInfo: Codable, Sendable, Equatable {
    let trackId: String
    let title: String?
    let artist: String?
    let durationMs: Int
    let bpm: Double?
    let beatOffsetMs: Int?
    let timingConfidence: Double?
}

struct AIDJBackendSettings: Codable, Sendable, Equatable {
    let preferredFadeDurationMs: Int
    let preferredCurve: String?
    let allowTempoMatch: Bool
    let allowBeatSync: Bool
    let allowEQPolish: Bool
}

/// Backend response format
struct AIDJBackendResponse: Codable, Sendable, Equatable {
    let plan: AIDJBackendPlan
    let confidence: Double?
    let reasoning: String?
    let warnings: [String]?
}

struct AIDJBackendPlan: Codable, Sendable, Equatable {
    let fadeStartSeconds: Double
    let fadeDurationSeconds: Double
    let crossfadeCurve: String?
    let incomingStartOffsetSeconds: Double?
    let beatAlignment: String?
    let tempoMatch: AIDJBackendTempoMatch?
    let outgoingEQCurves: [AIDJBackendEQCurve]?
    let incomingEQCurves: [AIDJBackendEQCurve]?
}

struct AIDJBackendTempoMatch: Codable, Sendable, Equatable {
    let enabled: Bool
    let targetBpm: Double?
    let maxRateAdjustment: Double?
}

struct AIDJBackendEQCurve: Codable, Sendable, Equatable {
    let band: String?
    let keyframes: [AIDJBackendEQKeyframe]
}

struct AIDJBackendEQKeyframe: Codable, Sendable, Equatable {
    /// Progress through the fade (0.0 to 1.0) - consistent with app-side
    let progress: Double
    let gainDB: Double
}

// MARK: - Request/Response Conversions

extension AIDJPlanRequest {
    /// Convert to backend request format
    func toBackendRequest() -> AIDJBackendRequest {
        AIDJBackendRequest(
            outgoingTrack: AIDJBackendTrackInfo(
                trackId: outgoingTrack.trackId,
                title: outgoingTrack.title,
                artist: outgoingTrack.artist,
                durationMs: Int(outgoingTrack.durationSeconds * 1000),
                bpm: outgoingTrack.bpm,
                beatOffsetMs: outgoingTrack.beatOffsetSeconds.map { Int($0 * 1000) },
                timingConfidence: outgoingTrack.timingConfidence
            ),
            incomingTrack: AIDJBackendTrackInfo(
                trackId: incomingTrack.trackId,
                title: incomingTrack.title,
                artist: incomingTrack.artist,
                durationMs: Int(incomingTrack.durationSeconds * 1000),
                bpm: incomingTrack.bpm,
                beatOffsetMs: incomingTrack.beatOffsetSeconds.map { Int($0 * 1000) },
                timingConfidence: incomingTrack.timingConfidence
            ),
            settings: AIDJBackendSettings(
                preferredFadeDurationMs: Int(settings.preferredFadeDurationSeconds * 1000),
                preferredCurve: settings.preferredCurve?.rawValue,
                allowTempoMatch: settings.allowTempoMatch,
                allowBeatSync: settings.allowBeatSync,
                allowEQPolish: settings.allowEQPolish
            )
        )
    }
}

extension AIDJBackendResponse {
    /// Convert backend response to a transition plan
    func toTransitionPlan() -> DJTransitionPlan {
        let curve = mapCrossfadeCurve(plan.crossfadeCurve)
        let alignment = mapBeatAlignment(plan.beatAlignment)

        let tempoMatch: DJTempoMatchConfig
        if let tm = plan.tempoMatch {
            tempoMatch = DJTempoMatchConfig(
                enabled: tm.enabled,
                targetBPM: tm.targetBpm ?? 0,
                maxRateAdjustment: tm.maxRateAdjustment ?? 0.08,
                preservePitch: true
            )
        } else {
            tempoMatch = .disabled
        }

        let outgoingEQ = plan.outgoingEQCurves?.map(mapEQCurve) ?? []
        let incomingEQ = plan.incomingEQCurves?.map(mapEQCurve) ?? []

        return DJTransitionPlan(
            fadeDurationSeconds: plan.fadeDurationSeconds,
            fadeStartSeconds: plan.fadeStartSeconds,
            crossfadeCurve: curve,
            outgoingEQCurves: outgoingEQ,
            incomingEQCurves: incomingEQ,
            tempoMatch: tempoMatch,
            beatAlignment: alignment,
            isFallback: false
        )
    }
}

private func mapCrossfadeCurve(_ value: String?) -> DJCrossfadeCurve {
    switch value?.lowercased() {
    case "equalpower": return .equalPower
    case "linear": return .linear
    case "scurve": return .sCurve
    case "logarithmic": return .exponential
    default: return .equalPower
    }
}

private func mapBeatAlignment(_ value: String?) -> DJBeatAlignmentMode {
    switch value?.lowercased() {
    case "beat": return .beat
    case "bar": return .bar
    default: return .none
    }
}

private func mapEQBand(_ value: String?) -> DJEQBand {
    switch value?.lowercased() {
    case "low": return .low
    case "mid": return .mid
    case "high": return .high
    default: return .mid
    }
}

private func mapEQCurve(_ curve: AIDJBackendEQCurve) -> DJEQCurve {
    DJEQCurve(
        band: mapEQBand(curve.band),
        keyframes: curve.keyframes.map { DJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
    )
}
