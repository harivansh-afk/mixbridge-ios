import Foundation

/// Crossfade curve type for volume transitions.
/// This is the single source of truth for fade curves across streaming and DJ mixing.
public enum DJCrossfadeCurve: String, Sendable, Equatable, Codable, CaseIterable {
    /// Linear crossfade (simple volume ramp).
    case linear

    /// Equal-power crossfade using sine/cosine curves.
    /// Maintains perceived loudness throughout the transition.
    case equalPower

    /// Smooth S-curve using smoothstep - gradual start and end.
    case sCurve

    /// Exponential curve - aggressive quick drop then long tail.
    case exponential

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .equalPower: return "Equal Power"
        case .sCurve: return "S-Curve"
        case .exponential: return "Exponential"
        }
    }

    /// Calculate fade-out gain (1 -> 0) for the outgoing track.
    /// - Parameter progress: 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier 0.0 to 1.0
    public func fadeOutGain(progress: Double) -> Double {
        let p = min(1.0, max(0.0, progress))

        switch self {
        case .linear:
            return 1.0 - p

        case .equalPower:
            return cos(p * .pi / 2)

        case .sCurve:
            let smoothed = p * p * (3.0 - 2.0 * p)
            return 1.0 - smoothed

        case .exponential:
            return pow(1.0 - p, 3)
        }
    }

    /// Calculate fade-in gain (0 -> 1) for the incoming track.
    /// - Parameter progress: 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier 0.0 to 1.0
    public func fadeInGain(progress: Double) -> Double {
        let p = min(1.0, max(0.0, progress))

        switch self {
        case .linear:
            return p

        case .equalPower:
            return sin(p * .pi / 2)

        case .sCurve:
            return p * p * (3.0 - 2.0 * p)

        case .exponential:
            return pow(p, 3)
        }
    }
}

/// EQ band identifiers for 3-band equalizer.
public enum DJEQBand: String, Sendable, Equatable, Codable, CaseIterable {
    case low
    case mid
    case high
}

/// Time-varying EQ gain value at a specific point in the transition.
public struct DJEQKeyframe: Sendable, Equatable, Codable {
    /// Progress through the transition (0.0 = start, 1.0 = end).
    public let progress: Double

    /// Gain in decibels for this keyframe (-24 to +12 dB typical range).
    public let gainDB: Double

    public init(progress: Double, gainDB: Double) {
        self.progress = max(0.0, min(1.0, progress))
        self.gainDB = gainDB
    }
}

/// EQ curve for a single band during a transition.
public struct DJEQCurve: Sendable, Equatable, Codable {
    public let band: DJEQBand
    public let keyframes: [DJEQKeyframe]

    public init(band: DJEQBand, keyframes: [DJEQKeyframe]) {
        self.band = band
        // Sort keyframes by progress and ensure at least start/end points
        var sorted = keyframes.sorted { $0.progress < $1.progress }
        if sorted.isEmpty || sorted.first!.progress > 0 {
            sorted.insert(DJEQKeyframe(progress: 0.0, gainDB: 0.0), at: 0)
        }
        if sorted.last!.progress < 1.0 {
            sorted.append(DJEQKeyframe(progress: 1.0, gainDB: sorted.last!.gainDB))
        }
        self.keyframes = sorted
    }

    /// Interpolates gain at a given progress point.
    public func gain(at progress: Double) -> Double {
        let clampedProgress = max(0.0, min(1.0, progress))

        // Find surrounding keyframes
        var lower = keyframes.first!
        var upper = keyframes.last!

        for i in 0..<keyframes.count - 1 {
            if keyframes[i].progress <= clampedProgress && keyframes[i + 1].progress >= clampedProgress {
                lower = keyframes[i]
                upper = keyframes[i + 1]
                break
            }
        }

        // Linear interpolation between keyframes
        let range = upper.progress - lower.progress
        guard range > 0 else { return lower.gainDB }

        let t = (clampedProgress - lower.progress) / range
        return lower.gainDB + (upper.gainDB - lower.gainDB) * t
    }

    /// Creates a flat EQ curve at 0dB.
    public static func flat(band: DJEQBand) -> DJEQCurve {
        DJEQCurve(band: band, keyframes: [
            DJEQKeyframe(progress: 0.0, gainDB: 0.0),
            DJEQKeyframe(progress: 1.0, gainDB: 0.0)
        ])
    }

    /// Creates a high-frequency duck curve for incoming track.
    /// Reduces highs during first half of fade, then restores.
    public static func highDuckIncoming(band: DJEQBand = .high) -> DJEQCurve {
        DJEQCurve(band: band, keyframes: [
            DJEQKeyframe(progress: 0.0, gainDB: -12.0),
            DJEQKeyframe(progress: 0.5, gainDB: -6.0),
            DJEQKeyframe(progress: 1.0, gainDB: 0.0)
        ])
    }
}

/// Tempo matching configuration for a transition.
public struct DJTempoMatchConfig: Sendable, Equatable, Codable {
    /// Whether tempo matching is enabled.
    public let enabled: Bool

    /// The target BPM (typically the outgoing track's BPM).
    public let targetBPM: Double

    /// Maximum rate adjustment allowed (e.g., 0.08 for +/-8%).
    public let maxRateAdjustment: Double

    /// Whether to preserve pitch during tempo change.
    public let preservePitch: Bool

