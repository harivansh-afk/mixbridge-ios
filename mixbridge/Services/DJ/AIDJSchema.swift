import Foundation
import MixBridgeDJ

// MARK: - Schema Version

enum AIDJSchemaVersion: Int, Codable, Sendable {
    case v1 = 1
    case v2 = 2 // Simplified absolute-only time semantics
}

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
    let preferredCurve: AIDJCrossfadeCurve?
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

// MARK: - Plan Response

struct AIDJPlanResponse: Codable, Sendable, Equatable {
    let plan: AIDJMixPlan
    let confidence: Double?
    let reasoning: String?
    let warnings: [String]?
}

// MARK: - Mix Plan (All Absolute Times)

/// The mix plan with all absolute time values (seconds from track start).
struct AIDJMixPlan: Codable, Sendable, Equatable {
    /// When to start fading out the outgoing track (seconds from outgoing track start)
    let outgoingFadeStartSeconds: Double

    /// Duration of the crossfade in seconds
    let fadeDurationSeconds: Double

    /// Crossfade curve type
    let crossfadeCurve: AIDJCrossfadeCurve

    /// When to start the incoming track relative to fade start (0 = at fade start)
    let incomingStartOffsetSeconds: Double

    /// Beat alignment mode
    let beatAlignment: AIDJBeatAlignmentMode

    /// Tempo matching configuration
    let tempoMatch: AIDJTempoMatch

    /// EQ curves for outgoing track (progress 0-1 through fade)
    let outgoingEQCurves: [AIDJEQCurve]

    /// EQ curves for incoming track (progress 0-1 through fade)
    let incomingEQCurves: [AIDJEQCurve]

    /// Whether this is a fallback plan (local, not AI-generated)
    let isFallback: Bool

    /// Convert to DJTransitionPlan for the mixer engine
    func toDJTransitionPlan() -> DJTransitionPlan {
        DJTransitionPlan(
            fadeDurationSeconds: fadeDurationSeconds,
            fadeStartSeconds: outgoingFadeStartSeconds,
            crossfadeCurve: crossfadeCurve.toDJ(),
            outgoingEQCurves: outgoingEQCurves.map { $0.toDJEQCurve() },
            incomingEQCurves: incomingEQCurves.map { $0.toDJEQCurve() },
            tempoMatch: tempoMatch.toDJConfig(),
            beatAlignment: beatAlignment.toDJ(),
            isFallback: isFallback
        )
    }
}

// MARK: - Validation Error

enum AIDJValidationError: Error, LocalizedError {
    case fadeExceedsTrackDuration(fadeEnd: Double, trackDuration: Double)
    case invalidFadeStart(value: Double)
    case invalidFadeDuration(value: Double)
    case invalidIncomingOffset(value: Double)

    var errorDescription: String? {
        switch self {
        case let .fadeExceedsTrackDuration(fadeEnd, duration):
            return "Fade end (\(String(format: "%.2f", fadeEnd))s) exceeds track duration (\(String(format: "%.2f", duration))s)"
        case let .invalidFadeStart(value):
            return "Invalid fade start: \(String(format: "%.2f", value))s"
        case let .invalidFadeDuration(value):
            return "Invalid fade duration: \(String(format: "%.2f", value))s"
        case let .invalidIncomingOffset(value):
            return "Invalid incoming offset: \(String(format: "%.2f", value))s"
        }
    }
}

// MARK: - Plan Validation

extension AIDJMixPlan {
    /// Validate the plan against track durations. Returns validated plan or throws.
    func validated(outgoingDuration: Double, incomingDuration _: Double) throws -> AIDJMixPlan {
        // Validate fade start
        guard outgoingFadeStartSeconds >= 0 else {
            throw AIDJValidationError.invalidFadeStart(value: outgoingFadeStartSeconds)
        }

        // Validate fade duration
        guard fadeDurationSeconds > 0 else {
            throw AIDJValidationError.invalidFadeDuration(value: fadeDurationSeconds)
        }

        // Validate fade fits within outgoing track
        let fadeEnd = outgoingFadeStartSeconds + fadeDurationSeconds
        guard fadeEnd <= outgoingDuration else {
            throw AIDJValidationError.fadeExceedsTrackDuration(fadeEnd: fadeEnd, trackDuration: outgoingDuration)
        }

        // Validate incoming offset
        guard incomingStartOffsetSeconds >= 0 else {
            throw AIDJValidationError.invalidIncomingOffset(value: incomingStartOffsetSeconds)
        }

        return self
    }

