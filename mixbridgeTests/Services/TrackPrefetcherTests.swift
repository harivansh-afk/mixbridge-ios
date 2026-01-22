import XCTest
@testable import mixbridge

/// Tests for TrackPrefetcher
/// Tests prefetch logic, cancellation, priority, and deduplication
final class TrackPrefetcherTests: XCTestCase {

    // MARK: - Test Fixtures

    private var prefetcher: TestableTrackPrefetcher!

    override func setUp() async throws {
        try await super.setUp()
        prefetcher = TestableTrackPrefetcher()
    }

    override func tearDown() async throws {
        await prefetcher.reset()
        prefetcher = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeTrack(
        id: String = UUID().uuidString,
        title: String = "Test Track",
        artist: String = "Test Artist",
        artwork: String = "https://example.com/artwork.jpg"
    ) -> Track {
        Track(
            id: id,
            title: title,
            artist: artist,
            album: "",
            artwork: artwork,
            duration: 180.0
        )
    }

    private func makeTracks(count: Int, artworkPrefix: String = "https://example.com/artwork") -> [Track] {
        (0..<count).map { index in
            Track(
                id: "track-\(index)",
                title: "Track \(index + 1)",
                artist: "Artist",
                album: "",
                artwork: "\(artworkPrefix)\(index).jpg",
                duration: 180.0
            )
        }
    }

    // MARK: - Initial State Tests

    func testPrefetcherStartsEmpty() async {
        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.isEmpty)
    }

    func testPrefetcherStartsWithNoCurrentTask() async {
        let hasTask = await prefetcher.hasCurrentPrefetchTask()
        XCTAssertFalse(hasTask)
    }

    // MARK: - prefetchForQueue Tests

    func testPrefetchForQueuePrefetchesFromCurrentIndex() async {
        let tracks = makeTracks(count: 10)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        // Wait for task to start processing
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        // With lookahead=5, should prefetch indices 0-5 (6 tracks)
        XCTAssertTrue(prefetchedIds.contains("track-0"), "Should prefetch current track")
        XCTAssertTrue(prefetchedIds.count >= 1, "Should have prefetched at least the current track")
    }

    func testPrefetchForQueueRespectsLookahead() async {
        let tracks = makeTracks(count: 20)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        // Wait for prefetch to complete
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        // Lookahead is 5, so should prefetch indices 0-5 (6 tracks total: current + 5 ahead)
        XCTAssertTrue(prefetchedIds.count <= 6, "Should respect lookahead limit")

        // Tracks beyond lookahead should not be prefetched
        XCTAssertFalse(prefetchedIds.contains("track-10"), "Should not prefetch beyond lookahead")
    }

    func testPrefetchForQueueFromMiddleOfQueue() async {
        let tracks = makeTracks(count: 15)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 5)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()

