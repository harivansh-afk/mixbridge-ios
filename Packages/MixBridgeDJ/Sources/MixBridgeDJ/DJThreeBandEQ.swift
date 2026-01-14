import AVFoundation

/// Configuration for a single EQ band.
public struct DJEQBandConfig: Sendable {
    /// Center frequency in Hz.
    public let frequency: Float

    /// Bandwidth in octaves.
    public let bandwidth: Float

    /// Filter type for this band.
    public let filterType: AVAudioUnitEQFilterType

    public init(frequency: Float, bandwidth: Float, filterType: AVAudioUnitEQFilterType) {
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.filterType = filterType
    }
}

/// 3-band equalizer using AVAudioUnitEQ.
/// Provides low/mid/high band control for DJ mixing.
public final class DJThreeBandEQ: @unchecked Sendable {
    /// The underlying AVAudioUnitEQ node.
    public let eqNode: AVAudioUnitEQ

    /// Band configuration (low, mid, high frequencies).
    public let bandConfigs: [DJEQBandConfig]

    /// Default band configuration for DJ mixing.
    /// Low: 80Hz (low shelf), Mid: 1kHz (parametric), High: 8kHz (high shelf)
    public static let defaultBandConfigs: [DJEQBandConfig] = [
        DJEQBandConfig(frequency: 80, bandwidth: 1.0, filterType: .lowShelf),
        DJEQBandConfig(frequency: 1000, bandwidth: 1.0, filterType: .parametric),
        DJEQBandConfig(frequency: 8000, bandwidth: 1.0, filterType: .highShelf)
    ]

    /// Minimum gain in dB.
    public static let minGainDB: Float = -24.0

    /// Maximum gain in dB.
    public static let maxGainDB: Float = 12.0

    /// Creates a 3-band EQ with the specified configuration.
    /// - Parameter bandConfigs: Configuration for each band. Defaults to standard DJ bands.
    public init(bandConfigs: [DJEQBandConfig] = defaultBandConfigs) {
        precondition(bandConfigs.count == 3, "DJThreeBandEQ requires exactly 3 bands")

        self.bandConfigs = bandConfigs
        self.eqNode = AVAudioUnitEQ(numberOfBands: 3)

        // Configure each band
        for (index, config) in bandConfigs.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = config.filterType
            band.frequency = config.frequency
            band.bandwidth = config.bandwidth
            band.gain = 0.0 // Start flat
            band.bypass = false
        }

        // Enable global bypass control
        eqNode.globalGain = 0.0
    }

    /// Sets the gain for a specific band.
    /// - Parameters:
    ///   - band: Which band to adjust.
    ///   - gainDB: Gain in decibels (clamped to safe range).
    public func setGain(band: DJEQBand, gainDB: Float) {
        let index = bandIndex(for: band)
        let clampedGain = max(Self.minGainDB, min(Self.maxGainDB, gainDB))
        eqNode.bands[index].gain = clampedGain
    }

    /// Gets the current gain for a specific band.
    /// - Parameter band: Which band to query.
    /// - Returns: Current gain in decibels.
    public func getGain(band: DJEQBand) -> Float {
        let index = bandIndex(for: band)
        return eqNode.bands[index].gain
    }

    /// Sets gains for all bands at once.
    /// - Parameter gains: Dictionary of band to gain in dB.
    public func setGains(_ gains: [DJEQBand: Float]) {
        for (band, gain) in gains {
            setGain(band: band, gainDB: gain)
        }
    }

    /// Resets all bands to 0dB (flat response).
    public func reset() {
        for band in DJEQBand.allCases {
            setGain(band: band, gainDB: 0.0)
        }
    }

    /// Applies gains from EQ curves at a specific progress point.
    /// - Parameters:
    ///   - curves: Array of EQ curves to apply.
    ///   - progress: Transition progress (0.0 to 1.0).
    public func applyEQCurves(_ curves: [DJEQCurve], at progress: Double) {
        for curve in curves {
            let gainDB = curve.gain(at: progress)
            setGain(band: curve.band, gainDB: Float(gainDB))
        }
    }

    /// Bypasses the entire EQ.
    /// - Parameter bypassed: Whether to bypass.
    public func setBypassed(_ bypassed: Bool) {
        for band in eqNode.bands {
            band.bypass = bypassed
        }
    }

    // MARK: - Private

    private func bandIndex(for band: DJEQBand) -> Int {
        switch band {
        case .low: return 0
        case .mid: return 1
        case .high: return 2
        }
    }
}

// MARK: - DJThreeBandEQ Snapshot for testing

/// Snapshot of EQ state for comparison in tests.
public struct DJEQSnapshot: Sendable, Equatable {
    public let lowGainDB: Float
    public let midGainDB: Float
    public let highGainDB: Float

    public init(lowGainDB: Float, midGainDB: Float, highGainDB: Float) {
        self.lowGainDB = lowGainDB
        self.midGainDB = midGainDB
        self.highGainDB = highGainDB
    }

    public init(from eq: DJThreeBandEQ) {
        self.lowGainDB = eq.getGain(band: .low)
        self.midGainDB = eq.getGain(band: .mid)
        self.highGainDB = eq.getGain(band: .high)
    }

    /// Returns the total absolute gain change from flat.
    public var totalAbsoluteGain: Float {
        abs(lowGainDB) + abs(midGainDB) + abs(highGainDB)
    }
}
