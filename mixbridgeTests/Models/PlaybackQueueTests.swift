//
//  PlaybackQueueTests.swift
//  mixbridgeTests
//
//  Comprehensive tests for PlaybackQueue and QueueItem models.
//

import XCTest
@testable import mixbridge

@MainActor
final class PlaybackQueueTests: XCTestCase {

    // MARK: - Test Helpers

    private var sut: PlaybackQueue!

    override func setUp() {
        super.setUp()
        sut = PlaybackQueue()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - QueueItem Factory

    private func makeQueueItem(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        trackId: String? = nil,
        title: String = "Test Track"
    ) -> QueueItem {
        let actualTrackId = trackId ?? "track-\(UUID().uuidString)"
        let track = Track(
            id: actualTrackId,
            title: title,
            artist: "Test Artist",
            album: "Test Album",
            artwork: "https://example.com/art.jpg",
            duration: 180.0
        )
        return QueueItem(
            id: id,
            serverId: serverId,
            trackId: actualTrackId,
            track: track,
            soundCloudTrack: nil
        )
    }

    private func makeQueueItems(count: Int, prefix: String = "item") -> [QueueItem] {
        (0..<count).map { index in
            makeQueueItem(
                id: "\(prefix)-\(index)",
                trackId: "track-\(prefix)-\(index)",
                title: "Track \(index)"
            )
        }
    }

    // MARK: - QueueItem Tests

    func testQueueItemInit_withAllParameters() {
        let track = Track(id: "t1", title: "Title", artist: "Artist")
        let soundCloudTrack = TestFixtures.sampleTrack

        let item = QueueItem(
            id: "q1",
            serverId: "server-123",
            trackId: "sc-track-1",
            track: track,
            soundCloudTrack: soundCloudTrack
        )

        XCTAssertEqual(item.id, "q1")
        XCTAssertEqual(item.serverId, "server-123")
        XCTAssertEqual(item.trackId, "sc-track-1")
        XCTAssertEqual(item.track.title, "Title")
        XCTAssertNotNil(item.soundCloudTrack)
    }

    func testQueueItemInit_withNilServerId() {
        let item = makeQueueItem(serverId: nil)

        XCTAssertNil(item.serverId)
    }

    func testQueueItemInit_withNilSoundCloudTrack() {
        let item = makeQueueItem()

        XCTAssertNil(item.soundCloudTrack)
    }

    func testQueueItem_equality_basedOnIdOnly() {
        let track1 = Track(id: "t1", title: "Title 1", artist: "Artist 1")
        let track2 = Track(id: "t2", title: "Title 2", artist: "Artist 2")

        let item1 = QueueItem(id: "same-id", serverId: nil, trackId: "track-1", track: track1, soundCloudTrack: nil)
        let item2 = QueueItem(id: "same-id", serverId: "server-123", trackId: "track-2", track: track2, soundCloudTrack: nil)

        XCTAssertEqual(item1, item2, "QueueItems with same id should be equal regardless of other fields")
    }

    func testQueueItem_inequality_differentIds() {
        let item1 = makeQueueItem(id: "id-1")
        let item2 = makeQueueItem(id: "id-2")

        XCTAssertNotEqual(item1, item2)
    }

    func testQueueItem_identifiable_idProperty() {
        let item = makeQueueItem(id: "test-id")

        XCTAssertEqual(item.id, "test-id")
    }

    // MARK: - Initial State Tests

    func testInitialState_isEmpty() {
        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.count, 0)
        XCTAssertTrue(sut.items.isEmpty)
    }

    func testInitialState_peekReturnsNil() {
        XCTAssertNil(sut.peek())
    }

    func testInitialState_popReturnsNil() {
        XCTAssertNil(sut.pop())
    }

    // MARK: - Append Tests

    func testAppend_singleItem() {
        let item = makeQueueItem()

        sut.append(item)

        XCTAssertEqual(sut.count, 1)
        XCTAssertFalse(sut.isEmpty)
        XCTAssertEqual(sut.items.first, item)
    }

