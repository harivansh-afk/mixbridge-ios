import AVFoundation
import Accelerate
import Foundation

/// Local audio analyzer for BPM and beat phase detection.
/// Uses onset detection and autocorrelation for deterministic BPM estimation.
public actor DJLocalAnalyzer {

    /// Cache store for persisting analysis results.
    private let store: any DJAnalysisStore

    /// Default analysis options.
    private let defaultOptions: DJAnalysisOptions

    /// Creates an analyzer with the specified cache store.
    /// - Parameters:
    ///   - store: Cache store for persisting results.
    ///   - options: Default analysis options.
    public init(
        store: any DJAnalysisStore = DJNullAnalysisStore(),
        options: DJAnalysisOptions = .default
    ) {
        self.store = store
        self.defaultOptions = options
    }

    /// Analyzes the audio file at the given URL.
    /// - Parameters:
    ///   - url: Local file URL to analyze.
    ///   - trackId: Optional track identifier for caching. Uses filename if not provided.
    ///   - options: Analysis options. Uses default if not provided.
    /// - Returns: Analysis result with BPM, beat offset, and confidence.
    public func analyze(
        url: URL,
        trackId: String? = nil,
        options: DJAnalysisOptions? = nil
    ) async throws -> DJAnalysisResult {
        let opts = options ?? defaultOptions
        let id = trackId ?? url.lastPathComponent

        // Check file identity for caching
        guard let fileIdentity = FileIdentity.from(url: url) else {
            throw DJAnalysisError.fileNotFound(url)
        }

        // Check cache first
        if let cached = await store.get(trackId: id, fileIdentity: fileIdentity) {
            return cached
        }

        // Perform analysis
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await performAnalysis(url: url, options: opts)
        let duration = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        // Update metadata with timing
        let finalResult = DJAnalysisResult(
            bpm: result.bpm,
            beatOffsetSeconds: result.beatOffsetSeconds,
            timeSignatureNumerator: result.timeSignatureNumerator,
            timeSignatureDenominator: result.timeSignatureDenominator,
            confidence: result.confidence,
            metadata: AnalysisMetadata(
                analysisVersion: AnalysisMetadata.currentVersion,
                analysisDurationMs: duration,
                failureReason: result.metadata.failureReason
            )
        )

        // Cache result
        await store.put(result: finalResult, trackId: id, fileIdentity: fileIdentity)

        return finalResult
    }

    // MARK: - Core Analysis

    private func performAnalysis(url: URL, options: DJAnalysisOptions) async throws -> DJAnalysisResult {
        // Load and convert audio to mono Float32
        let audioData = try await loadAudioData(from: url, options: options)

        guard audioData.samples.count > 0 else {
            return .lowConfidence(reason: "Empty audio file")
        }

        // Compute onset detection function
        let onsets = computeOnsetFunction(
            samples: audioData.samples,
            sampleRate: audioData.sampleRate,
            options: options
        )

        guard onsets.count > 10 else {
            return .lowConfidence(reason: "Insufficient audio duration for analysis")
        }

        // Estimate BPM using autocorrelation
        let bpmResult = estimateBPM(
            onsets: onsets,
            hopRate: audioData.sampleRate / Double(options.hopSizeSamples),
            options: options
        )

        guard bpmResult.confidence > 0.1 else {
            return .nonPeriodic()
        }

        // Find beat offset (phase)
        let beatOffset = findBeatOffset(
            onsets: onsets,
            bpm: bpmResult.bpm,
            hopRate: audioData.sampleRate / Double(options.hopSizeSamples),
            options: options
        )

        return DJAnalysisResult(
            bpm: bpmResult.bpm,
            beatOffsetSeconds: beatOffset,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            confidence: bpmResult.confidence
        )
    }

    // MARK: - Audio Loading

    private struct AudioData {
        let samples: [Float]
        let sampleRate: Double
    }

    private func loadAudioData(from url: URL, options: DJAnalysisOptions) async throws -> AudioData {
        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat

        // Target format: mono Float32 at analysis sample rate
        let targetSampleRate = options.analysisSampleRate
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DJAnalysisError.formatConversionFailed
        }

        // Calculate how many samples to analyze
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let sourceSampleRate = sourceFormat.sampleRate
        let maxSourceFrames = AVAudioFrameCount(options.maxAnalysisDurationSeconds * sourceSampleRate)
        let framesToRead = min(totalFrames, maxSourceFrames)

        // Read in chunks to avoid loading entire file
        let chunkSize: AVAudioFrameCount = 65536
        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(Double(framesToRead) * targetSampleRate / sourceSampleRate))

        var framesRead: AVAudioFrameCount = 0

        // Create converter if needed
        let needsConversion = sourceFormat.sampleRate != targetSampleRate ||
                              sourceFormat.channelCount != 1

        var converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }

        while framesRead < framesToRead {
            let framesToReadThisChunk = min(chunkSize, framesToRead - framesRead)

            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: framesToReadThisChunk
            ) else {
                throw DJAnalysisError.bufferAllocationFailed
            }

            try audioFile.read(into: sourceBuffer, frameCount: framesToReadThisChunk)
            let actualFramesRead = sourceBuffer.frameLength

            if actualFramesRead == 0 {
                break
            }

            // Convert to mono Float32 at target sample rate
            let monoSamples: [Float]
            if let conv = converter {
                monoSamples = try convertBuffer(sourceBuffer, using: conv, targetFormat: targetFormat)
            } else {
                monoSamples = extractMonoSamples(from: sourceBuffer)
            }

            allSamples.append(contentsOf: monoSamples)
            framesRead += actualFramesRead
        }

        return AudioData(samples: allSamples, sampleRate: targetSampleRate)
    }

    private func convertBuffer(
        _ source: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) throws -> [Float] {
        // Estimate output size
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(Double(source.frameLength) * ratio) + 100

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedOutputFrames
        ) else {
            throw DJAnalysisError.bufferAllocationFailed
        }

        var error: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return source
        }

        if status == .error, let err = error {
            throw DJAnalysisError.conversionError(err.localizedDescription)
        }

        return extractMonoSamples(from: outputBuffer)
    }

    private func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        // Mix down to mono
        var monoSamples = [Float](repeating: 0, count: frameCount)
        let scale = 1.0 / Float(channelCount)

        for ch in 0..<channelCount {
            vDSP_vsma(channelData[ch], 1, [scale], monoSamples, 1, &monoSamples, 1, vDSP_Length(frameCount))
        }

        return monoSamples
    }

    // MARK: - Onset Detection

    private func computeOnsetFunction(
        samples: [Float],
        sampleRate: Double,
        options: DJAnalysisOptions
    ) -> [Float] {
        let windowSize = options.windowSizeSamples
        let hopSize = options.hopSizeSamples

        guard samples.count > windowSize else { return [] }

        let numFrames = (samples.count - windowSize) / hopSize + 1
        var onsets = [Float](repeating: 0, count: numFrames)

        // Energy-based onset detection with spectral emphasis
        var prevEnergy: Float = 0

        for i in 0..<numFrames {
            let startIdx = i * hopSize
            let endIdx = min(startIdx + windowSize, samples.count)
            let frameLength = endIdx - startIdx

            // Compute frame energy using vDSP
            var energy: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                let framePtr = ptr.baseAddress! + startIdx
                vDSP_svesq(framePtr, 1, &energy, vDSP_Length(frameLength))
            }
            energy = sqrt(energy / Float(frameLength))

            // Half-wave rectified first difference (onset strength)
            let diff = max(0, energy - prevEnergy)
            onsets[i] = diff

            prevEnergy = energy
        }

        // Normalize onset function
        var maxOnset: Float = 0
        vDSP_maxv(onsets, 1, &maxOnset, vDSP_Length(numFrames))

        if maxOnset > 0 {
            var scale = 1.0 / maxOnset
            vDSP_vsmul(onsets, 1, &scale, &onsets, 1, vDSP_Length(numFrames))
        }

        return onsets
    }

    // MARK: - BPM Estimation

    private struct BPMResult {
        let bpm: Double
        let confidence: Double
    }

    private func estimateBPM(
        onsets: [Float],
        hopRate: Double,
        options: DJAnalysisOptions
    ) -> BPMResult {
        // Convert BPM range to lag range in onset frames
        let minLag = Int(hopRate * options.minBeatIntervalSeconds)
        let maxLag = Int(hopRate * options.maxBeatIntervalSeconds)

        guard minLag > 0, maxLag > minLag, onsets.count > maxLag * 2 else {
            return BPMResult(bpm: 0, confidence: 0)
        }

        // Compute autocorrelation using vDSP
        let autocorr = computeAutocorrelation(onsets, maxLag: maxLag)

        // Find all significant peaks in the autocorrelation
        let peaks = findAutocorrPeaks(autocorr, minLag: minLag, maxLag: maxLag)

        guard !peaks.isEmpty else {
            return BPMResult(bpm: 0, confidence: 0)
        }

        // Select the best peak, resolving octave ambiguity
        let bestPeak = resolveOctaveAmbiguity(
            peaks: peaks,
            autocorr: autocorr,
            minLag: minLag,
            maxLag: maxLag,
            hopRate: hopRate,
            options: options
        )

        // Refine peak using parabolic interpolation
        let refinedLag = refinePeak(autocorr, peakIndex: bestPeak.lag)

        // Convert lag to BPM
        let bpm = 60.0 * hopRate / refinedLag

        // Calculate confidence from peak sharpness and periodicity strength
        let confidence = calculateConfidence(
            autocorr: autocorr,
            peakLag: bestPeak.lag,
            peakValue: bestPeak.value,
            minLag: minLag,
            maxLag: maxLag
        )

        return BPMResult(bpm: bpm, confidence: Double(confidence))
    }

    private struct AutocorrPeak {
        let lag: Int
        let value: Float
    }

    private func findAutocorrPeaks(
        _ autocorr: [Float],
        minLag: Int,
        maxLag: Int
    ) -> [AutocorrPeak] {
        var peaks: [AutocorrPeak] = []
        let end = min(maxLag, autocorr.count - 2)

        guard end > minLag else { return peaks }

        for lag in (minLag + 1)..<end {
            let prev = autocorr[lag - 1]
            let curr = autocorr[lag]
            let next = autocorr[lag + 1]

            // Local maximum
            if curr > prev && curr > next && curr > 0.1 {
                peaks.append(AutocorrPeak(lag: lag, value: curr))
            }
        }

        // Sort by value descending
        peaks.sort { $0.value > $1.value }

        // Keep top peaks
        return Array(peaks.prefix(10))
    }

    private func resolveOctaveAmbiguity(
        peaks: [AutocorrPeak],
        autocorr: [Float],
        minLag: Int,
        maxLag: Int,
        hopRate: Double,
        options: DJAnalysisOptions
    ) -> AutocorrPeak {
        guard let primaryPeak = peaks.first else {
            return AutocorrPeak(lag: minLag, value: 0)
        }

        // Check if there's a peak at half the lag (double the BPM)
        // This would indicate the primary peak is a sub-harmonic (octave error)
        let halfLag = primaryPeak.lag / 2

        if halfLag >= minLag {
            // Look for a peak near half the lag
            for peak in peaks {
                let lagRatio = Double(primaryPeak.lag) / Double(peak.lag)

                // Check if this peak is at approximately double the BPM
                if lagRatio > 1.9 && lagRatio < 2.1 {
                    // Found a potential true fundamental at higher BPM
                    // Prefer it if it has reasonable strength (at least 60% of primary)
                    if peak.value > primaryPeak.value * 0.6 {
                        let higherBPM = 60.0 * hopRate / Double(peak.lag)
                        // Ensure it's within our BPM range
                        if higherBPM >= options.minBPM && higherBPM <= options.maxBPM {
                            return peak
                        }
                    }
                }
            }

            // Also check autocorr value directly at half lag
            if halfLag < autocorr.count {
                let halfLagValue = autocorr[halfLag]
                // If there's significant correlation at half lag, prefer it
                if halfLagValue > primaryPeak.value * 0.5 {
                    let higherBPM = 60.0 * hopRate / Double(halfLag)
                    if higherBPM >= options.minBPM && higherBPM <= options.maxBPM {
                        return AutocorrPeak(lag: halfLag, value: halfLagValue)
                    }
                }
            }
        }

        return primaryPeak
    }

    private func computeAutocorrelation(_ signal: [Float], maxLag: Int) -> [Float] {
        let n = signal.count
        var result = [Float](repeating: 0, count: maxLag + 1)

        // Use vDSP for efficient autocorrelation
        for lag in 0...maxLag {
            let length = n - lag
            guard length > 0 else { break }

            var sum: Float = 0
            signal.withUnsafeBufferPointer { ptr in
                vDSP_dotpr(ptr.baseAddress!, 1, ptr.baseAddress! + lag, 1, &sum, vDSP_Length(length))
            }
            result[lag] = sum / Float(length)
        }

        // Normalize by zero-lag value
        if result[0] > 0 {
            let norm = result[0]
            for i in 0..<result.count {
                result[i] /= norm
            }
        }

        return result
    }

    private func refinePeak(_ values: [Float], peakIndex: Int) -> Double {
        guard peakIndex > 0, peakIndex < values.count - 1 else {
            return Double(peakIndex)
        }

        let a = Double(values[peakIndex - 1])
        let b = Double(values[peakIndex])
        let c = Double(values[peakIndex + 1])

        // Parabolic interpolation to find sub-sample peak location
        // Fit quadratic y = A*x^2 + B*x + C through points at x = -1, 0, 1
        // Peak is at x = -B / (2*A) = (a - c) / (2 * (a - 2*b + c))
        let denominator = 2.0 * (a - 2.0 * b + c)
        guard abs(denominator) > 1e-10 else {
            return Double(peakIndex)
        }

        let offset = (a - c) / denominator
        // Clamp to reasonable range to avoid wild extrapolation
        let clampedOffset = max(-0.5, min(0.5, offset))
        return Double(peakIndex) + clampedOffset
    }

    private func calculateConfidence(
        autocorr: [Float],
        peakLag: Int,
        peakValue: Float,
        minLag: Int,
        maxLag: Int
    ) -> Float {
        // Confidence based on:
        // 1. Peak height relative to surrounding values
        // 2. Presence of harmonics (peaks at 2x, 0.5x the period)
        // 3. Peak sharpness

        guard peakValue > 0.1 else { return 0 }

        // Calculate local mean around the peak (excluding peak region)
        var localSum: Float = 0
        var localCount = 0

        for lag in minLag...min(maxLag, autocorr.count - 1) {
            // Skip region around main peak
            if abs(lag - peakLag) > 5 {
                localSum += autocorr[lag]
                localCount += 1
            }
        }

        let localMean = localCount > 0 ? localSum / Float(localCount) : 0.1
        let peakRatio = peakValue / max(localMean, 0.01)

        // Check for harmonic at 2x the period (half the BPM)
        let harmonic2Lag = peakLag * 2
        var harmonicBonus: Float = 0
        if harmonic2Lag < autocorr.count - 1 {
            let harmonicValue = autocorr[harmonic2Lag]
            if harmonicValue > localMean * 1.5 {
                harmonicBonus = 0.1
            }
        }

        // Peak sharpness: difference from neighbors
        var sharpness: Float = 0
        if peakLag > 2 && peakLag < autocorr.count - 3 {
            let leftDiff = peakValue - autocorr[peakLag - 2]
            let rightDiff = peakValue - autocorr[peakLag + 2]
            sharpness = min(leftDiff, rightDiff) / max(peakValue, 0.01)
        }

        // Combine factors
        var confidence = min(1.0, (peakRatio - 1.0) / 5.0) * 0.5
        confidence += sharpness * 0.3
        confidence += harmonicBonus
        confidence += peakValue * 0.1

        return min(1.0, max(0.0, confidence))
    }

    // MARK: - Beat Offset Detection

    private func findBeatOffset(
        onsets: [Float],
        bpm: Double,
        hopRate: Double,
        options: DJAnalysisOptions
    ) -> Double {
        guard bpm > 0, hopRate > 0 else { return 0 }

        let beatPeriodFrames = hopRate * 60.0 / bpm
        let searchFrames = Int(beatPeriodFrames) + 1

        guard searchFrames > 0, searchFrames <= onsets.count else { return 0 }

        // Find the strongest onset within the first beat period
        var maxOnset: Float = 0
        var maxIndex = 0

        for i in 0..<searchFrames {
            if onsets[i] > maxOnset {
                maxOnset = onsets[i]
                maxIndex = i
            }
        }

        // Convert frame index to seconds
        let offsetSeconds = Double(maxIndex) / hopRate

        return offsetSeconds
    }
}

// MARK: - Errors

/// Errors that can occur during audio analysis.
public enum DJAnalysisError: Error, LocalizedError {
    case fileNotFound(URL)
    case formatConversionFailed
    case bufferAllocationFailed
    case conversionError(String)
    case insufficientData

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Audio file not found: \(url.path)"
        case .formatConversionFailed:
            return "Failed to create target audio format"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .conversionError(let message):
            return "Audio conversion error: \(message)"
        case .insufficientData:
            return "Insufficient audio data for analysis"
        }
    }
}