    public init(
        enabled: Bool = true,
        targetBPM: Double = 0.0,
        maxRateAdjustment: Double = 0.08,
        preservePitch: Bool = true
    ) {
        self.enabled = enabled
        self.targetBPM = targetBPM
        self.maxRateAdjustment = maxRateAdjustment
        self.preservePitch = preservePitch
    }

    /// Computes the playback rate for the incoming track.
    /// Rate = bpmA / bpmB, clamped to safe range.
    /// - Parameter incomingBPM: BPM of the incoming track.
    /// - Returns: Playback rate (1.0 = normal speed).
    public func computeRate(incomingBPM: Double) -> Double {
        guard enabled, targetBPM > 0, incomingBPM > 0 else { return 1.0 }

        // Compute ideal rate: incoming plays at outgoing's tempo
        // rate = targetBPM / incomingBPM (to make incoming match target)
        let idealRate = targetBPM / incomingBPM

        // Clamp to safe range
        let minRate = 1.0 - maxRateAdjustment
        let maxRate = 1.0 + maxRateAdjustment

        return max(minRate, min(maxRate, idealRate))
    }

    /// Creates a disabled tempo match config.
    public static var disabled: DJTempoMatchConfig {
        DJTempoMatchConfig(enabled: false)
    }
}

/// Beat alignment mode for starting the incoming track.
public enum DJBeatAlignmentMode: String, Sendable, Equatable, Codable {
    /// Align to the next beat boundary.
    case beat

    /// Align to the next bar (measure) boundary.
    case bar

    /// No beat alignment - start immediately.
    case none
}

/// Complete transition plan for mixing from deck A to deck B.
public struct DJTransitionPlan: Sendable, Equatable, Codable {
    /// Duration of the crossfade in seconds.
    public let fadeDurationSeconds: Double

    /// When to start the fade (seconds into deck A playback).
    public let fadeStartSeconds: Double

    /// Type of crossfade curve to use.
    public let crossfadeCurve: DJCrossfadeCurve

    /// EQ curves for the outgoing deck (A) during the transition.
    public let outgoingEQCurves: [DJEQCurve]

    /// EQ curves for the incoming deck (B) during the transition.
    public let incomingEQCurves: [DJEQCurve]

    /// Tempo matching configuration.
    public let tempoMatch: DJTempoMatchConfig

    /// Beat alignment mode.
    public let beatAlignment: DJBeatAlignmentMode

    /// Whether this is a fallback plan (used when validation fails).
    public let isFallback: Bool

    public init(
        fadeDurationSeconds: Double,
        fadeStartSeconds: Double,
        crossfadeCurve: DJCrossfadeCurve = .equalPower,
        outgoingEQCurves: [DJEQCurve] = [],
        incomingEQCurves: [DJEQCurve] = [],
        tempoMatch: DJTempoMatchConfig = .disabled,
        beatAlignment: DJBeatAlignmentMode = .beat,
        isFallback: Bool = false
    ) {
        self.fadeDurationSeconds = fadeDurationSeconds
        self.fadeStartSeconds = fadeStartSeconds
        self.crossfadeCurve = crossfadeCurve
        self.outgoingEQCurves = outgoingEQCurves
        self.incomingEQCurves = incomingEQCurves
        self.tempoMatch = tempoMatch
        self.beatAlignment = beatAlignment
        self.isFallback = isFallback
    }

    /// Computes the crossfade gains at a given progress point.
    /// - Parameter progress: Transition progress (0.0 = start, 1.0 = end).
    /// - Returns: Tuple of (outgoingGain, incomingGain) as linear values.
    public func crossfadeGains(at progress: Double) -> (outgoing: Double, incoming: Double) {
        (crossfadeCurve.fadeOutGain(progress: progress), crossfadeCurve.fadeInGain(progress: progress))
    }

    /// Computes the scheduled start time for the incoming track
    /// based on beat alignment and the outgoing track's timing.
    /// - Parameters:
    ///   - outgoingTiming: Timing info for the outgoing track.
    ///   - fadeStartTime: When the fade starts in the outgoing track.
    /// - Returns: Time offset (in outgoing track's timeline) when incoming should start.
    public func computeIncomingStartTime(
        outgoingTiming: DJTrackTiming,
        fadeStartTime: Double
    ) -> Double {
        switch beatAlignment {
        case .none:
            return fadeStartTime

        case .beat:
            // Align to next beat boundary at or after fade start
            return outgoingTiming.nextBeatBoundary(after: fadeStartTime)

        case .bar:
            // Align to next bar boundary at or after fade start
            return outgoingTiming.nextBarBoundary(after: fadeStartTime)
        }
    }

    /// Creates a fallback plan with safe defaults.
    /// Used when validation fails or timing confidence is low.
    public static func fallback(fadeDuration: Double = 8.0, fadeStart: Double = 0.0) -> DJTransitionPlan {
        DJTransitionPlan(
            fadeDurationSeconds: fadeDuration,
            fadeStartSeconds: fadeStart,
            crossfadeCurve: .equalPower,
            outgoingEQCurves: DJEQBand.allCases.map { .flat(band: $0) },
            incomingEQCurves: DJEQBand.allCases.map { .flat(band: $0) },
            tempoMatch: .disabled,
            beatAlignment: .none,
            isFallback: true
        )
    }
}