    func testAppend_multipleItems_maintainsOrder() {
        let items = makeQueueItems(count: 3)

        for item in items {
            sut.append(item)
        }

        XCTAssertEqual(sut.count, 3)
        XCTAssertEqual(sut.items[0].id, "item-0")
        XCTAssertEqual(sut.items[1].id, "item-1")
        XCTAssertEqual(sut.items[2].id, "item-2")
    }

    func testAppendContentsOf_addsAllItems() {
        let items = makeQueueItems(count: 5)

        sut.append(contentsOf: items)

        XCTAssertEqual(sut.count, 5)
        for (index, item) in items.enumerated() {
            XCTAssertEqual(sut.items[index], item)
        }
    }

    func testAppendContentsOf_emptyArray() {
        sut.append(contentsOf: [])

        XCTAssertTrue(sut.isEmpty)
    }

    func testAppendContentsOf_toExistingQueue() {
        let initialItems = makeQueueItems(count: 2, prefix: "initial")
        let newItems = makeQueueItems(count: 3, prefix: "new")

        sut.append(contentsOf: initialItems)
        sut.append(contentsOf: newItems)

        XCTAssertEqual(sut.count, 5)
        XCTAssertEqual(sut.items[0].id, "initial-0")
        XCTAssertEqual(sut.items[2].id, "new-0")
    }

    // MARK: - InsertNext Tests

    func testInsertNext_toEmptyQueue() {
        let item = makeQueueItem()

        sut.insertNext(item)

        XCTAssertEqual(sut.count, 1)
        XCTAssertEqual(sut.peek(), item)
    }

    func testInsertNext_insertsAtFront() {
        let existingItems = makeQueueItems(count: 3, prefix: "existing")
        sut.append(contentsOf: existingItems)

        let newItem = makeQueueItem(id: "new-item")
        sut.insertNext(newItem)

        XCTAssertEqual(sut.count, 4)
        XCTAssertEqual(sut.items[0].id, "new-item")
        XCTAssertEqual(sut.items[1].id, "existing-0")
    }

    func testInsertNext_multipleTimes() {
        sut.insertNext(makeQueueItem(id: "first"))
        sut.insertNext(makeQueueItem(id: "second"))
        sut.insertNext(makeQueueItem(id: "third"))

        XCTAssertEqual(sut.items[0].id, "third")
        XCTAssertEqual(sut.items[1].id, "second")
        XCTAssertEqual(sut.items[2].id, "first")
    }

    // MARK: - Peek Tests

