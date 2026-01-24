//
//  MixControlsSettings.swift
//  mixbridge
//

import Foundation

struct MixControlsSettings: Codable, Equatable, Sendable {
    var bpmMatchEnabled: Bool = true
    /// Max tempo adjustment as a fraction (e.g. 0.08 for ±8%).
    var maxRateAdjustment: Double = 0.08

    /// Swap depths are 0.0 - 1.0, where 1.0 maps to full -24dB cut.
    var bassSwapDepth: Double = 0.65
    var midsSwapDepth: Double = 0.50
    var highsSwapDepth: Double = 0.40

    /// Blend length for DJ transitions (seconds).
    var blendLengthSeconds: Double = 8.0

    static let `default` = MixControlsSettings()

    func clampedMaxRateAdjustment() -> Double {
        let allowed = [0.04, 0.06, 0.08]
        if let nearest = allowed.min(by: { abs($0 - maxRateAdjustment) < abs($1 - maxRateAdjustment) }) {
            return nearest
        }
        return 0.08
    }

    func clampedSwapDepth(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    func clampedBlendLength() -> Double {
        max(2.0, min(20.0, blendLengthSeconds))
    }

    var hasAnyEQSwap: Bool {
        clampedSwapDepth(bassSwapDepth) > 0.001 ||
        clampedSwapDepth(midsSwapDepth) > 0.001 ||
        clampedSwapDepth(highsSwapDepth) > 0.001
    }
}