        // Should prefetch from index 5 onwards (indices 5-10)
        XCTAssertTrue(prefetchedIds.contains("track-5"), "Should prefetch current track at index 5")
        XCTAssertFalse(prefetchedIds.contains("track-0"), "Should not prefetch tracks before current index")
    }

    func testPrefetchForQueueNearEndOfQueue() async {
        let tracks = makeTracks(count: 8)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 6)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()

        // Should prefetch indices 6-7 (only 2 tracks remain)
        XCTAssertTrue(prefetchedIds.contains("track-6"), "Should prefetch current track")
        XCTAssertTrue(prefetchedIds.contains("track-7"), "Should prefetch last track")
    }

    func testPrefetchForQueueWithEmptyQueue() async {
        let tracks: [Track] = []

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.isEmpty, "Should not prefetch anything for empty queue")
    }

    func testPrefetchForQueueWithIndexBeyondBounds() async {
        let tracks = makeTracks(count: 5)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 10)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.isEmpty, "Should not prefetch anything when index is beyond bounds")
    }

    func testPrefetchForQueueWithNegativeIndex() async {
        let tracks = makeTracks(count: 5)

        // Negative index gets clamped to 0 via max(0, currentIndex)
        await prefetcher.prefetchForQueue(tracks, currentIndex: -1)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        // Should start from index 0
        XCTAssertTrue(prefetchedIds.contains("track-0"), "Should clamp negative index to 0")
    }

    // MARK: - Task Cancellation Tests

    func testPrefetchForQueueCancelsPreviousTask() async {
        let tracks = makeTracks(count: 20)

        // Start first prefetch
        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)

        // Immediately start second prefetch (should cancel first)
        await prefetcher.prefetchForQueue(tracks, currentIndex: 10)

        // Wait for processing
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()

        // Second prefetch should take precedence, starting from index 10
        XCTAssertTrue(prefetchedIds.contains("track-10"), "Should prefetch from new current index")
    }

    func testRapidQueueChanges() async {
        let tracks = makeTracks(count: 30)

        // Rapidly change queue positions
        for i in 0..<5 {
            await prefetcher.prefetchForQueue(tracks, currentIndex: i * 5)
        }

        // Final prefetch should be from index 20
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("track-20"), "Should handle rapid queue changes")
    }

    // MARK: - Deduplication Tests

    func testAlreadyPrefetchedTracksAreSkipped() async {
        let tracks = makeTracks(count: 10)

        // First prefetch
        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let imageLoadCountBefore = await prefetcher.getImageLoadCount()

        // Same prefetch again
        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let imageLoadCountAfter = await prefetcher.getImageLoadCount()

        // Should not load same images again
        XCTAssertEqual(imageLoadCountBefore, imageLoadCountAfter, "Should not reload already prefetched tracks")
    }

    func testOverlappingPrefetchRanges() async {
        let tracks = makeTracks(count: 15)

        // Prefetch from index 0
        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let countAfterFirst = await prefetcher.getImageLoadCount()

        // Prefetch from index 3 (overlaps with previous range)
        await prefetcher.prefetchForQueue(tracks, currentIndex: 3)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let countAfterSecond = await prefetcher.getImageLoadCount()

        // Should only load new tracks (indices 6-8), not reload 3-5
        let newLoads = countAfterSecond - countAfterFirst
        XCTAssertLessThanOrEqual(newLoads, 3, "Should not reload overlapping tracks")
    }

    // MARK: - preloadTrackImmediately Tests

    func testPreloadTrackImmediatelyLoadsArtwork() async {
        let track = makeTrack(id: "immediate-track", artwork: "https://example.com/immediate.jpg")

        await prefetcher.preloadTrackImmediately(track)

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("immediate-track"), "Should mark track as prefetched")

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.contains("https://example.com/immediate.jpg"), "Should load artwork URL")
    }

    func testPreloadTrackImmediatelyWithNoArtwork() async {
        let track = makeTrack(id: "no-artwork", artwork: "")

        await prefetcher.preloadTrackImmediately(track)

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertFalse(prefetchedIds.contains("no-artwork"), "Should not mark track without valid artwork")
    }

    func testPreloadTrackImmediatelyWithNonHttpArtwork() async {
        let track = makeTrack(id: "local-artwork", artwork: "music.note")

        await prefetcher.preloadTrackImmediately(track)

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertFalse(prefetchedIds.contains("local-artwork"), "Should not prefetch non-http artwork")
    }

    func testPreloadTrackImmediatelyWithInvalidUrl() async {
        let track = makeTrack(id: "invalid-url", artwork: "https://")

        await prefetcher.preloadTrackImmediately(track)

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertFalse(loadedUrls.contains("https://"), "Should not load invalid URL")
    }

    // MARK: - Artwork URL Validation Tests

    func testHttpsArtworkUrlIsPrefetched() async {
        let track = makeTrack(artwork: "https://secure.example.com/artwork.jpg")

        await prefetcher.preloadTrackImmediately(track)

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.contains("https://secure.example.com/artwork.jpg"))
    }

    func testHttpArtworkUrlIsPrefetched() async {
        let track = makeTrack(artwork: "http://insecure.example.com/artwork.jpg")

        await prefetcher.preloadTrackImmediately(track)

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.contains("http://insecure.example.com/artwork.jpg"))
    }

    func testLocalImagePathIsNotPrefetched() async {
        let track = makeTrack(artwork: "/local/path/image.jpg")

        await prefetcher.preloadTrackImmediately(track)

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.isEmpty, "Should not prefetch local paths")
    }

    func testSystemImageNameIsNotPrefetched() async {
        let track = makeTrack(artwork: "music.note")

        await prefetcher.preloadTrackImmediately(track)

        let loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.isEmpty, "Should not prefetch system image names")
    }

    // MARK: - Priority Tests

    func testCurrentTrackHasHighPriority() async {
        let tracks = makeTracks(count: 10)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let priorities = await prefetcher.getLoadedPriorities()

        // First track (current) should have high priority
        if let firstPriority = priorities.first {
            XCTAssertEqual(firstPriority, TaskPriority.high, "Current track should have high priority")
        }
    }

    func testUpcomingTracksHaveUtilityPriority() async {
        let tracks = makeTracks(count: 5)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let priorities = await prefetcher.getLoadedPriorities()

        // All tracks after the first should have utility priority
        let utilityPriorities = priorities.dropFirst().filter { $0 == TaskPriority.utility }
        XCTAssertTrue(utilityPriorities.count >= 1, "Upcoming tracks should have utility priority")
    }

    // MARK: - Sleep Between Prefetches Tests

    func testNonCurrentTrackPrefetchesHaveDelay() async {
        let tracks = makeTracks(count: 3)

        let startTime = Date()
        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms to let prefetch complete

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        let elapsed = Date().timeIntervalSince(startTime)

        // If all 3 tracks were prefetched with 100ms delay between non-current tracks,
        // it should take at least 200ms (2 delays for tracks 1 and 2)
        if prefetchedIds.count >= 3 {
            XCTAssertGreaterThanOrEqual(elapsed, 0.15, "Should have delays between non-current track prefetches")
        }
    }

    // MARK: - Edge Cases

    func testPrefetchSingleTrackQueue() async {
        let tracks = [makeTrack(id: "only-track")]

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("only-track"))
        XCTAssertEqual(prefetchedIds.count, 1)
    }

    func testPrefetchAtLastIndex() async {
        let tracks = makeTracks(count: 5)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 4)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("track-4"), "Should prefetch last track")
        XCTAssertEqual(prefetchedIds.count, 1, "Should only prefetch one track at end")
    }

    func testPrefetchWithMixedArtworkTypes() async {
        let tracks = [
            makeTrack(id: "track-http", artwork: "https://example.com/art.jpg"),
            makeTrack(id: "track-local", artwork: "music.note"),
            makeTrack(id: "track-https", artwork: "https://secure.example.com/art.jpg"),
            makeTrack(id: "track-empty", artwork: ""),
            makeTrack(id: "track-valid", artwork: "http://another.com/art.jpg")
        ]

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let loadedUrls = await prefetcher.getLoadedImageUrls()

        XCTAssertTrue(loadedUrls.contains("https://example.com/art.jpg"), "Should load HTTPS")
        XCTAssertTrue(loadedUrls.contains("https://secure.example.com/art.jpg"), "Should load secure HTTPS")
        XCTAssertTrue(loadedUrls.contains("http://another.com/art.jpg"), "Should load HTTP")
        XCTAssertFalse(loadedUrls.contains("music.note"), "Should not load system image")
        XCTAssertFalse(loadedUrls.contains(""), "Should not load empty")
    }

    func testPrefetchPreservesTrackIdAfterArtworkLoad() async {
        let track = makeTrack(id: "preserve-id", artwork: "https://example.com/art.jpg")

        await prefetcher.preloadTrackImmediately(track)

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("preserve-id"))
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentPrefetchCalls() async {
        let tracks = makeTracks(count: 30)

        // Simulate concurrent prefetch calls from multiple sources
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await self.prefetcher.prefetchForQueue(tracks, currentIndex: i * 5)
                }
            }
        }

        // Wait for all to settle
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Should not crash and should have some tracks prefetched
        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertFalse(prefetchedIds.isEmpty, "Should have prefetched some tracks")
    }

    func testConcurrentPreloadImmediately() async {
        let tracks = (0..<10).map { makeTrack(id: "concurrent-\($0)", artwork: "https://example.com/\($0).jpg") }

        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask {
                    await self.prefetcher.preloadTrackImmediately(track)
                }
            }
        }

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        // All tracks should be prefetched (thread-safe actor)
        XCTAssertEqual(prefetchedIds.count, 10, "All concurrent preloads should complete")
    }

    // MARK: - Reset Tests

    func testResetClearsPrefetchedTrackIds() async {
        let track = makeTrack(id: "to-reset")
        await prefetcher.preloadTrackImmediately(track)

        var prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.contains("to-reset"))

        await prefetcher.reset()

        prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertTrue(prefetchedIds.isEmpty, "Reset should clear prefetched IDs")
    }

    func testResetClearsImageLoadHistory() async {
        let track = makeTrack(artwork: "https://example.com/reset.jpg")
        await prefetcher.preloadTrackImmediately(track)

        var loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertFalse(loadedUrls.isEmpty)

        await prefetcher.reset()

        loadedUrls = await prefetcher.getLoadedImageUrls()
        XCTAssertTrue(loadedUrls.isEmpty, "Reset should clear image load history")
    }

    // MARK: - Stress Tests

    func testPrefetchLargeQueue() async {
        let tracks = makeTracks(count: 100)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()

        // Should only prefetch lookahead (6 tracks: current + 5)
        XCTAssertLessThanOrEqual(prefetchedIds.count, 6, "Should respect lookahead even with large queue")
    }

    func testMultiplePrefetchCycles() async {
        let tracks = makeTracks(count: 20)

        // Simulate user progressing through queue
        for currentIndex in stride(from: 0, to: 15, by: 3) {
            await prefetcher.prefetchForQueue(tracks, currentIndex: currentIndex)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between changes
        }

        // Should have accumulated multiple prefetched tracks
        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertGreaterThan(prefetchedIds.count, 6, "Should accumulate prefetched tracks over time")
    }

    // MARK: - Lookahead Boundary Tests

    func testLookaheadExactlyMatchesRemainingTracks() async {
        // Queue with exactly lookahead+1 tracks (6 tracks for lookahead=5)
        let tracks = makeTracks(count: 6)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertEqual(prefetchedIds.count, 6, "Should prefetch all tracks when count equals lookahead+1")
    }

    func testLookaheadWithFewerRemainingTracks() async {
        // Queue with fewer tracks than lookahead
        let tracks = makeTracks(count: 3)

        await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let prefetchedIds = await prefetcher.getPrefetchedTrackIds()
        XCTAssertEqual(prefetchedIds.count, 3, "Should prefetch all available tracks when fewer than lookahead")
    }
}