    /// Clamp the plan to valid bounds, returning a corrected plan.
    func clamped(outgoingDuration: Double, incomingDuration _: Double) -> AIDJMixPlan {
        let clampedFadeStart = max(0, min(outgoingFadeStartSeconds, outgoingDuration - 1))
        let maxFadeDuration = outgoingDuration - clampedFadeStart
        let clampedFadeDuration = max(0.5, min(fadeDurationSeconds, maxFadeDuration))
        let clampedIncomingOffset = max(0, incomingStartOffsetSeconds)

        return AIDJMixPlan(
            outgoingFadeStartSeconds: clampedFadeStart,
            fadeDurationSeconds: clampedFadeDuration,
            crossfadeCurve: crossfadeCurve,
            incomingStartOffsetSeconds: clampedIncomingOffset,
            beatAlignment: beatAlignment,
            tempoMatch: tempoMatch,
            outgoingEQCurves: outgoingEQCurves,
            incomingEQCurves: incomingEQCurves,
            isFallback: isFallback
        )
    }
}

// MARK: - Enums

enum AIDJCrossfadeCurve: String, Codable, Sendable {
    case equalPower
    case linear
    case sCurve
    case logarithmic

    func toDJ() -> DJCrossfadeCurve {
        switch self {
        case .equalPower: return .equalPower
        case .linear: return .linear
        case .sCurve, .logarithmic: return .constantPower
        }
    }

    static func fromBackend(_ value: String?) -> AIDJCrossfadeCurve {
        switch value?.lowercased() {
        case "equalpower": return .equalPower
        case "linear": return .linear
        case "scurve": return .sCurve
        case "logarithmic": return .logarithmic
        default: return .equalPower
        }
    }

    init(from fadeCurve: FadeCurve) {
        switch fadeCurve {
        case .linear: self = .linear
        case .equalPower: self = .equalPower
        case .sCurve: self = .sCurve
        case .exponential: self = .logarithmic
        }
    }
}

enum AIDJBeatAlignmentMode: String, Codable, Sendable {
    case beat
    case bar
    case none

    func toDJ() -> DJBeatAlignmentMode {
        switch self {
        case .beat: return .beat
        case .bar: return .bar
        case .none: return .none
        }
    }

    static func fromBackend(_ value: String?) -> AIDJBeatAlignmentMode {
        switch value?.lowercased() {
        case "beat": return .beat
        case "bar": return .bar
        default: return .none
        }
    }
}

enum AIDJEQBand: String, Codable, Sendable {
    case low
    case mid
    case high

    func toDJ() -> DJEQBand {
        switch self {
        case .low: return .low
        case .mid: return .mid
        case .high: return .high
        }
    }

    static func fromBackend(_ value: String?) -> AIDJEQBand {
        switch value?.lowercased() {
        case "low": return .low
        case "mid": return .mid
        case "high": return .high
        default: return .mid
        }
    }
}

// MARK: - EQ Types

struct AIDJEQKeyframe: Codable, Sendable, Equatable {
    /// Progress through the fade (0.0 to 1.0)
    let progress: Double
    /// Gain in decibels
    let gainDB: Double
}

struct AIDJEQCurve: Codable, Sendable, Equatable {
    let band: AIDJEQBand
    let keyframes: [AIDJEQKeyframe]

    func toDJEQCurve() -> DJEQCurve {
        DJEQCurve(
            band: band.toDJ(),
            keyframes: keyframes.map { DJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
        )
    }
}

// MARK: - Tempo Match

struct AIDJTempoMatch: Codable, Sendable, Equatable {
    let enabled: Bool
    let targetBPM: Double?
    let maxRateAdjustment: Double?
    let preservePitch: Bool?

    static let disabled = AIDJTempoMatch(enabled: false, targetBPM: nil, maxRateAdjustment: nil, preservePitch: nil)

