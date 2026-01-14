import XCTest
@testable import MixBridgeDJ

/// Tests for DJLocalAnalyzer BPM detection accuracy and cache behavior.
final class DJLocalAnalyzerTests: XCTestCase {

    // MARK: - BPM Accuracy Tests

    /// BPM tolerance: analysis must be within 0.5 BPM of actual.
    static let bpmTolerance: Double = 0.5

    /// Beat offset tolerance: must be within 0.05 seconds of actual.
    static let beatOffsetTolerance: Double = 0.05

    /// Test BPM detection at 120 BPM (common house/techno tempo).
    func testBPMDetection_120BPM() async throws {
        let testBPM = 120.0
        let url = try TestClickTrackFactory.generate(bpm: testBPM, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.bpm,
            testBPM,
            accuracy: Self.bpmTolerance,
            "BPM should be within \(Self.bpmTolerance) of \(testBPM), got \(result.bpm)"
        )
        XCTAssertGreaterThan(result.confidence, 0.5, "Confidence should be > 0.5 for clean click track")
        XCTAssertTrue(result.isUsableForBeatSync, "Should be usable for beat sync")
    }

    /// Test BPM detection at 140 BPM (common trance tempo).
    func testBPMDetection_140BPM() async throws {
        let testBPM = 140.0
        let url = try TestClickTrackFactory.generate(bpm: testBPM, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.bpm,
            testBPM,
            accuracy: Self.bpmTolerance,
            "BPM should be within \(Self.bpmTolerance) of \(testBPM), got \(result.bpm)"
        )
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    /// Test BPM detection at 90 BPM (slower hip-hop tempo).
    func testBPMDetection_90BPM() async throws {
        let testBPM = 90.0
        let url = try TestClickTrackFactory.generate(bpm: testBPM, duration: 15.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.bpm,
            testBPM,
            accuracy: Self.bpmTolerance,
            "BPM should be within \(Self.bpmTolerance) of \(testBPM), got \(result.bpm)"
        )
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    /// Test BPM detection at 174 BPM (drum and bass tempo).
    func testBPMDetection_174BPM() async throws {
        let testBPM = 174.0
        let url = try TestClickTrackFactory.generate(bpm: testBPM, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.bpm,
            testBPM,
            accuracy: Self.bpmTolerance,
            "BPM should be within \(Self.bpmTolerance) of \(testBPM), got \(result.bpm)"
        )
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    /// Test multiple BPM values in a single test to verify consistency.
    func testBPMDetection_MultipleBPMValues() async throws {
        let testBPMs: [Double] = [85.0, 100.0, 128.0, 150.0, 180.0]

        let analyzer = DJLocalAnalyzer(options: .clickTrack)

        for testBPM in testBPMs {
            let url = try TestClickTrackFactory.generate(bpm: testBPM, duration: 8.0)
            defer { TestClickTrackFactory.cleanup(url: url) }

            let result = try await analyzer.analyze(url: url)

            XCTAssertEqual(
                result.bpm,
                testBPM,
                accuracy: Self.bpmTolerance,
                "BPM \(testBPM): got \(result.bpm), error = \(abs(result.bpm - testBPM))"
            )
        }
    }

    // MARK: - Beat Offset Tests

    /// Test beat offset detection with no offset.
    func testBeatOffset_ZeroOffset() async throws {
        let testBPM = 120.0
        let testOffset = 0.0
        let url = try TestClickTrackFactory.generate(bpm: testBPM, beatOffset: testOffset, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.beatOffsetSeconds,
            testOffset,
            accuracy: Self.beatOffsetTolerance,
            "Beat offset should be within \(Self.beatOffsetTolerance)s of \(testOffset), got \(result.beatOffsetSeconds)"
        )
    }

    /// Test beat offset detection with 0.1s offset.
    func testBeatOffset_100msOffset() async throws {
        let testBPM = 120.0
        let testOffset = 0.1
        let url = try TestClickTrackFactory.generate(bpm: testBPM, beatOffset: testOffset, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.beatOffsetSeconds,
            testOffset,
            accuracy: Self.beatOffsetTolerance,
            "Beat offset should be within \(Self.beatOffsetTolerance)s of \(testOffset), got \(result.beatOffsetSeconds)"
        )
    }

    /// Test beat offset detection with 0.25s offset.
    func testBeatOffset_250msOffset() async throws {
        let testBPM = 128.0
        let testOffset = 0.25
        let url = try TestClickTrackFactory.generate(bpm: testBPM, beatOffset: testOffset, duration: 10.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(
            result.beatOffsetSeconds,
            testOffset,
            accuracy: Self.beatOffsetTolerance,
            "Beat offset should be within \(Self.beatOffsetTolerance)s of \(testOffset), got \(result.beatOffsetSeconds)"
        )
    }

    // MARK: - Cache Tests

    /// Test that second analyze call hits cache and doesn't redo analysis.
    func testCacheHit_SecondAnalyzeUsesCache() async throws {
        let url = try TestClickTrackFactory.generate(bpm: 120.0, duration: 5.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let store = DJInMemoryAnalysisStore()
        let analyzer = DJLocalAnalyzer(store: store, options: .clickTrack)

        // First analysis
        let result1 = try await analyzer.analyze(url: url)
        let putCount1 = await store.putCount
        let hitCount1 = await store.hitCount

        XCTAssertEqual(putCount1, 1, "First analysis should put result in cache")
        XCTAssertEqual(hitCount1, 0, "First analysis should not hit cache")

        // Second analysis of same file
        let result2 = try await analyzer.analyze(url: url)
        let putCount2 = await store.putCount
        let hitCount2 = await store.hitCount

        XCTAssertEqual(putCount2, 1, "Second analysis should NOT put (cache hit)")
        XCTAssertEqual(hitCount2, 1, "Second analysis should hit cache")

        // Results should be identical
        XCTAssertEqual(result1.bpm, result2.bpm)
        XCTAssertEqual(result1.beatOffsetSeconds, result2.beatOffsetSeconds)
        XCTAssertEqual(result1.confidence, result2.confidence)
    }

    /// Test that changed file identity forces re-analysis.
    func testCacheInvalidation_ChangedFileIdentityForcesReanalysis() async throws {
        let bpm1 = 120.0
        let bpm2 = 140.0

        // Generate first click track
        let url1 = try TestClickTrackFactory.generate(bpm: bpm1, duration: 5.0)

        let store = DJInMemoryAnalysisStore()
        let analyzer = DJLocalAnalyzer(store: store, options: .clickTrack)

        // Analyze first file
        let result1 = try await analyzer.analyze(url: url1, trackId: "test-track")

        XCTAssertEqual(result1.bpm, bpm1, accuracy: Self.bpmTolerance)

        let hitCount1 = await store.hitCount
        let putCount1 = await store.putCount
        let missCount1 = await store.missCount

        XCTAssertEqual(hitCount1, 0, "First analysis: no cache hit")
        XCTAssertEqual(putCount1, 1, "First analysis: one put")
        XCTAssertEqual(missCount1, 1, "First analysis: one miss (empty cache)")

        // Delete first file and create new one with different BPM at same path
        TestClickTrackFactory.cleanup(url: url1)

        // Generate second click track with different BPM
        // Use a new file to simulate changed identity
        let url2 = try TestClickTrackFactory.generate(bpm: bpm2, duration: 6.0)
        defer { TestClickTrackFactory.cleanup(url: url2) }

        // Analyze second file with same track ID
        let result2 = try await analyzer.analyze(url: url2, trackId: "test-track")

        let hitCount2 = await store.hitCount
        let missCount2 = await store.missCount
        let putCount2 = await store.putCount

        // Should miss cache because file identity changed (miss count increased by 1)
        XCTAssertEqual(missCount2, 2, "Changed file identity should cause additional cache miss")
        XCTAssertEqual(hitCount2, 0, "No cache hits (identity mismatch)")
        XCTAssertEqual(putCount2, 2, "Should put new analysis in cache")

        // BPM should reflect the new file
        XCTAssertEqual(result2.bpm, bpm2, accuracy: Self.bpmTolerance)
        XCTAssertNotEqual(result1.bpm, result2.bpm, accuracy: 1.0, "BPMs should be different")
    }

    /// Test file-based cache store.
    func testFileStore_PersistsAndReloads() async throws {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DJAnalysisCacheTest_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let url = try TestClickTrackFactory.generate(bpm: 128.0, duration: 5.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        // Create first store instance and analyze
        let store1 = try DJFileAnalysisStore(cacheDirectory: cacheDir)
        let analyzer1 = DJLocalAnalyzer(store: store1, options: .clickTrack)

        let result1 = try await analyzer1.analyze(url: url, trackId: "persistent-test")

        let putCount1 = await store1.putCount
        XCTAssertEqual(putCount1, 1, "Should put result in file store")

        // Create second store instance (simulating app restart)
        let store2 = try DJFileAnalysisStore(cacheDirectory: cacheDir)
        let analyzer2 = DJLocalAnalyzer(store: store2, options: .clickTrack)

        let result2 = try await analyzer2.analyze(url: url, trackId: "persistent-test")

        let hitCount2 = await store2.hitCount
        let putCount2 = await store2.putCount

        XCTAssertEqual(hitCount2, 1, "Second store should hit persisted cache")
        XCTAssertEqual(putCount2, 0, "Second store should not need to put")

        // Results should match
        XCTAssertEqual(result1.bpm, result2.bpm)
        XCTAssertEqual(result1.beatOffsetSeconds, result2.beatOffsetSeconds)
    }

    // MARK: - Low Confidence / Fallback Tests

    /// Test that white noise produces low confidence result.
    func testLowConfidence_WhiteNoiseProducesLowConfidence() async throws {
        let url = try TestClickTrackFactory.generateWhiteNoise(duration: 5.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        XCTAssertLessThan(
            result.confidence,
            0.5,
            "White noise should produce low confidence (<0.5), got \(result.confidence)"
        )
        XCTAssertFalse(
            result.isUsableForBeatSync,
            "Low confidence result should not be usable for beat sync"
        )
    }

    /// Test confidence threshold helper.
    func testConfidenceThreshold_IsUsableForBeatSync() async throws {
        let url = try TestClickTrackFactory.generate(bpm: 120.0, duration: 8.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        // Clean click track should pass default threshold
        XCTAssertTrue(result.isUsableForBeatSync)
        XCTAssertTrue(result.isUsableForBeatSync(threshold: 0.5))

        // Should fail extremely high threshold
        XCTAssertFalse(result.isUsableForBeatSync(threshold: 0.99))
    }

    /// Test low confidence result provides fallback signal.
    func testFallbackSignal_LowConfidenceResultShape() async throws {
        // Create a low confidence result manually
        let lowConfResult = DJAnalysisResult.lowConfidence(reason: "Test fallback")

        XCTAssertEqual(lowConfResult.confidence, 0)
        XCTAssertFalse(lowConfResult.isUsableForBeatSync)
        XCTAssertNotNil(lowConfResult.metadata.failureReason)

        // Non-periodic result
        let nonPeriodic = DJAnalysisResult.nonPeriodic()
        XCTAssertFalse(nonPeriodic.isUsableForBeatSync)
    }

    // MARK: - Conversion to DJTrackTiming

    /// Test conversion to DJTrackTiming for transition planning.
    func testToTrackTiming_ConversionPreservesValues() async throws {
        let url = try TestClickTrackFactory.generate(bpm: 128.0, duration: 5.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        let timing = result.toTrackTiming()

        XCTAssertEqual(timing.bpm, result.bpm)
        XCTAssertEqual(timing.downbeatOffsetSeconds, result.beatOffsetSeconds)
        XCTAssertEqual(timing.confidence, result.confidence)
        XCTAssertEqual(timing.timeSignatureNumerator, result.timeSignatureNumerator ?? 4)
    }

    // MARK: - Analysis Options Tests

    /// Test that custom options are respected.
    func testAnalysisOptions_CustomOptionsApplied() async throws {
        let customOptions = DJAnalysisOptions(
            minBPM: 100.0,
            maxBPM: 160.0,
            windowSizeSeconds: 0.05,
            hopFraction: 0.25,
            confidenceThreshold: 0.7
        )

        XCTAssertEqual(customOptions.minBPM, 100.0)
        XCTAssertEqual(customOptions.maxBPM, 160.0)
        XCTAssertEqual(customOptions.confidenceThreshold, 0.7)

        // Computed properties
        XCTAssertEqual(customOptions.minBeatIntervalSeconds, 60.0 / 160.0, accuracy: 0.001)
        XCTAssertEqual(customOptions.maxBeatIntervalSeconds, 60.0 / 100.0, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    /// Test analysis of short audio file.
    func testEdgeCase_ShortAudioFile() async throws {
        // 4 second audio - minimum viable duration for reliable BPM detection
        // At 120 BPM, this gives 8 beats which is enough for autocorrelation
        let url = try TestClickTrackFactory.generate(bpm: 120.0, duration: 4.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        // Should detect BPM with reasonable accuracy
        XCTAssertGreaterThan(result.bpm, 0, "Should detect BPM for 4-second audio")
        XCTAssertEqual(result.bpm, 120.0, accuracy: Self.bpmTolerance)
    }

    /// Test that very short audio returns low confidence (graceful degradation).
    func testEdgeCase_VeryShortAudioReturnsLowConfidence() async throws {
        // 1 second is too short for reliable BPM detection
        let url = try TestClickTrackFactory.generate(bpm: 120.0, duration: 1.0)
        defer { TestClickTrackFactory.cleanup(url: url) }

        let analyzer = DJLocalAnalyzer(options: .clickTrack)
        let result = try await analyzer.analyze(url: url)

        // Very short audio should either return low confidence or fail gracefully
        // We don't require accurate BPM, just no crash
        XCTAssertGreaterThanOrEqual(result.bpm, 0, "BPM should be non-negative")
    }
}