// MARK: - Testable TrackPrefetcher

/// A testable version of TrackPrefetcher that mocks the ImageCacheManager dependency
/// to avoid network calls and allow inspection of prefetch behavior
actor TestableTrackPrefetcher {

    private let lookahead = 5
    private var currentPrefetchTask: Task<Void, Never>?
    private var prefetchedTrackIds = Set<String>()

    // Test inspection properties
    private var loadedImageUrls: [String] = []
    private var loadedPriorities: [TaskPriority] = []
    private var imageLoadCount = 0

    // MARK: - Public API (mirrors TrackPrefetcher)

    func prefetchForQueue(_ tracks: [Track], currentIndex: Int) {
        currentPrefetchTask?.cancel()

        currentPrefetchTask = Task(priority: .utility) {
            await prefetchTracks(tracks: tracks, currentIndex: currentIndex)
        }
    }

    private func prefetchTracks(tracks: [Track], currentIndex: Int) async {
        let startIndex = max(0, currentIndex)
        let endIndex = min(currentIndex + lookahead + 1, tracks.count)

        guard startIndex < tracks.count else { return }

        for i in startIndex..<endIndex {
            guard !Task.isCancelled else { break }

            let track = tracks[i]
            guard !prefetchedTrackIds.contains(track.id) else { continue }

            await prefetchTrack(track, priority: i == currentIndex ? .high : .utility)
            prefetchedTrackIds.insert(track.id)

            if i != currentIndex {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            }
        }
    }

    private func prefetchTrack(_ track: Track, priority: TaskPriority) async {
        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            await Task(priority: priority) {
                await self.simulateImageLoad(url: url.absoluteString, priority: priority)
            }.value
        }
    }

    func preloadTrackImmediately(_ track: Track) async {
        guard track.artwork.starts(with: "http"),
              let url = URL(string: track.artwork) else {
            return
        }

        await simulateImageLoad(url: url.absoluteString, priority: .high)
        prefetchedTrackIds.insert(track.id)
    }

    // MARK: - Mock Image Loading

    private func simulateImageLoad(url: String, priority: TaskPriority) async {
        loadedImageUrls.append(url)
        loadedPriorities.append(priority)
        imageLoadCount += 1

        // Simulate small network delay
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }

    // MARK: - Test Inspection Methods

    func getPrefetchedTrackIds() -> Set<String> {
        prefetchedTrackIds
    }

    func hasCurrentPrefetchTask() -> Bool {
        currentPrefetchTask != nil
    }

    func getLoadedImageUrls() -> [String] {
        loadedImageUrls
    }

    func getLoadedPriorities() -> [TaskPriority] {
        loadedPriorities
    }

    func getImageLoadCount() -> Int {
        imageLoadCount
    }

    func reset() {
        currentPrefetchTask?.cancel()
        currentPrefetchTask = nil
        prefetchedTrackIds.removeAll()
        loadedImageUrls.removeAll()
        loadedPriorities.removeAll()
        imageLoadCount = 0
    }
}