    func toDJConfig() -> DJTempoMatchConfig {
        DJTempoMatchConfig(
            enabled: enabled,
            targetBPM: targetBPM ?? 0,
            maxRateAdjustment: maxRateAdjustment ?? 0.08,
            preservePitch: preservePitch ?? true
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
    /// Convert backend response to app-side plan response
    func toPlanResponse() -> AIDJPlanResponse {
        let curve = AIDJCrossfadeCurve.fromBackend(plan.crossfadeCurve)
        let alignment = AIDJBeatAlignmentMode.fromBackend(plan.beatAlignment)

        let tempoMatch: AIDJTempoMatch
        if let tm = plan.tempoMatch {
            tempoMatch = AIDJTempoMatch(
                enabled: tm.enabled,
                targetBPM: tm.targetBpm,
                maxRateAdjustment: tm.maxRateAdjustment,
                preservePitch: true
            )
        } else {
            tempoMatch = .disabled
        }

        let outgoingEQ = plan.outgoingEQCurves?.map { curve in
            AIDJEQCurve(
                band: AIDJEQBand.fromBackend(curve.band),
                keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
            )
        } ?? []

        let incomingEQ = plan.incomingEQCurves?.map { curve in
            AIDJEQCurve(
                band: AIDJEQBand.fromBackend(curve.band),
                keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
            )
        } ?? []

        return AIDJPlanResponse(
            plan: AIDJMixPlan(
                outgoingFadeStartSeconds: plan.fadeStartSeconds,
                fadeDurationSeconds: plan.fadeDurationSeconds,
                crossfadeCurve: curve,
                incomingStartOffsetSeconds: plan.incomingStartOffsetSeconds ?? 0,
                beatAlignment: alignment,
                tempoMatch: tempoMatch,
                outgoingEQCurves: outgoingEQ,
                incomingEQCurves: incomingEQ,
                isFallback: false
            ),
            confidence: confidence,
            reasoning: reasoning,
            warnings: warnings
        )
    }
}

// MARK: - Local Fallback Plan Builder

extension AIDJMixPlan {
    /// Create a fallback plan using local analysis (no AI)
    static func localFallback(
        outgoingDuration: Double,
        outgoingAnalysis: DJAnalysisResult,
        incomingAnalysis: DJAnalysisResult,
        settings: AIDJMixSettings
    ) -> AIDJMixPlan {
        let fadeDuration = min(settings.preferredFadeDurationSeconds, outgoingDuration * 0.5)
        let fadeStart = max(0, outgoingDuration - fadeDuration)

        let plannerSettings = DJTransitionPlannerSettings(
            crossfadeSeconds: fadeDuration,
            fadeCurve: settings.preferredCurve.map { curve -> FadeCurve in
                switch curve {
                case .equalPower: return .equalPower
                case .linear: return .linear
                case .sCurve: return .sCurve
                case .logarithmic: return .exponential
                }
            } ?? .equalPower,
            beatSyncEnabled: settings.allowBeatSync,
            tempoMatchEnabled: settings.allowTempoMatch,
            eqPolishEnabled: settings.allowEQPolish,
            preferBarSync: true,
            confidenceThreshold: 0.6
        )

        let djPlan = DJTransitionPlanner.makePlan(
            outgoing: outgoingAnalysis,
            incoming: incomingAnalysis,
            fadeStartSeconds: fadeStart,
            fadeDurationSeconds: fadeDuration,
            settings: plannerSettings
        )

        return AIDJMixPlan(
            outgoingFadeStartSeconds: djPlan.fadeStartSeconds,
            fadeDurationSeconds: djPlan.fadeDurationSeconds,
            crossfadeCurve: AIDJCrossfadeCurve.fromDJ(djPlan.crossfadeCurve),
            incomingStartOffsetSeconds: 0,
            beatAlignment: AIDJBeatAlignmentMode.fromDJ(djPlan.beatAlignment),
            tempoMatch: AIDJTempoMatch(
                enabled: djPlan.tempoMatch.enabled,
                targetBPM: djPlan.tempoMatch.targetBPM,
                maxRateAdjustment: djPlan.tempoMatch.maxRateAdjustment,
                preservePitch: djPlan.tempoMatch.preservePitch
            ),
            outgoingEQCurves: djPlan.outgoingEQCurves.map { curve in
                AIDJEQCurve(
                    band: AIDJEQBand.fromDJ(curve.band),
                    keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
                )
            },
            incomingEQCurves: djPlan.incomingEQCurves.map { curve in
                AIDJEQCurve(
                    band: AIDJEQBand.fromDJ(curve.band),
                    keyframes: curve.keyframes.map { AIDJEQKeyframe(progress: $0.progress, gainDB: $0.gainDB) }
                )
            },
            isFallback: true
        )
    }
}

// MARK: - DJ Type Conversions

extension AIDJCrossfadeCurve {
    static func fromDJ(_ curve: DJCrossfadeCurve) -> AIDJCrossfadeCurve {
        switch curve {
        case .equalPower: return .equalPower
        case .linear: return .linear
        case .constantPower: return .sCurve
        }
    }
}

extension AIDJBeatAlignmentMode {
    static func fromDJ(_ mode: DJBeatAlignmentMode) -> AIDJBeatAlignmentMode {
        switch mode {
        case .beat: return .beat
        case .bar: return .bar
        case .none: return .none
        }
    }
}

extension AIDJEQBand {
    static func fromDJ(_ band: DJEQBand) -> AIDJEQBand {
        switch band {
        case .low: return .low
        case .mid: return .mid
        case .high: return .high
        }
    }
}
