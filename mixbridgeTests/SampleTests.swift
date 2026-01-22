import XCTest
@testable import mixbridge

/// Sample test class to verify test infrastructure is working
final class SampleTests: XCTestCase {

    // MARK: - Setup and Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Put setup code here
    }

    override func tearDownWithError() throws {
        // Put teardown code here
        try super.tearDownWithError()
    }

    // MARK: - Test Fixtures

    func testFixturesAreAvailable() {
        // Verify test fixtures can be accessed
        XCTAssertEqual(TestFixtures.sampleTrack.id, 100001)
        XCTAssertEqual(TestFixtures.sampleTrack.title, "Test Track")
        XCTAssertEqual(TestFixtures.testUser.username, "TestArtist")
    }

    func testFixturesGenerateMultipleTracks() {
        let tracks = TestFixtures.makeTracks(count: 5)
        XCTAssertEqual(tracks.count, 5)

        // Verify each track has a unique ID
        let ids = Set(tracks.map { $0.id })
        XCTAssertEqual(ids.count, 5)
    }

    func testFixturesGenerateMultiplePlaylists() {
        let playlists = TestFixtures.makePlaylists(count: 3)
        XCTAssertEqual(playlists.count, 3)

        // Verify each playlist has a unique ID
        let ids = Set(playlists.map { $0.id })
        XCTAssertEqual(ids.count, 3)
    }

    // MARK: - Mock Services

    func testMockConvexServiceReturnsStubData() async throws {
        let mock = MockConvexService()
        mock.stubbedLikedTracks = [TestFixtures.sampleTrack, TestFixtures.secondaryTrack]

        let tracks = try await mock.getLikedTracks(userId: TestFixtures.testUserId)

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.first?.id, TestFixtures.sampleTrack.id)
    }

    func testMockConvexServiceTracksMethodCalls() async throws {
        let mock = MockConvexService()

        _ = try await mock.getLikedTracks(userId: "user-1")
        _ = try await mock.getPlaylists(userId: "user-2")

        XCTAssertEqual(mock.methodCalls.count, 2)
        XCTAssertEqual(mock.methodCalls[0].name, "getLikedTracks")
        XCTAssertEqual(mock.methodCalls[1].name, "getPlaylists")
    }

    func testMockConvexServiceThrowsConfiguredError() async {
        let mock = MockConvexService()
        mock.errorToThrow = ConvexError.requestFailed

        do {
            _ = try await mock.getLikedTracks(userId: TestFixtures.testUserId)
            XCTFail("Expected error to be thrown")
        } catch ConvexError.requestFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @MainActor
    func testMockAuthManagerSimulatesLogin() async {
        let mock = MockAuthManager()
        mock.simulateLoggedIn(userId: "test-user")

        XCTAssertTrue(mock.isAuthenticated)
        XCTAssertEqual(mock.currentUserId, "test-user")
        XCTAssertEqual(mock.currentProvider, .soundcloud)
    }

    @MainActor
    func testMockAuthManagerSimulatesLogout() async {
        let mock = MockAuthManager()
        mock.simulateLoggedIn()

        mock.logout()

        XCTAssertFalse(mock.isAuthenticated)
        XCTAssertNil(mock.currentUserId)
        XCTAssertEqual(mock.logoutCallCount, 1)
    }

    // MARK: - Async Test Helpers

    func testAsyncWaitForCondition() async {
        var counter = 0

        Task {
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                counter += 1
            }
        }

        await waitUntil(timeout: 2.0) {
            counter >= 3
        }

        XCTAssertGreaterThanOrEqual(counter, 3)
    }

    func testAsyncNoThrow() async {
        let result = await assertNoThrowAsync {
            return "success"
        }

        XCTAssertEqual(result, "success")
    }

    // MARK: - Track Conversion

    func testSoundCloudTrackConversion() {
        let scTrack = TestFixtures.sampleTrack
        let track = scTrack.toTrack()

        XCTAssertEqual(track.id, String(scTrack.id))
        XCTAssertEqual(track.title, scTrack.title)
        XCTAssertEqual(track.artist, scTrack.user.username)
        XCTAssertEqual(track.duration, Double(scTrack.duration) / 1000.0, accuracy: 0.001)
    }

    // MARK: - Search Results

    func testSearchResultFixtures() {
        let result = TestFixtures.sampleSearchResult

        XCTAssertEqual(result.tracks.count, 2)
        XCTAssertEqual(result.playlists.count, 1)
        XCTAssertEqual(result.users.count, 2)
    }

    func testEmptySearchResultFixtures() {
        let result = TestFixtures.emptySearchResult

        XCTAssertTrue(result.tracks.isEmpty)
        XCTAssertTrue(result.playlists.isEmpty)
        XCTAssertTrue(result.users.isEmpty)
    }
}