    func testPeek_returnsFirstItem() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        XCTAssertEqual(sut.peek()?.id, "item-0")
    }

    func testPeek_doesNotRemoveItem() {
        let item = makeQueueItem()
        sut.append(item)

        _ = sut.peek()
        _ = sut.peek()

        XCTAssertEqual(sut.count, 1)
    }

    // MARK: - Pop Tests

    func testPop_removesAndReturnsFirstItem() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let popped = sut.pop()

        XCTAssertEqual(popped?.id, "item-0")
        XCTAssertEqual(sut.count, 2)
        XCTAssertEqual(sut.items[0].id, "item-1")
    }

    func testPop_emptyQueue_returnsNil() {
        let result = sut.pop()

        XCTAssertNil(result)
    }

    func testPop_allItems() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        XCTAssertEqual(sut.pop()?.id, "item-0")
        XCTAssertEqual(sut.pop()?.id, "item-1")
        XCTAssertEqual(sut.pop()?.id, "item-2")
        XCTAssertNil(sut.pop())
        XCTAssertTrue(sut.isEmpty)
    }

    // MARK: - Contains Tests

    func testContains_existingTrackId_returnsTrue() {
        let item = makeQueueItem(trackId: "track-123")
        sut.append(item)

        XCTAssertTrue(sut.contains(trackId: "track-123"))
    }

    func testContains_nonexistentTrackId_returnsFalse() {
        let item = makeQueueItem(trackId: "track-123")
        sut.append(item)

        XCTAssertFalse(sut.contains(trackId: "track-999"))
    }

    func testContains_emptyQueue_returnsFalse() {
        XCTAssertFalse(sut.contains(trackId: "any-track"))
    }

    func testContains_multipleItems_findsCorrectTrack() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        XCTAssertTrue(sut.contains(trackId: "track-item-2"))
        XCTAssertFalse(sut.contains(trackId: "track-item-99"))
    }

    // MARK: - Item Query Tests

    func testItemForTrackId_existingTrack_returnsItem() {
        let item = makeQueueItem(trackId: "target-track")
        sut.append(item)

        let found = sut.item(forTrackId: "target-track")

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.trackId, "target-track")
    }

    func testItemForTrackId_nonexistentTrack_returnsNil() {
        sut.append(makeQueueItem(trackId: "other-track"))

        let found = sut.item(forTrackId: "missing-track")

        XCTAssertNil(found)
    }

    func testIndexOfTrackId_existingTrack_returnsIndex() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        let index = sut.index(ofTrackId: "track-item-3")

        XCTAssertEqual(index, 3)
    }

    func testIndexOfTrackId_nonexistentTrack_returnsNil() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let index = sut.index(ofTrackId: "nonexistent")

        XCTAssertNil(index)
    }

    func testTrackAtIndex_validIndex_returnsTrack() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let track = sut.track(at: 1)

        XCTAssertNotNil(track)
        XCTAssertEqual(track?.title, "Track 1")
    }

    func testTrackAtIndex_invalidIndex_returnsNil() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        XCTAssertNil(sut.track(at: -1))
        XCTAssertNil(sut.track(at: 3))
        XCTAssertNil(sut.track(at: 100))
    }

    func testSoundCloudTrackAtIndex_withSoundCloudTrack_returnsTrack() {
        let scTrack = TestFixtures.sampleTrack
        let track = Track(id: "t1", title: "Title", artist: "Artist")
        let item = QueueItem(id: "q1", serverId: nil, trackId: "track-1", track: track, soundCloudTrack: scTrack)
        sut.append(item)

        let result = sut.soundCloudTrack(at: 0)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, scTrack.id)
    }

    func testSoundCloudTrackAtIndex_withNilSoundCloudTrack_returnsNil() {
        let item = makeQueueItem()
        sut.append(item)

        let result = sut.soundCloudTrack(at: 0)

        XCTAssertNil(result)
    }

    func testSoundCloudTrackAtIndex_invalidIndex_returnsNil() {
        XCTAssertNil(sut.soundCloudTrack(at: 0))
        XCTAssertNil(sut.soundCloudTrack(at: -1))
    }

    // MARK: - Remove by ID Tests

    func testRemoveById_existingId_removesAndReturnsItem() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(id: "item-1")

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, "item-1")
        XCTAssertEqual(sut.count, 2)
        XCTAssertFalse(sut.items.contains { $0.id == "item-1" })
    }

    func testRemoveById_nonexistentId_returnsNil() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(id: "nonexistent")

        XCTAssertNil(removed)
        XCTAssertEqual(sut.count, 3)
    }

    func testRemoveById_emptyQueue_returnsNil() {
        let removed = sut.remove(id: "any-id")

        XCTAssertNil(removed)
    }

    // MARK: - Remove by TrackId Tests

    func testRemoveByTrackId_existingTrackId_removesAndReturnsItem() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(trackId: "track-item-1")

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.trackId, "track-item-1")
        XCTAssertEqual(sut.count, 2)
    }

    func testRemoveByTrackId_nonexistentTrackId_returnsNil() {
        sut.append(makeQueueItem(trackId: "existing"))

        let removed = sut.remove(trackId: "nonexistent")

        XCTAssertNil(removed)
        XCTAssertEqual(sut.count, 1)
    }

    // MARK: - Remove at Index Tests

    func testRemoveAtIndex_validIndex_removesAndReturnsItem() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        let removed = sut.remove(at: 2)

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, "item-2")
        XCTAssertEqual(sut.count, 4)
        XCTAssertEqual(sut.items[2].id, "item-3")
    }

    func testRemoveAtIndex_firstIndex() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(at: 0)

        XCTAssertEqual(removed?.id, "item-0")
        XCTAssertEqual(sut.items[0].id, "item-1")
    }

    func testRemoveAtIndex_lastIndex() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(at: 2)

        XCTAssertEqual(removed?.id, "item-2")
        XCTAssertEqual(sut.count, 2)
    }

    func testRemoveAtIndex_negativeIndex_returnsNil() {
        sut.append(makeQueueItem())

        let removed = sut.remove(at: -1)

        XCTAssertNil(removed)
        XCTAssertEqual(sut.count, 1)
    }

    func testRemoveAtIndex_outOfBoundsIndex_returnsNil() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let removed = sut.remove(at: 10)

        XCTAssertNil(removed)
        XCTAssertEqual(sut.count, 3)
    }

    func testRemoveAtIndex_emptyQueue_returnsNil() {
        let removed = sut.remove(at: 0)

        XCTAssertNil(removed)
    }

    // MARK: - Move Tests

    func testMove_forwardInQueue() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        sut.move(from: 1, to: 4)

        // After moving item-1 from index 1 to index 4:
        // Original: [0, 1, 2, 3, 4]
        // Remove 1: [0, 2, 3, 4]
        // Insert at adjusted position: [0, 2, 3, 1, 4]
        XCTAssertEqual(sut.items[0].id, "item-0")
        XCTAssertEqual(sut.items[3].id, "item-1")
    }

    func testMove_backwardInQueue() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        sut.move(from: 4, to: 1)

        // After moving item-4 from index 4 to index 1:
        // Original: [0, 1, 2, 3, 4]
        // Remove 4: [0, 1, 2, 3]
        // Insert at 1: [0, 4, 1, 2, 3]
        XCTAssertEqual(sut.items[1].id, "item-4")
    }

    func testMove_samePosition() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 1, to: 1)

        XCTAssertEqual(sut.items[0].id, "item-0")
        XCTAssertEqual(sut.items[1].id, "item-1")
        XCTAssertEqual(sut.items[2].id, "item-2")
    }

    func testMove_toFirstPosition() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 2, to: 0)

        XCTAssertEqual(sut.items[0].id, "item-2")
        XCTAssertEqual(sut.items[1].id, "item-0")
        XCTAssertEqual(sut.items[2].id, "item-1")
    }

    func testMove_toLastPosition() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 0, to: 3)

        XCTAssertEqual(sut.items[0].id, "item-1")
        XCTAssertEqual(sut.items[1].id, "item-2")
        XCTAssertEqual(sut.items[2].id, "item-0")
    }

    func testMove_invalidSourceIndex_noChange() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 10, to: 1)

        XCTAssertEqual(sut.count, 3)
        XCTAssertEqual(sut.items[0].id, "item-0")
    }

    func testMove_negativeSourceIndex_noChange() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: -1, to: 1)

        XCTAssertEqual(sut.count, 3)
        XCTAssertEqual(sut.items[0].id, "item-0")
    }

    func testMove_destinationBeyondEnd_clampsToEnd() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 0, to: 100)

        XCTAssertEqual(sut.items[2].id, "item-0")
    }

    func testMove_negativeDestination_clampsToStart() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.move(from: 2, to: -5)

        XCTAssertEqual(sut.items[0].id, "item-2")
    }

    // MARK: - ReplaceAll Tests

    func testReplaceAll_replacesAllItems() {
        let oldItems = makeQueueItems(count: 3, prefix: "old")
        sut.append(contentsOf: oldItems)

        let newItems = makeQueueItems(count: 5, prefix: "new")
        sut.replaceAll(newItems)

        XCTAssertEqual(sut.count, 5)
        XCTAssertEqual(sut.items[0].id, "new-0")
        XCTAssertFalse(sut.items.contains { $0.id.hasPrefix("old") })
    }

    func testReplaceAll_withEmptyArray() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        sut.replaceAll([])

        XCTAssertTrue(sut.isEmpty)
    }

    func testReplaceAll_onEmptyQueue() {
        let newItems = makeQueueItems(count: 2)
        sut.replaceAll(newItems)

        XCTAssertEqual(sut.count, 2)
    }

    // MARK: - Clear Tests

    func testClear_removesAllItems() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        sut.clear()

        XCTAssertTrue(sut.isEmpty)
        XCTAssertEqual(sut.count, 0)
        XCTAssertNil(sut.peek())
    }

    func testClear_onEmptyQueue() {
        sut.clear()

        XCTAssertTrue(sut.isEmpty)
    }

    // MARK: - UpdateItem Tests

    func testUpdateItem_existingId_appliesTransform() {
        let item = makeQueueItem(id: "target", serverId: nil)
        sut.append(item)

        sut.updateItem(withId: "target") { existing in
            QueueItem(
                id: existing.id,
                serverId: "new-server-id",
                trackId: existing.trackId,
                track: existing.track,
                soundCloudTrack: existing.soundCloudTrack
            )
        }

        XCTAssertEqual(sut.items[0].serverId, "new-server-id")
    }

    func testUpdateItem_nonexistentId_noChange() {
        let item = makeQueueItem(id: "existing", serverId: nil)
        sut.append(item)

        sut.updateItem(withId: "nonexistent") { existing in
            QueueItem(
                id: existing.id,
                serverId: "changed",
                trackId: existing.trackId,
                track: existing.track,
                soundCloudTrack: existing.soundCloudTrack
            )
        }

        XCTAssertNil(sut.items[0].serverId)
    }

    func testUpdateItem_preservesPosition() {
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        sut.updateItem(withId: "item-2") { existing in
            QueueItem(
                id: existing.id,
                serverId: "updated-server",
                trackId: existing.trackId,
                track: existing.track,
                soundCloudTrack: existing.soundCloudTrack
            )
        }

        XCTAssertEqual(sut.items[2].serverId, "updated-server")
        XCTAssertEqual(sut.items[2].id, "item-2")
    }

    // MARK: - Reinsert (Rollback) Tests

    func testReinsert_atOriginalPosition() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)
        let removedItem = sut.remove(at: 1)!

        sut.reinsert(removedItem, at: 1)

        XCTAssertEqual(sut.count, 3)
        XCTAssertEqual(sut.items[1].id, "item-1")
    }

    func testReinsert_atStart() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)
        let newItem = makeQueueItem(id: "new-item")

        sut.reinsert(newItem, at: 0)

        XCTAssertEqual(sut.items[0].id, "new-item")
        XCTAssertEqual(sut.count, 4)
    }

    func testReinsert_atEnd() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)
        let newItem = makeQueueItem(id: "new-item")

        sut.reinsert(newItem, at: 3)

        XCTAssertEqual(sut.items[3].id, "new-item")
    }

    func testReinsert_beyondEnd_clampsToEnd() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)
        let newItem = makeQueueItem(id: "new-item")

        sut.reinsert(newItem, at: 100)

        XCTAssertEqual(sut.items.last?.id, "new-item")
    }

    func testReinsert_negativeIndex_clampsToStart() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)
        let newItem = makeQueueItem(id: "new-item")

        sut.reinsert(newItem, at: -5)

        XCTAssertEqual(sut.items.first?.id, "new-item")
    }

    func testReinsert_toEmptyQueue() {
        let item = makeQueueItem()

        sut.reinsert(item, at: 0)

        XCTAssertEqual(sut.count, 1)
    }

    // MARK: - IsEmpty and Count Tests

    func testIsEmpty_emptyQueue_true() {
        XCTAssertTrue(sut.isEmpty)
    }

    func testIsEmpty_nonEmptyQueue_false() {
        sut.append(makeQueueItem())

        XCTAssertFalse(sut.isEmpty)
    }

    func testCount_emptyQueue_zero() {
        XCTAssertEqual(sut.count, 0)
    }

    func testCount_afterOperations() {
        XCTAssertEqual(sut.count, 0)

        sut.append(makeQueueItem())
        XCTAssertEqual(sut.count, 1)

        sut.append(makeQueueItem())
        XCTAssertEqual(sut.count, 2)

        sut.pop()
        XCTAssertEqual(sut.count, 1)

        sut.clear()
        XCTAssertEqual(sut.count, 0)
    }

    // MARK: - Edge Cases

    func testQueueItem_emptyStrings() {
        let track = Track(id: "", title: "", artist: "", album: "", artwork: "", duration: 0)
        let item = QueueItem(id: "", serverId: "", trackId: "", track: track, soundCloudTrack: nil)

        XCTAssertEqual(item.id, "")
        XCTAssertEqual(item.serverId, "")
        XCTAssertEqual(item.trackId, "")
    }

    func testQueueItem_specialCharacters() {
        let track = Track(id: "id-\u{1F600}", title: "Track with unicode", artist: "Artist")
        let item = QueueItem(
            id: "queue-\u{1F3B5}",
            serverId: "server/id#123",
            trackId: "track@test.com",
            track: track,
            soundCloudTrack: nil
        )

        XCTAssertEqual(item.id, "queue-\u{1F3B5}")
        XCTAssertEqual(item.serverId, "server/id#123")
        XCTAssertEqual(item.trackId, "track@test.com")
    }

    func testOperationSequence_complex() {
        // Complex sequence of operations
        let items = makeQueueItems(count: 5)
        sut.append(contentsOf: items)

        // Insert at front
        sut.insertNext(makeQueueItem(id: "front"))
        XCTAssertEqual(sut.items[0].id, "front")

        // Pop front
        let popped = sut.pop()
        XCTAssertEqual(popped?.id, "front")

        // Remove middle
        sut.remove(at: 2)

        // Move
        sut.move(from: 0, to: 3)

        // Update
        sut.updateItem(withId: "item-1") { existing in
            QueueItem(
                id: existing.id,
                serverId: "updated",
                trackId: existing.trackId,
                track: existing.track,
                soundCloudTrack: existing.soundCloudTrack
            )
        }

        XCTAssertEqual(sut.count, 4)
    }

    func testStressTest_largeQueue() {
        let items = makeQueueItems(count: 100)
        sut.append(contentsOf: items)

        XCTAssertEqual(sut.count, 100)
        XCTAssertEqual(sut.items[0].id, "item-0")
        XCTAssertEqual(sut.items[99].id, "item-99")
        XCTAssertTrue(sut.contains(trackId: "track-item-50"))
        XCTAssertEqual(sut.index(ofTrackId: "track-item-75"), 75)
    }

    func testStressTest_manyOperations() {
        // Perform many sequential operations
        for i in 0..<50 {
            sut.append(makeQueueItem(id: "item-\(i)"))
        }

        for _ in 0..<25 {
            sut.pop()
        }

        sut.insertNext(makeQueueItem(id: "inserted"))

        XCTAssertEqual(sut.count, 26)
        XCTAssertEqual(sut.items[0].id, "inserted")
    }

    // MARK: - Sendable Conformance Tests

    func testQueueItem_sendable() async {
        let item = makeQueueItem()

        // Verify QueueItem can be sent across actor boundaries
        let receivedItem = await Task.detached {
            return item
        }.value

        XCTAssertEqual(receivedItem.id, item.id)
    }

    // MARK: - Items Property Access Tests

    func testItems_returnsCorrectArray() {
        let items = makeQueueItems(count: 3)
        sut.append(contentsOf: items)

        let retrieved = sut.items

        XCTAssertEqual(retrieved.count, 3)
        XCTAssertEqual(retrieved[0].id, "item-0")
        XCTAssertEqual(retrieved[1].id, "item-1")
        XCTAssertEqual(retrieved[2].id, "item-2")
    }

    func testItems_emptyQueue_returnsEmptyArray() {
        XCTAssertTrue(sut.items.isEmpty)
    }

    // MARK: - Integration with TestFixtures

    func testQueueItem_withSoundCloudTrackFromFixtures() {
        let scTrack = TestFixtures.sampleTrack
        let track = scTrack.toTrack()
        let item = QueueItem(
            id: "queue-\(scTrack.id)",
            serverId: nil,
            trackId: String(scTrack.id),
            track: track,
            soundCloudTrack: scTrack
        )

        sut.append(item)

        XCTAssertEqual(sut.count, 1)
        XCTAssertEqual(sut.peek()?.trackId, String(scTrack.id))
        XCTAssertNotNil(sut.soundCloudTrack(at: 0))
    }

    func testQueueWithMultipleSoundCloudTracks() {
        let tracks = TestFixtures.makeTracks(count: 5)
        let queueItems = tracks.enumerated().map { index, scTrack in
            QueueItem(
                id: "queue-\(index)",
                serverId: nil,
                trackId: String(scTrack.id),
                track: scTrack.toTrack(),
                soundCloudTrack: scTrack
            )
        }

        sut.append(contentsOf: queueItems)

        XCTAssertEqual(sut.count, 5)
        for i in 0..<5 {
            XCTAssertNotNil(sut.soundCloudTrack(at: i))
        }
    }
}
