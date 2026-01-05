//
//  PlaybackQueue.swift
//  mixbridge
//
//  The upcoming tracks queue. Current track is NEVER in this queue.
//  All operations are synchronous on local state for immediate UI feedback.
//  Backend sync happens asynchronously with rollback on failure.
//

import Foundation

/// A queue item with both display data and Convex ID for backend sync
struct QueueItem: Identifiable, Equatable {
    /// Stable local identifier (UUID for optimistic inserts; Convex id for synced rows).
    let id: String

    /// Convex `queueTracks._id` (nil until the optimistic insert is synced).
    let serverId: String?
    let trackId: String         // SoundCloud track ID
    let track: Track
    let soundCloudTrack: SoundCloudTrack?

    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// The upcoming tracks queue.
/// Invariant: The currently playing track is NEVER in this queue.
/// Next track is always peek() - no index arithmetic needed.
@Observable
@MainActor
final class PlaybackQueue {

    /// The queue items - upcoming tracks only
    private(set) var items: [QueueItem] = []

    // MARK: - Query

    /// What's next? Always index 0.
    func peek() -> QueueItem? {
        items.first
    }

    /// Is queue empty?
    var isEmpty: Bool { items.isEmpty }

    /// Number of items in queue
    var count: Int { items.count }

    /// Check if a track is in the queue by track ID
    func contains(trackId: String) -> Bool {
        items.contains { $0.trackId == trackId }
    }

    /// Get item by track ID
    func item(forTrackId trackId: String) -> QueueItem? {
        items.first { $0.trackId == trackId }
    }

    /// Get index of item by track ID
    func index(ofTrackId trackId: String) -> Int? {
        items.firstIndex { $0.trackId == trackId }
    }

    /// Get track at index (for carousel)
    func track(at index: Int) -> Track? {
        guard items.indices.contains(index) else { return nil }
        return items[index].track
    }

    /// Get SoundCloud track at index
    func soundCloudTrack(at index: Int) -> SoundCloudTrack? {
        guard items.indices.contains(index) else { return nil }
        return items[index].soundCloudTrack
    }

    // MARK: - Mutations (Synchronous Local State)

    /// Remove and return the next item (pop from front)
    @discardableResult
    func pop() -> QueueItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    /// Remove item by Convex ID
    @discardableResult
    func remove(id: String) -> QueueItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Remove item by track ID
    @discardableResult
    func remove(trackId: String) -> QueueItem? {
        guard let index = items.firstIndex(where: { $0.trackId == trackId }) else { return nil }
        return items.remove(at: index)
    }

    /// Remove item at index
    @discardableResult
    func remove(at index: Int) -> QueueItem? {
        guard items.indices.contains(index) else { return nil }
        return items.remove(at: index)
    }

    /// Insert at front (play next)
    func insertNext(_ item: QueueItem) {
        items.insert(item, at: 0)
    }

    /// Append to end
    func append(_ item: QueueItem) {
        items.append(item)
    }

    /// Append multiple items
    func append(contentsOf newItems: [QueueItem]) {
        items.append(contentsOf: newItems)
    }

    /// Move item from one position to another
    func move(from sourceIndex: Int, to destinationIndex: Int) {
        guard items.indices.contains(sourceIndex) else { return }
        let adjustedDestination = min(max(0, destinationIndex), items.count)
        let item = items.remove(at: sourceIndex)
        let insertIndex = sourceIndex < adjustedDestination ? adjustedDestination - 1 : adjustedDestination
        items.insert(item, at: min(insertIndex, items.count))
    }

    /// Replace all items
    func replaceAll(_ newItems: [QueueItem]) {
        items = newItems
    }

    /// Update a single item in-place (used for server ID reconciliation).
    func updateItem(withId id: String, transform: (QueueItem) -> QueueItem) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = transform(items[index])
    }

    /// Clear all items
    func clear() {
        items.removeAll()
    }

    // MARK: - Rollback Support

    /// Re-insert an item at a specific position (for rollback)
    func reinsert(_ item: QueueItem, at index: Int) {
        let safeIndex = min(max(0, index), items.count)
        items.insert(item, at: safeIndex)
    }
}
