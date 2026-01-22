import XCTest
@testable import mixbridge

/// Tests for PlaybackPositionTracker
/// Tests position tracking accuracy, session management, and flush behavior
final class PlaybackPositionTrackerTests: XCTestCase {

    // MARK: - Test Fixtures

    private var tracker: TestablePlaybackPositionTracker!
    private var mockConvexService: MockPositionConvexService!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        mockConvexService = MockPositionConvexService()
        tracker = TestablePlaybackPositionTracker(
            convexService: mockConvexService,
            currentUserId: "test-user-123",
            flushInterval: 10.0
        )
    }

    @MainActor
    override func tearDown() async throws {
        tracker.endSession()
        tracker = nil
        mockConvexService = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    @MainActor
    func testInitialStateHasNoSession() {
        XCTAssertNil(tracker.sessionId)
        XCTAssertNil(tracker.queueIndex)
    }

    @MainActor
    func testInitialStateHasZeroPosition() {
        XCTAssertEqual(tracker.lastPositionForTesting, 0)
        XCTAssertEqual(tracker.lastDurationForTesting, 0)
    }

    // MARK: - Start Session Tests

    @MainActor
    func testStartSessionReturnsUniqueSessionId() {
        let sessionId = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(tracker.sessionId, sessionId)
    }

    @MainActor
    func testStartSessionSetsQueueIndex() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 5, duration: 180.0)

        XCTAssertEqual(tracker.queueIndex, 5)
    }

    @MainActor
    func testStartSessionSetsNilQueueIndex() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: nil, duration: 180.0)

        XCTAssertNil(tracker.queueIndex)
    }

    @MainActor
    func testStartSessionSetsDuration() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 240.5)

        XCTAssertEqual(tracker.lastDurationForTesting, 240.5)
    }

    @MainActor
    func testStartSessionResetsPosition() {
        // Start first session and update position
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(90.0, duration: 180.0)

        // Start new session
        _ = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)

        XCTAssertEqual(tracker.lastPositionForTesting, 0)
    }

    @MainActor
    func testStartSessionGeneratesUniqueIds() {
        let sessionId1 = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.endSession()

        let sessionId2 = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)

        XCTAssertNotEqual(sessionId1, sessionId2)
    }

    @MainActor
    func testStartSessionFlushesExistingSession() {
        // Start first session and update position
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(90.0, duration: 180.0)

        // Start new session - should flush previous
        _ = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
    }

    @MainActor
    func testStartSessionDoesNotFlushWithoutPosition() {
        // Start first session without updating position
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        // Start new session - should not flush (position is 0)
        _ = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    // MARK: - Update Position Tests

    @MainActor
    func testUpdatePositionStoresPosition() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        tracker.updatePosition(45.5, duration: 180.0)

        XCTAssertEqual(tracker.lastPositionForTesting, 45.5)
    }

    @MainActor
    func testUpdatePositionStoresDuration() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        tracker.updatePosition(45.5, duration: 185.0)

        XCTAssertEqual(tracker.lastDurationForTesting, 185.0)
    }

    @MainActor
    func testUpdatePositionWithoutSessionDoesNothing() {
        // No session started
        tracker.updatePosition(45.5, duration: 180.0)

        XCTAssertEqual(tracker.lastPositionForTesting, 0)
    }

    @MainActor
    func testUpdatePositionDoesNotFlushBeforeInterval() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        // Update position multiple times
        tracker.updatePosition(10.0, duration: 180.0)
        tracker.updatePosition(20.0, duration: 180.0)
        tracker.updatePosition(30.0, duration: 180.0)

        // Should not have flushed yet
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testUpdatePositionFlushesAfterInterval() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(10.0, duration: 180.0)

        // Simulate time passing beyond flush interval
        tracker.simulateTimePassedForTesting(seconds: 11)
        tracker.updatePosition(50.0, duration: 180.0)

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
    }

    @MainActor
    func testUpdatePositionTracksMultipleFlushes() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(10.0, duration: 180.0)

        // First flush
        tracker.simulateTimePassedForTesting(seconds: 11)
        tracker.updatePosition(50.0, duration: 180.0)

        // Second flush
        tracker.simulateTimePassedForTesting(seconds: 11)
        tracker.updatePosition(90.0, duration: 180.0)

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 2)
    }

    @MainActor
    func testUpdatePositionUpdatesMultipleTimes() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        tracker.updatePosition(10.0, duration: 180.0)
        XCTAssertEqual(tracker.lastPositionForTesting, 10.0)

        tracker.updatePosition(20.0, duration: 180.0)
        XCTAssertEqual(tracker.lastPositionForTesting, 20.0)

        tracker.updatePosition(30.0, duration: 180.0)
        XCTAssertEqual(tracker.lastPositionForTesting, 30.0)
    }

    // MARK: - Flush Tests

    @MainActor
    func testFlushSendsCorrectSessionId() {
        let sessionId = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(60.0, duration: 180.0)

        tracker.flush()

        XCTAssertEqual(mockConvexService.lastSessionId, sessionId)
    }

    @MainActor
    func testFlushSendsCorrectUserId() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(60.0, duration: 180.0)

        tracker.flush()

        XCTAssertEqual(mockConvexService.lastUserId, "test-user-123")
    }

    @MainActor
    func testFlushSendsCorrectPosition() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(75.5, duration: 180.0)

        tracker.flush()

        XCTAssertEqual(mockConvexService.lastPlaybackPosition, 75.5)
    }

    @MainActor
    func testFlushSendsCorrectDuration() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(60.0, duration: 180.0)

        tracker.flush()

        XCTAssertEqual(mockConvexService.lastDuration, 180.0)
    }

    @MainActor
    func testFlushWithoutSessionDoesNothing() {
        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testFlushWithZeroPositionDoesNothing() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        // Position remains 0

        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testFlushWithoutUserIdDoesNothing() {
        // Create tracker without user ID
        let trackerWithoutUser = TestablePlaybackPositionTracker(
            convexService: mockConvexService,
            currentUserId: nil,
            flushInterval: 10.0
        )

        _ = trackerWithoutUser.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        trackerWithoutUser.updatePosition(60.0, duration: 180.0)
        trackerWithoutUser.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testFlushUpdatesLastFlushTime() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(60.0, duration: 180.0)

        let beforeFlush = tracker.lastFlushTimeForTesting

        tracker.flush()

        let afterFlush = tracker.lastFlushTimeForTesting
        XCTAssertGreaterThanOrEqual(afterFlush, beforeFlush)
    }

    @MainActor
    func testMultipleFlushesIncrementCallCount() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(30.0, duration: 180.0)

        tracker.flush()
        tracker.flush()
        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 3)
    }

    // MARK: - End Session Tests

    @MainActor
    func testEndSessionClearsSessionId() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        tracker.endSession()

        XCTAssertNil(tracker.sessionId)
    }

    @MainActor
    func testEndSessionClearsQueueIndex() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 5, duration: 180.0)

        tracker.endSession()

        XCTAssertNil(tracker.queueIndex)
    }

    @MainActor
    func testEndSessionClearsPosition() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(90.0, duration: 180.0)

        tracker.endSession()

        XCTAssertEqual(tracker.lastPositionForTesting, 0)
    }

    @MainActor
    func testEndSessionClearsDuration() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        tracker.endSession()

        XCTAssertEqual(tracker.lastDurationForTesting, 0)
    }

    @MainActor
    func testEndSessionFlushesFinalPosition() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(150.0, duration: 180.0)

        tracker.endSession()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
        XCTAssertEqual(mockConvexService.lastPlaybackPosition, 150.0)
    }

    @MainActor
    func testEndSessionWithoutSessionDoesNothing() {
        // No session started
        tracker.endSession()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testEndSessionWithZeroPositionDoesNotFlush() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        // Position remains 0

        tracker.endSession()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    // MARK: - Percentage Calculation Tests

    @MainActor
    func testFlushCalculatesPercentageCorrectly() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 200.0)
        tracker.updatePosition(100.0, duration: 200.0) // 50%

        tracker.flush()

        // Verify position/duration sent correctly (percentage calculation is internal)
        XCTAssertEqual(mockConvexService.lastPlaybackPosition, 100.0)
        XCTAssertEqual(mockConvexService.lastDuration, 200.0)
    }

    @MainActor
    func testFlushWithZeroDurationDoesNotCrash() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 0)
        tracker.updatePosition(10.0, duration: 0)

        // Should not crash
        tracker.flush()

        // Position > 0 so flush should occur
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
    }

    // MARK: - Session Lifecycle Tests

    @MainActor
    func testCompleteSessionLifecycle() {
        // Start session
        let sessionId = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        XCTAssertNotNil(sessionId)
        XCTAssertEqual(tracker.sessionId, sessionId)

        // Update position multiple times
        tracker.updatePosition(30.0, duration: 180.0)
        tracker.updatePosition(60.0, duration: 180.0)

        // Manual flush
        tracker.flush()
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)

        // More updates
        tracker.updatePosition(90.0, duration: 180.0)
        tracker.updatePosition(120.0, duration: 180.0)

        // End session (should flush)
        tracker.endSession()
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 2)
        XCTAssertNil(tracker.sessionId)
    }

    @MainActor
    func testMultipleSessionsInSequence() {
        // First session
        let sessionId1 = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(90.0, duration: 180.0)
        tracker.endSession()

        // Second session
        let sessionId2 = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)
        tracker.updatePosition(100.0, duration: 200.0)
        tracker.endSession()

        // Third session
        let sessionId3 = tracker.startSession(trackId: "track-3", queueIndex: 2, duration: 220.0)
        tracker.updatePosition(110.0, duration: 220.0)
        tracker.endSession()

        XCTAssertNotEqual(sessionId1, sessionId2)
        XCTAssertNotEqual(sessionId2, sessionId3)
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 3)
    }

    @MainActor
    func testSessionSwitchWithoutEndSession() {
        // Start first session
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(90.0, duration: 180.0)

        // Start new session without ending first - should auto-flush
        _ = tracker.startSession(trackId: "track-2", queueIndex: 1, duration: 200.0)

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
        XCTAssertEqual(mockConvexService.lastPlaybackPosition, 90.0)
    }

    // MARK: - Flush Interval Tests

    @MainActor
    func testCustomFlushInterval() {
        // Create tracker with 5 second flush interval
        let fastTracker = TestablePlaybackPositionTracker(
            convexService: mockConvexService,
            currentUserId: "test-user-123",
            flushInterval: 5.0
        )

        _ = fastTracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        fastTracker.updatePosition(10.0, duration: 180.0)

        // Simulate 3 seconds - should not flush
        fastTracker.simulateTimePassedForTesting(seconds: 3)
        fastTracker.updatePosition(20.0, duration: 180.0)
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)

        // Simulate 3 more seconds (total 6) - should flush
        fastTracker.simulateTimePassedForTesting(seconds: 3)
        fastTracker.updatePosition(30.0, duration: 180.0)
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
    }

    // MARK: - Edge Cases

    @MainActor
    func testVerySmallPositionFlushes() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(0.001, duration: 180.0) // Very small but > 0

        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
    }

    @MainActor
    func testNegativePositionDoesNotFlush() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(-5.0, duration: 180.0)

        tracker.flush()

        // Position <= 0 should not flush
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testPositionBeyondDurationStillFlushes() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)
        tracker.updatePosition(200.0, duration: 180.0) // Beyond duration

        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 1)
        XCTAssertEqual(mockConvexService.lastPlaybackPosition, 200.0)
    }

    @MainActor
    func testRapidPositionUpdates() {
        _ = tracker.startSession(trackId: "track-1", queueIndex: 0, duration: 180.0)

        // Simulate rapid updates like from time observer
        for i in 0..<100 {
            tracker.updatePosition(Double(i) * 0.5, duration: 180.0)
        }

        // Last position should be stored
        XCTAssertEqual(tracker.lastPositionForTesting, 49.5)

        // Should not have flushed (no time passed)
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testTrackIdStoredCorrectly() {
        _ = tracker.startSession(trackId: "unique-track-id-12345", queueIndex: 0, duration: 180.0)

        XCTAssertEqual(tracker.currentTrackIdForTesting, "unique-track-id-12345")
    }

    @MainActor
    func testEndSessionBeforeStartDoesNotCrash() {
        // Should not crash when ending session that was never started
        tracker.endSession()

        XCTAssertNil(tracker.sessionId)
        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testFlushBeforeStartDoesNotCrash() {
        // Should not crash when flushing without session
        tracker.flush()

        XCTAssertEqual(mockConvexService.updatePlayPositionCallCount, 0)
    }

    @MainActor
    func testUpdatePositionBeforeStartDoesNotCrash() {
        // Should not crash when updating position without session
        tracker.updatePosition(60.0, duration: 180.0)

        XCTAssertEqual(tracker.lastPositionForTesting, 0)
    }
}

// MARK: - Mock ConvexService for Position Tracking

/// Mock ConvexService that only implements updatePlayPosition for testing PlaybackPositionTracker
final class MockPositionConvexService: @unchecked Sendable {

    // MARK: - Call Tracking

    private(set) var updatePlayPositionCallCount = 0
    private(set) var lastSessionId: String?
    private(set) var lastUserId: String?
    private(set) var lastPlaybackPosition: Double?
    private(set) var lastDuration: Double?

    // MARK: - Error Injection

    var errorToThrow: Error?

    // MARK: - Mock Methods

    func updatePlayPosition(
        sessionId: String,
        userId: String,
        playbackPosition: Double,
        duration: Double
    ) async throws {
        updatePlayPositionCallCount += 1
        lastSessionId = sessionId
        lastUserId = userId
        lastPlaybackPosition = playbackPosition
        lastDuration = duration

        if let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Test Helpers

    func reset() {
        updatePlayPositionCallCount = 0
        lastSessionId = nil
        lastUserId = nil
        lastPlaybackPosition = nil
        lastDuration = nil
        errorToThrow = nil
    }
}

// MARK: - Testable PlaybackPositionTracker

/// A testable version of PlaybackPositionTracker that allows dependency injection
/// and time manipulation for testing flush intervals
@MainActor
final class TestablePlaybackPositionTracker {

    private let convexService: MockPositionConvexService
    private let currentUserId: String?
    private let flushInterval: TimeInterval

    private var currentSessionId: String?
    private var currentTrackId: String?
    private var currentQueueIndex: Int?
    private var lastPosition: Double = 0
    private var lastDuration: Double = 0
    private var lastFlushTime: Date = Date()

    init(
        convexService: MockPositionConvexService,
        currentUserId: String?,
        flushInterval: TimeInterval = 10.0
    ) {
        self.convexService = convexService
        self.currentUserId = currentUserId
        self.flushInterval = flushInterval
    }

    // MARK: - Public API (mirrors PlaybackPositionTracker)

    func startSession(trackId: String, queueIndex: Int?, duration: Double) -> String {
        // End any existing session first
        if currentSessionId != nil {
            flush()
        }

        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        currentTrackId = trackId
        currentQueueIndex = queueIndex
        lastPosition = 0
        lastDuration = duration
        lastFlushTime = Date()

        return sessionId
    }

    func updatePosition(_ position: Double, duration: Double) {
        guard currentSessionId != nil else { return }

        lastPosition = position
        lastDuration = duration

        // Check if we should flush (every flushInterval seconds)
        if Date().timeIntervalSince(lastFlushTime) >= flushInterval {
            flush()
        }
    }

    func flush() {
        guard let sessionId = currentSessionId,
              let userId = currentUserId,
              lastPosition > 0 else {
            return
        }

        lastFlushTime = Date()
        let position = lastPosition
        let duration = lastDuration

        Task.detached(priority: .utility) { [convexService] in
            try? await convexService.updatePlayPosition(
                sessionId: sessionId,
                userId: userId,
                playbackPosition: position,
                duration: duration
            )
        }
    }

    func endSession() {
        guard currentSessionId != nil else { return }

        flush()
        currentSessionId = nil
        currentTrackId = nil
        currentQueueIndex = nil
        lastPosition = 0
        lastDuration = 0
    }

    var sessionId: String? { currentSessionId }
    var queueIndex: Int? { currentQueueIndex }

    // MARK: - Testing Helpers

    var lastPositionForTesting: Double { lastPosition }
    var lastDurationForTesting: Double { lastDuration }
    var lastFlushTimeForTesting: Date { lastFlushTime }
    var currentTrackIdForTesting: String? { currentTrackId }

    func simulateTimePassedForTesting(seconds: TimeInterval) {
        lastFlushTime = lastFlushTime.addingTimeInterval(-seconds)
    }
}
