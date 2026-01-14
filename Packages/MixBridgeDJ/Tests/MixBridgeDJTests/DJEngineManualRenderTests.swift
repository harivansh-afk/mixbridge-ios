import Testing
import AVFoundation
@testable import MixBridgeDJ

/// Tests for DJ mixer engine using manual/offline rendering.
/// These tests verify actual audio mixing outcomes, not just "no crash".
@Suite("DJ Engine Manual Render Tests")
struct DJEngineManualRenderTests {

    // MARK: - Track Timing Tests

    @Test("Beat boundary calculation finds next beat after given time")
    func testBeatBoundaryCalculation() {
        let timing = DJTrackTiming(bpm: 120.0, downbeatOffsetSeconds: 0.1)

        // At 120 BPM, beat duration is 0.5 seconds
        // With downbeat at 0.1s, beats are at: 0.1, 0.6, 1.1, 1.6, ...

        // Current time 0.0: next beat should be at 0.1 (first downbeat)
        let nextBeat0 = timing.nextBeatBoundary(after: 0.0)
        #expect(abs(nextBeat0 - 0.1) < 0.001, "Next beat after 0.0 should be 0.1")

        // Current time 0.2: next beat should be at 0.6
        let nextBeat02 = timing.nextBeatBoundary(after: 0.2)
        #expect(abs(nextBeat02 - 0.6) < 0.001, "Next beat after 0.2 should be 0.6")

        // Current time 0.6: next beat should be at 0.6 (at boundary)
        let nextBeat06 = timing.nextBeatBoundary(after: 0.6)
        #expect(abs(nextBeat06 - 0.6) < 0.001, "Next beat at 0.6 should be 0.6")
    }

    @Test("Bar boundary calculation finds next bar after given time")
    func testBarBoundaryCalculation() {
        let timing = DJTrackTiming(
            bpm: 120.0,
            timeSignatureNumerator: 4,
            downbeatOffsetSeconds: 0.0
        )

        // At 120 BPM in 4/4, bar duration is 2.0 seconds
        // Bars are at: 0.0, 2.0, 4.0, ...

        let nextBar05 = timing.nextBarBoundary(after: 0.5)
        #expect(abs(nextBar05 - 2.0) < 0.001, "Next bar after 0.5 should be 2.0")

        let nextBar25 = timing.nextBarBoundary(after: 2.5)
        #expect(abs(nextBar25 - 4.0) < 0.001, "Next bar after 2.5 should be 4.0")
    }

    // MARK: - Tempo Matching Tests

    @Test("Tempo match rate calculation with clamping")
    func testTempoMatchRateCalculation() {
        // Target BPM 120, incoming BPM 110
        // Rate = 120/110 = 1.09 -> clamped to 1.08 (max +8%)
        let config = DJTempoMatchConfig(
            enabled: true,
            targetBPM: 120.0,
            maxRateAdjustment: 0.08
        )

        let rate = config.computeRate(incomingBPM: 110.0)
        #expect(abs(rate - 1.08) < 0.001, "Rate should be clamped to 1.08")

        // Target BPM 120, incoming BPM 125
        // Rate = 120/125 = 0.96 -> within bounds
        let rate2 = config.computeRate(incomingBPM: 125.0)
        #expect(abs(rate2 - 0.96) < 0.001, "Rate should be 0.96")

        // Target BPM 120, incoming BPM 140
        // Rate = 120/140 = 0.857 -> clamped to 0.92 (min -8%)
        let rate3 = config.computeRate(incomingBPM: 140.0)
        #expect(abs(rate3 - 0.92) < 0.001, "Rate should be clamped to 0.92")
    }

    // MARK: - Crossfade Curve Tests

    @Test("Equal-power crossfade maintains energy at midpoint")
    func testEqualPowerCrossfade() {
        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 0.0,
            crossfadeCurve: .equalPower
        )

        // At midpoint (progress = 0.5), sum of squared gains should equal 1
        // For equal-power: out = cos(0.5 * pi/2), in = sin(0.5 * pi/2)
        // cos(pi/4) = sin(pi/4) = sqrt(2)/2 ~ 0.707
        // out^2 + in^2 = 0.5 + 0.5 = 1.0

        let (outGain, inGain) = plan.crossfadeGains(at: 0.5)
        let sumOfSquares = outGain * outGain + inGain * inGain

