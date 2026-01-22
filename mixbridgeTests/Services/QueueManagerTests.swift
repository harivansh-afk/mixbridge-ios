import XCTest
@testable import mixbridge

/// Tests for QueueManager and PlaybackQueue
/// Tests the core queue logic: add/remove/reorder, peek/pop, contains checks
@MainActor
final class QueueManagerTests: XCTestCase {

    // MARK: - Test Fixtures

    private var queue: PlaybackQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = PlaybackQueue()
    }

    override func tearDown() async throws {
        queue = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeQueueItem(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        trackId: String? = nil,
        title: String = "Test Track"
    ) -> QueueItem {
        let soundCloudTrack = TestFixtures.sampleTrack
        let track = Track(
            id: trackId ?? String(soundCloudTrack.id),
            title: title,
            artist: soundCloudTrack.user.username,
            album: soundCloudTrack.genre ?? "",
            artwork: soundCloudTrack.artwork_url ?? "",
            duration: Double(soundCloudTrack.duration) / 1000.0
        )
        return QueueItem(
            id: id,
            serverId: serverId,
            trackId: trackId ?? String(soundCloudTrack.id),
            track: track,
            soundCloudTrack: soundCloudTrack
        )
    }

    private func makeQueueItems(count: Int) -> [QueueItem] {
        (0..<count).map { index in
            let trackId = "track-\(index)"
            let track = Track(
                id: trackId,
                title: "Track \(index + 1)",
                artist: "Artist",
                album: "Album",
                artwork: "",
                duration: 180.0
            )
            return QueueItem(
                id: "item-\(index)",
                serverId: "server-\(index)",
                trackId: trackId,
                track: track,
                soundCloudTrack: TestFixtures.sampleTrack
            )
        }
    }

    // MARK: - Initial State Tests

    func testQueueStartsEmpty() {
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.peek())
    }

    // MARK: - Append Tests

    func testAppendSingleItem() {
        let item = makeQueueItem(id: "item-1", trackId: "track-1", title: "First Track")

        queue.append(item)

        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.peek()?.id, "item-1")
        XCTAssertEqual(queue.items.first?.track.title, "First Track")
    }

    func testAppendMultipleItems() {
        let items = makeQueueItems(count: 3)

        for item in items {
            queue.append(item)
        }

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].id, "item-0")
        XCTAssertEqual(queue.items[1].id, "item-1")
        XCTAssertEqual(queue.items[2].id, "item-2")
    }

    func testAppendContentsOf() {
        let items = makeQueueItems(count: 5)

        queue.append(contentsOf: items)

        XCTAssertEqual(queue.count, 5)
        for (index, item) in queue.items.enumerated() {
            XCTAssertEqual(item.id, "item-\(index)")
        }
    }

    // MARK: - InsertNext Tests

    func testInsertNextOnEmptyQueue() {
        let item = makeQueueItem(id: "item-1", trackId: "track-1")

        queue.insertNext(item)

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.peek()?.id, "item-1")
    }

    func testInsertNextOnNonEmptyQueue() {
        let firstItem = makeQueueItem(id: "item-1", trackId: "track-1", title: "First")
        let secondItem = makeQueueItem(id: "item-2", trackId: "track-2", title: "Second")
        let insertedItem = makeQueueItem(id: "item-3", trackId: "track-3", title: "Inserted")

        queue.append(firstItem)
        queue.append(secondItem)
        queue.insertNext(insertedItem)

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].id, "item-3") // Inserted at front
        XCTAssertEqual(queue.items[1].id, "item-1")
        XCTAssertEqual(queue.items[2].id, "item-2")
    }

    // MARK: - Peek Tests

    func testPeekReturnsFirstItem() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let peeked = queue.peek()

        XCTAssertEqual(peeked?.id, "item-0")
        XCTAssertEqual(queue.count, 3) // Peek doesn't remove
    }

    func testPeekOnEmptyQueueReturnsNil() {
        XCTAssertNil(queue.peek())
    }

    // MARK: - Pop Tests

    func testPopReturnsAndRemovesFirstItem() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let popped = queue.pop()

        XCTAssertEqual(popped?.id, "item-0")
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.peek()?.id, "item-1")
    }

    func testPopOnEmptyQueueReturnsNil() {
        let popped = queue.pop()

        XCTAssertNil(popped)
        XCTAssertTrue(queue.isEmpty)
    }

    func testPopAllItems() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let first = queue.pop()
        let second = queue.pop()
        let third = queue.pop()
        let fourth = queue.pop()

        XCTAssertEqual(first?.id, "item-0")
        XCTAssertEqual(second?.id, "item-1")
        XCTAssertEqual(third?.id, "item-2")
        XCTAssertNil(fourth)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Contains Tests

    func testContainsTrackId() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        XCTAssertTrue(queue.contains(trackId: "track-0"))
        XCTAssertTrue(queue.contains(trackId: "track-1"))
        XCTAssertTrue(queue.contains(trackId: "track-2"))
        XCTAssertFalse(queue.contains(trackId: "track-99"))
    }

    func testContainsOnEmptyQueue() {
        XCTAssertFalse(queue.contains(trackId: "any-track"))
    }

    // MARK: - Item Query Tests

    func testItemForTrackId() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let found = queue.item(forTrackId: "track-1")

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "item-1")
    }

    func testItemForTrackIdNotFound() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let notFound = queue.item(forTrackId: "nonexistent")

        XCTAssertNil(notFound)
    }

    func testIndexOfTrackId() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        XCTAssertEqual(queue.index(ofTrackId: "track-0"), 0)
        XCTAssertEqual(queue.index(ofTrackId: "track-1"), 1)
        XCTAssertEqual(queue.index(ofTrackId: "track-2"), 2)
        XCTAssertNil(queue.index(ofTrackId: "nonexistent"))
    }

    // MARK: - Track At Index Tests

    func testTrackAtValidIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let track = queue.track(at: 1)

        XCTAssertNotNil(track)
        XCTAssertEqual(track?.id, "track-1")
    }

    func testTrackAtInvalidIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        XCTAssertNil(queue.track(at: -1))
        XCTAssertNil(queue.track(at: 3))
        XCTAssertNil(queue.track(at: 100))
    }

    func testSoundCloudTrackAtIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let scTrack = queue.soundCloudTrack(at: 0)

        XCTAssertNotNil(scTrack)
    }

    // MARK: - Remove by ID Tests

    func testRemoveById() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(id: "item-1")

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, "item-1")
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.items[0].id, "item-0")
        XCTAssertEqual(queue.items[1].id, "item-2")
    }

    func testRemoveByIdNotFound() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(id: "nonexistent")

        XCTAssertNil(removed)
        XCTAssertEqual(queue.count, 3)
    }

    // MARK: - Remove by TrackId Tests

    func testRemoveByTrackId() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(trackId: "track-1")

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.trackId, "track-1")
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveByTrackIdNotFound() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(trackId: "nonexistent")

        XCTAssertNil(removed)
        XCTAssertEqual(queue.count, 3)
    }

    // MARK: - Remove at Index Tests

    func testRemoveAtIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 1)

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, "item-1")
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveAtFirstIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 0)

        XCTAssertEqual(removed?.id, "item-0")
        XCTAssertEqual(queue.peek()?.id, "item-1")
    }

    func testRemoveAtLastIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 2)

        XCTAssertEqual(removed?.id, "item-2")
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveAtInvalidIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        XCTAssertNil(queue.remove(at: -1))
        XCTAssertNil(queue.remove(at: 3))
        XCTAssertNil(queue.remove(at: 100))
        XCTAssertEqual(queue.count, 3)
    }

    // MARK: - Move Tests

    func testMoveForward() {
        let items = makeQueueItems(count: 5)
        queue.append(contentsOf: items)

        queue.move(from: 0, to: 3)

        // After move: 1, 2, 0, 3, 4
        XCTAssertEqual(queue.items[0].id, "item-1")
        XCTAssertEqual(queue.items[1].id, "item-2")
        XCTAssertEqual(queue.items[2].id, "item-0")
        XCTAssertEqual(queue.items[3].id, "item-3")
        XCTAssertEqual(queue.items[4].id, "item-4")
    }

    func testMoveBackward() {
        let items = makeQueueItems(count: 5)
        queue.append(contentsOf: items)

        queue.move(from: 3, to: 1)

        // After move: 0, 3, 1, 2, 4
        XCTAssertEqual(queue.items[0].id, "item-0")
        XCTAssertEqual(queue.items[1].id, "item-3")
        XCTAssertEqual(queue.items[2].id, "item-1")
        XCTAssertEqual(queue.items[3].id, "item-2")
        XCTAssertEqual(queue.items[4].id, "item-4")
    }

    func testMoveToSamePosition() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.move(from: 1, to: 1)

        // Should be unchanged
        XCTAssertEqual(queue.items[0].id, "item-0")
        XCTAssertEqual(queue.items[1].id, "item-1")
        XCTAssertEqual(queue.items[2].id, "item-2")
    }

    func testMoveFromInvalidIndex() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.move(from: 10, to: 0)

        // Should be unchanged
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].id, "item-0")
    }

    func testMoveToEnd() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.move(from: 0, to: 3)

        // item-0 should be at end
        XCTAssertEqual(queue.items[0].id, "item-1")
        XCTAssertEqual(queue.items[1].id, "item-2")
        XCTAssertEqual(queue.items[2].id, "item-0")
    }

    func testMoveToBeginning() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.move(from: 2, to: 0)

        // item-2 should be at front
        XCTAssertEqual(queue.items[0].id, "item-2")
        XCTAssertEqual(queue.items[1].id, "item-0")
        XCTAssertEqual(queue.items[2].id, "item-1")
    }

    // MARK: - ReplaceAll Tests

    func testReplaceAllOnEmptyQueue() {
        let items = makeQueueItems(count: 3)

        queue.replaceAll(items)

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[0].id, "item-0")
    }

    func testReplaceAllOnNonEmptyQueue() {
        let oldItems = makeQueueItems(count: 2)
        queue.append(contentsOf: oldItems)

        let newItems = (0..<4).map { index in
            let trackId = "new-track-\(index)"
            let track = Track(
                id: trackId,
                title: "New Track \(index)",
                artist: "Artist",
                album: "",
                artwork: "",
                duration: 120.0
            )
            return QueueItem(
                id: "new-item-\(index)",
                serverId: nil,
                trackId: trackId,
                track: track,
                soundCloudTrack: TestFixtures.sampleTrack
            )
        }

        queue.replaceAll(newItems)

        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue.items[0].id, "new-item-0")
        XCTAssertFalse(queue.contains(trackId: "track-0")) // Old item gone
    }

    func testReplaceAllWithEmpty() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.replaceAll([])

        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Clear Tests

    func testClear() {
        let items = makeQueueItems(count: 5)
        queue.append(contentsOf: items)

        queue.clear()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.peek())
    }

    func testClearEmptyQueue() {
        queue.clear()

        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - UpdateItem Tests

    func testUpdateItemServerId() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        queue.updateItem(withId: "item-1") { old in
            QueueItem(
                id: old.id,
                serverId: "new-server-id",
                trackId: old.trackId,
                track: old.track,
                soundCloudTrack: old.soundCloudTrack
            )
        }

        XCTAssertEqual(queue.items[1].serverId, "new-server-id")
    }

    func testUpdateItemNotFound() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)
        var transformCalled = false

        queue.updateItem(withId: "nonexistent") { old in
            transformCalled = true
            return old
        }

        XCTAssertFalse(transformCalled)
    }

    // MARK: - Reinsert (Rollback) Tests

    func testReinsertAtOriginalPosition() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 1)!

        queue.reinsert(removed, at: 1)

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.items[1].id, "item-1")
    }

    func testReinsertAtBeginning() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 2)!

        queue.reinsert(removed, at: 0)

        XCTAssertEqual(queue.items[0].id, "item-2")
        XCTAssertEqual(queue.count, 3)
    }

    func testReinsertAtEnd() {
        let items = makeQueueItems(count: 3)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 0)!

        queue.reinsert(removed, at: 2)

        XCTAssertEqual(queue.items[2].id, "item-0")
    }

    func testReinsertBeyondBounds() {
        let items = makeQueueItems(count: 2)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 0)!

        queue.reinsert(removed, at: 100)

        // Should be clamped to end
        XCTAssertEqual(queue.items.last?.id, "item-0")
    }

    func testReinsertNegativeIndex() {
        let items = makeQueueItems(count: 2)
        queue.append(contentsOf: items)

        let removed = queue.remove(at: 1)!

        queue.reinsert(removed, at: -5)

        // Should be clamped to beginning
        XCTAssertEqual(queue.items.first?.id, "item-1")
    }

    // MARK: - Edge Cases

    func testQueueItemEquality() {
        let item1 = makeQueueItem(id: "same-id", trackId: "track-1")
        let item2 = makeQueueItem(id: "same-id", trackId: "track-2")
        let item3 = makeQueueItem(id: "different-id", trackId: "track-1")

        XCTAssertEqual(item1, item2) // Same id = equal
        XCTAssertNotEqual(item1, item3) // Different id = not equal
    }

    func testMultipleOperationsSequence() {
        // Simulate a realistic usage sequence
        let items = makeQueueItems(count: 5)
        queue.append(contentsOf: items)

        // Pop first (simulates track starting to play)
        let _ = queue.pop()
        XCTAssertEqual(queue.count, 4)

        // Insert next (user adds track to play next)
        let newItem = makeQueueItem(id: "priority-item", trackId: "priority-track")
        queue.insertNext(newItem)
        XCTAssertEqual(queue.peek()?.id, "priority-item")

        // Remove specific track
        let _ = queue.remove(trackId: "track-2")
        XCTAssertFalse(queue.contains(trackId: "track-2"))

        // Reorder
        queue.move(from: 0, to: 2)
        XCTAssertEqual(queue.items[0].id, "item-1") // item-1 is now first

        // Final state check
        XCTAssertEqual(queue.count, 4)
    }

    func testStressTestLargeQueue() {
        // Add many items
        let count = 100
        for i in 0..<count {
            let trackId = "track-\(i)"
            let track = Track(id: trackId, title: "Track \(i)", artist: "Artist", album: "", artwork: "", duration: 180.0)
            let item = QueueItem(id: "item-\(i)", serverId: nil, trackId: trackId, track: track, soundCloudTrack: TestFixtures.sampleTrack)
            queue.append(item)
        }

        XCTAssertEqual(queue.count, count)

        // Pop half
        for _ in 0..<50 {
            let _ = queue.pop()
        }

        XCTAssertEqual(queue.count, 50)
        XCTAssertEqual(queue.peek()?.trackId, "track-50")

        // Clear
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
    }
}
