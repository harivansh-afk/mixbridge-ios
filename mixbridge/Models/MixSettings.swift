//
//  MixSettings.swift
//  mixbridge
//
//  Fade curve types and mix transition settings.
//

import Foundation
import MixBridgeDJ

// MARK: - Fade Curve Types

/// Different volume curve algorithms for crossfading between tracks
enum FadeCurve: String, CaseIterable, Codable {
    case linear
    case equalPower      // Current default - maintains perceived loudness
    case sCurve          // Extra smooth, gradual start/end
    case exponential     // Aggressive, quick drop then long tail

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .equalPower: return "Equal Power"
        case .sCurve: return "S-Curve"
        case .exponential: return "Exponential"
        }
    }

    var description: String {
        switch self {
        case .linear: return "Simple straight-line fade"
        case .equalPower: return "Smooth, maintains loudness"
        case .sCurve: return "Extra smooth transitions"
        case .exponential: return "Quick drop, long tail"
        }
    }

    /// Calculate fade-out gain (1 -> 0) for the outgoing track
    /// - Parameter progress: 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier 0.0 to 1.0
    func fadeOutGain(progress: Double) -> Float {
        let p = min(1.0, max(0.0, progress))

        switch self {
        case .linear:
            // Simple linear ramp down
            return Float(1.0 - p)

        case .equalPower:
            // Cosine curve - maintains perceived loudness during crossfade
            return Float(cos(p * .pi / 2))

        case .sCurve:
            // Smooth S-curve using smoothstep - gradual start and end
            let smoothed = p * p * (3.0 - 2.0 * p)
            return Float(1.0 - smoothed)

        case .exponential:
            // Exponential decay - quick initial drop, long tail
            // Using power of 3 for more aggressive curve
            return Float(pow(1.0 - p, 3))
        }
    }

    /// Calculate fade-in gain (0 -> 1) for the incoming track
    /// - Parameter progress: 0.0 (start) to 1.0 (end)
    /// - Returns: Volume multiplier 0.0 to 1.0
    func fadeInGain(progress: Double) -> Float {
        let p = min(1.0, max(0.0, progress))

        switch self {
        case .linear:
            // Simple linear ramp up
            return Float(p)

        case .equalPower:
            // Sine curve - maintains perceived loudness during crossfade
            return Float(sin(p * .pi / 2))

        case .sCurve:
            // Smooth S-curve using smoothstep
            let smoothed = p * p * (3.0 - 2.0 * p)
            return Float(smoothed)

        case .exponential:
            // Exponential rise - slow start, quick finish
            return Float(pow(p, 3))
        }
    }

    /// Convert to the unified DJCrossfadeCurve type from MixBridgeDJ package.
    func toDJCrossfadeCurve() -> DJCrossfadeCurve {
        switch self {
        case .linear: return .linear
        case .equalPower: return .equalPower
        case .sCurve: return .sCurve
        case .exponential: return .exponential
        }
    }
}