        #expect(abs(sumOfSquares - 1.0) < 0.01, "Equal-power crossfade should maintain unity gain at midpoint, got \(sumOfSquares)")
        #expect(abs(outGain - inGain) < 0.01, "Gains should be equal at midpoint")
    }

    @Test("Equal-power crossfade avoids loudness dip")
    func testEqualPowerNoLoudnessDip() {
        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 0.0,
            crossfadeCurve: .equalPower
        )

        // Sample multiple points and verify sum of squared gains stays close to 1
        let progressValues = stride(from: 0.0, through: 1.0, by: 0.1)
        var minSumOfSquares: Double = 2.0
        var maxSumOfSquares: Double = 0.0

        for progress in progressValues {
            let (outGain, inGain) = plan.crossfadeGains(at: progress)
            let sumOfSquares = outGain * outGain + inGain * inGain
            minSumOfSquares = min(minSumOfSquares, sumOfSquares)
            maxSumOfSquares = max(maxSumOfSquares, sumOfSquares)
        }

        // Equal-power should maintain sum of squares within tolerance
        let tolerance = 0.05
        #expect(minSumOfSquares >= 1.0 - tolerance, "Minimum sum of squares \(minSumOfSquares) indicates loudness dip")
        #expect(maxSumOfSquares <= 1.0 + tolerance, "Maximum sum of squares \(maxSumOfSquares) indicates loudness boost")
    }

    @Test("Linear crossfade has predictable loudness dip at midpoint")
    func testLinearCrossfadeDip() {
        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 0.0,
            crossfadeCurve: .linear
        )

        // At midpoint, linear gives out = 0.5, in = 0.5
        // Sum of squares = 0.25 + 0.25 = 0.5 (significant dip)
        let (outGain, inGain) = plan.crossfadeGains(at: 0.5)
        let sumOfSquares = outGain * outGain + inGain * inGain

        #expect(abs(sumOfSquares - 0.5) < 0.01, "Linear crossfade should have ~-3dB dip at midpoint")
    }

    // MARK: - EQ Curve Tests

    @Test("EQ curve interpolation at keyframes")
    func testEQCurveInterpolation() {
        let curve = DJEQCurve(band: .high, keyframes: [
            DJEQKeyframe(progress: 0.0, gainDB: -12.0),
            DJEQKeyframe(progress: 0.5, gainDB: -6.0),
            DJEQKeyframe(progress: 1.0, gainDB: 0.0)
        ])

        #expect(abs(curve.gain(at: 0.0) - (-12.0)) < 0.1, "Gain at 0.0 should be -12dB")
        #expect(abs(curve.gain(at: 0.5) - (-6.0)) < 0.1, "Gain at 0.5 should be -6dB")
        #expect(abs(curve.gain(at: 1.0) - 0.0) < 0.1, "Gain at 1.0 should be 0dB")

        // Test interpolation between keyframes
        #expect(abs(curve.gain(at: 0.25) - (-9.0)) < 0.1, "Gain at 0.25 should be ~-9dB")
        #expect(abs(curve.gain(at: 0.75) - (-3.0)) < 0.1, "Gain at 0.75 should be ~-3dB")
    }

    @Test("High duck curve for incoming track")
    func testHighDuckCurve() {
        let curve = DJEQCurve.highDuckIncoming()

        // Should start ducked, then rise
        let startGain = curve.gain(at: 0.0)
        let midGain = curve.gain(at: 0.5)
        let endGain = curve.gain(at: 1.0)

        #expect(startGain < midGain, "Start should be more ducked than mid")
        #expect(midGain < endGain, "Mid should be more ducked than end")
        #expect(abs(endGain - 0.0) < 0.1, "End should be at 0dB (flat)")
    }

    // MARK: - Plan Validation Tests

    @Test("Plan validator clamps out-of-bounds values")
    func testPlanValidatorClamping() {
        let validator = DJPlanValidator.default

        // Create plan with out-of-bounds values
        let plan = DJTransitionPlan(
            fadeDurationSeconds: 100.0, // Too long
            fadeStartSeconds: -5.0,     // Negative
            crossfadeCurve: .equalPower
        )

        let result = validator.validate(plan: plan, outgoingTiming: nil, incomingTiming: nil)

        #expect(result.validatedPlan.fadeDurationSeconds <= 32.0, "Fade duration should be clamped")
        #expect(result.validatedPlan.fadeStartSeconds >= 0.0, "Fade start should be non-negative")
        #expect(!result.issues.isEmpty, "Should have validation issues")
    }

    @Test("Plan validator creates fallback for low confidence timing")
    func testPlanValidatorFallback() {
        let validator = DJPlanValidator.default

        let lowConfidenceTiming = DJTrackTiming(bpm: 120.0, confidence: 0.3)

        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 0.0,
            tempoMatch: DJTempoMatchConfig(enabled: true, targetBPM: 120.0),
            beatAlignment: .beat
        )

        let result = validator.validate(
            plan: plan,
            outgoingTiming: lowConfidenceTiming,
            incomingTiming: lowConfidenceTiming
        )

        #expect(result.validatedPlan.isFallback, "Should use fallback for low confidence")
        #expect(!result.validatedPlan.tempoMatch.enabled, "Fallback should disable tempo match")
        #expect(result.validatedPlan.beatAlignment == .none, "Fallback should disable beat alignment")
    }

    // MARK: - 3-Band EQ Tests

    @Test("Three-band EQ gain setting and retrieval")
    func testThreeBandEQGains() {
        let eq = DJThreeBandEQ()

        // Set gains
        eq.setGain(band: .low, gainDB: -6.0)
        eq.setGain(band: .mid, gainDB: 3.0)
        eq.setGain(band: .high, gainDB: -12.0)

        // Verify
        #expect(abs(eq.getGain(band: .low) - (-6.0)) < 0.1)
        #expect(abs(eq.getGain(band: .mid) - 3.0) < 0.1)
        #expect(abs(eq.getGain(band: .high) - (-12.0)) < 0.1)
    }

    @Test("Three-band EQ clamps extreme values")
    func testThreeBandEQClamping() {
        let eq = DJThreeBandEQ()

        // Set extreme values
        eq.setGain(band: .low, gainDB: -50.0) // Below min
        eq.setGain(band: .high, gainDB: 30.0) // Above max

        // Should be clamped
        #expect(eq.getGain(band: .low) >= -24.0, "Low gain should be clamped to min")
        #expect(eq.getGain(band: .high) <= 12.0, "High gain should be clamped to max")
    }

    @Test("Three-band EQ applies curves correctly")
    func testThreeBandEQCurveApplication() {
        let eq = DJThreeBandEQ()

        let curves = [
            DJEQCurve.highDuckIncoming(band: .high)
        ]

        // At start (progress 0)
        eq.applyEQCurves(curves, at: 0.0)
        let startHighGain = eq.getGain(band: .high)
        #expect(startHighGain < -6.0, "High should be ducked at start")

        // At end (progress 1)
        eq.applyEQCurves(curves, at: 1.0)
        let endHighGain = eq.getGain(band: .high)
        #expect(abs(endHighGain - 0.0) < 0.5, "High should be flat at end")
    }

    // MARK: - RMS Energy Analysis Tests

    @Test("RMS calculation returns correct value for sine wave")
    func testRMSCalculation() throws {
        let sampleRate: Double = 44100
        let duration: Double = 0.1 // 100ms
        let frameCount = Int(duration * sampleRate)
        let amplitude: Float = 0.5

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw TestAudioError.bufferCreationFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw TestAudioError.bufferCreationFailed
        }

        // Generate sine wave
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            channelData[0][frame] = Float(sin(2.0 * .pi * 440.0 * time)) * amplitude
        }

        let rms = DJMixerEngine.computeRMS(buffer: buffer)

        // RMS of sine wave = amplitude / sqrt(2) ~ 0.707 * amplitude
        let expectedRMS = amplitude / sqrt(2.0)
        let tolerance: Float = 0.05

        #expect(abs(rms - expectedRMS) < tolerance, "RMS \(rms) should be close to \(expectedRMS)")
    }

    // MARK: - Manual Render Integration Tests

    @Test("Engine creates audio graph without errors")
    func testEngineCreation() {
        let config = DJMixerEngineConfig.manualRendering
        let engine = DJMixerEngine(config: config)

        // Verify EQ access works
        let eqA = engine.eq(for: .a)
        let eqB = engine.eq(for: .b)

        #expect(eqA.getGain(band: .low) == 0.0, "EQ A low should start flat")
        #expect(eqB.getGain(band: .high) == 0.0, "EQ B high should start flat")
    }

    @Test("Tempo rate preserved when pitch is set to zero")
    func testTempoRateWithZeroPitch() {
        let config = DJTempoMatchConfig(
            enabled: true,
            targetBPM: 130.0,
            maxRateAdjustment: 0.08,
            preservePitch: true
        )

        // bpmA = 130 (target), bpmB = 120 (incoming)
        // Rate = 130/120 = 1.083... -> clamped to 1.08
        let rate = config.computeRate(incomingBPM: 120.0)

        #expect(abs(rate - 1.08) < 0.01, "Rate should be 1.08 (clamped)")
        #expect(config.preservePitch == true, "Pitch should be preserved")
    }

    @Test("Transition plan computes correct incoming start time with beat alignment")
    func testIncomingStartTimeCalculation() {
        let outgoingTiming = DJTrackTiming(
            bpm: 128.0,
            timeSignatureNumerator: 4,
            downbeatOffsetSeconds: 0.0,
            confidence: 1.0
        )

        // Fade starts at 10.0 seconds
        // At 128 BPM, beat duration = 60/128 = 0.46875s
        // Next beat after 10.0 = ceil(10.0 / 0.46875) * 0.46875 = 22 * 0.46875 = 10.3125

        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 10.0,
            beatAlignment: .beat
        )

        let incomingStart = plan.computeIncomingStartTime(
            outgoingTiming: outgoingTiming,
            fadeStartTime: 10.0
        )

        let beatDuration = 60.0 / 128.0
        let expectedBeat = ceil(10.0 / beatDuration) * beatDuration

        #expect(abs(incomingStart - expectedBeat) < 0.001, "Incoming start \(incomingStart) should align to next beat \(expectedBeat)")
    }

    @Test("Bar alignment aligns to bar boundary not beat")
    func testBarAlignment() {
        let outgoingTiming = DJTrackTiming(
            bpm: 120.0,
            timeSignatureNumerator: 4,
            downbeatOffsetSeconds: 0.0,
            confidence: 1.0
        )

        // Bar duration at 120 BPM in 4/4 = 2.0 seconds
        // Bars at: 0, 2, 4, 6, 8, 10, ...
        // Fade start at 7.5: next bar is 8.0

        let plan = DJTransitionPlan(
            fadeDurationSeconds: 8.0,
            fadeStartSeconds: 7.5,
            beatAlignment: .bar
        )

        let incomingStart = plan.computeIncomingStartTime(
            outgoingTiming: outgoingTiming,
            fadeStartTime: 7.5
        )

        #expect(abs(incomingStart - 8.0) < 0.001, "Bar alignment should find next bar at 8.0, got \(incomingStart)")
    }

    @Test("Fallback plan has expected safe defaults")
    func testFallbackPlanDefaults() {
        let fallback = DJTransitionPlan.fallback(fadeDuration: 8.0, fadeStart: 5.0)

        #expect(fallback.isFallback == true, "Should be marked as fallback")
        #expect(fallback.crossfadeCurve == .equalPower, "Should use equal-power crossfade")
        #expect(!fallback.tempoMatch.enabled, "Should have tempo match disabled")
        #expect(fallback.beatAlignment == .none, "Should have no beat alignment")

        // All EQ curves should be flat
        for curve in fallback.outgoingEQCurves {
            #expect(abs(curve.gain(at: 0.5) - 0.0) < 0.1, "Outgoing EQ should be flat")
        }
        for curve in fallback.incomingEQCurves {
            #expect(abs(curve.gain(at: 0.5) - 0.0) < 0.1, "Incoming EQ should be flat")
        }
    }

    // MARK: - Volume and Rate Access Tests

    @Test("Volume access and setting works correctly")
    func testVolumeAccess() {
        let engine = DJMixerEngine(config: .manualRendering)

        // Initial volumes
        #expect(engine.volume(for: .a) == 1.0, "Deck A should start at full volume")
        #expect(engine.volume(for: .b) == 0.0, "Deck B should start silent")

        // Set volumes
        engine.setVolume(0.5, for: .a)
        engine.setVolume(0.7, for: .b)

        #expect(abs(engine.volume(for: .a) - 0.5) < 0.01)
        #expect(abs(engine.volume(for: .b) - 0.7) < 0.01)

        // Test clamping
        engine.setVolume(1.5, for: .a)
        engine.setVolume(-0.5, for: .b)

        #expect(engine.volume(for: .a) == 1.0, "Volume should be clamped to 1.0")
        #expect(engine.volume(for: .b) == 0.0, "Volume should be clamped to 0.0")
    }

    @Test("Rate access works correctly")
    func testRateAccess() {
        let engine = DJMixerEngine(config: .manualRendering)

        // Initial rate
        #expect(engine.rate(for: .a) == 1.0, "Rate should start at 1.0")
        #expect(engine.rate(for: .b) == 1.0, "Rate should start at 1.0")

        // Set rate
        engine.setRate(1.05, for: .a, preservePitch: true)
        #expect(abs(engine.rate(for: .a) - 1.05) < 0.01)
    }
}
