//
//  QueueManager.swift
//  mixbridge
//
//  Centralized queue state management.
//  Single source of truth for queue operations across the entire app.
//
//  Core invariant: The currently playing track is NEVER in the queue.
//  Next track is always queue.peek() - no index arithmetic needed.
//

import Foundation
import SwiftUI

/// Centralized queue state management
/// Single source of truth for queue operations across the entire app
@Observable
@MainActor
class QueueManager {
    static let shared = QueueManager()

    // MARK: - State

    /// The upcoming tracks queue
    let queue = PlaybackQueue()

    /// SoundCloud metadata cache (trackId -> SoundCloudTrack)
    private var soundCloudTracks: [String: SoundCloudTrack] = [:]

    private(set) var isLoading = false
    private var prefetchTask: Task<Void, Never>?

    /// Check if queue has any tracks
    var hasQueue: Bool { !queue.isEmpty }

    /// Direct access to queue items for UI binding
    var queueTracks: [Track] {
        queue.items.map { $0.track }
    }

    private init() {
        logInfo(.queue, "QueueManager initialized")
    }

    // MARK: - Queue Change Notification

    /// Called internally after queue mutations to notify playback system
    private func notifyQueueChanged() {
        logDebug(.queue, "notifyQueueChanged: count=\(queue.count), peek=\(queue.peek()?.track.title ?? "nil")")
        prefetchTask?.cancel()
        prefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(100))  // Debounce rapid changes
            guard !Task.isCancelled else { return }
            logDebug(.queue, "notifyQueueChanged: triggering handleQueueChanged + prefetch")
            PlaybackCoordinator.shared.handleQueueChanged()
            await TrackPrefetcher.shared.prefetchForQueue(queueTracks, currentIndex: 0)
            PlaybackCoordinator.shared.prefetchQueue()
        }
    }

    /// Log current queue state for debugging
    private func logQueueState(_ context: String) {
        let titles = queue.items.prefix(5).map { $0.track.title }
        let more = queue.count > 5 ? "... +\(queue.count - 5) more" : ""
        logDebug(.queue, "\(context) | count=\(queue.count) | items=[\(titles.joined(separator: ", "))\(more)]")
    }

    // MARK: - Query Operations

    /// Check if a track is in the queue
    func isInQueue(_ trackId: String) -> Bool {
        queue.contains(trackId: trackId)
    }

    /// Get SoundCloud track data for a track ID
    func soundCloudTrack(for trackId: String) -> SoundCloudTrack? {
        soundCloudTracks[trackId]
    }

    /// Get index of track in queue
    func indexOfTrack(withId trackId: String) -> Int? {
        queue.index(ofTrackId: trackId)
    }

    /// Get next track after given index
    func nextTrack(after index: Int) -> (track: Track, index: Int)? {
        let nextIndex = index + 1
        guard let track = queue.track(at: nextIndex) else { return nil }
        return (track, nextIndex)
    }

    /// Get previous track before given index
    func previousTrack(before index: Int) -> (track: Track, index: Int)? {
        let previousIndex = index - 1
        guard let track = queue.track(at: previousIndex) else { return nil }
        return (track, previousIndex)
    }

    /// Check if track at given index can navigate forward
    func canPlayNext(from index: Int) -> Bool {
        queue.track(at: index + 1) != nil
    }

    /// Check if track at given index can navigate backward
    func canPlayPrevious(from index: Int) -> Bool {
        queue.track(at: index - 1) != nil
    }

    /// Get queue position info for a track
    func queuePosition(for trackId: String) -> (index: Int, hasNext: Bool, hasPrevious: Bool)? {
        guard let index = queue.index(ofTrackId: trackId) else { return nil }
        return (
            index: index,
            hasNext: index < queue.count - 1,
            hasPrevious: index > 0
        )
    }

    // MARK: - Pop Operation (for playback)

    /// Pop the next track from queue (called when track starts playing)
    /// Returns the item that was removed, or nil if queue empty
    @discardableResult
    func popNext() -> QueueItem? {
        logQueueState("popNext BEFORE")

        guard let item = queue.pop() else {
            logWarning(.queue, "popNext: queue was EMPTY, returning nil")
            return nil
        }

        logInfo(.queue, "popNext: popped '\(item.track.title)' (id=\(item.id), trackId=\(item.trackId))")
        logQueueState("popNext AFTER")
        notifyQueueChanged()

        // Sync removal to backend (fire-and-forget with logging)
        Task {
            do {
                logDebug(.queue, "popNext: syncing removal to Convex for id=\(item.id)")
                try await BackgroundExecutor.run {
                    try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
                }
                logDebug(.queue, "popNext: Convex removal SUCCESS for id=\(item.id)")
            } catch {
                logWarning(.queue, "popNext: Convex removal FAILED for id=\(item.id): \(error)")
                // Don't rollback - track already played
            }
        }

        return item
    }

    // MARK: - Add Operations

    /// Add track to queue
    func addTrack(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        logInfo(.queue, "addTrack: '\(track.title)' (trackId=\(track.id))")

        if isInQueue(track.id) {
            logWarning(.queue, "addTrack: track already in queue, throwing alreadyInQueue")
            throw ConvexError.alreadyInQueue
        }

        do {
            logDebug(.queue, "addTrack: calling Convex addTrackToQueue")
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
            }
            logDebug(.queue, "addTrack: Convex returned queueTrackId=\(queueTrackId)")

            let item = QueueItem(
                id: queueTrackId,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )
            queue.append(item)
            soundCloudTracks[track.id] = soundCloudTrack
            logQueueState("addTrack AFTER")
            notifyQueueChanged()

            HapticManager.success()

        } catch ConvexError.alreadyInQueue {
            logWarning(.queue, "addTrack: Convex returned alreadyInQueue")
            throw ConvexError.alreadyInQueue
        }
    }

    /// Insert track as "next up" (right after currently playing)
    func insertTrackNext(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        logInfo(.queue, "insertTrackNext: '\(track.title)' (trackId=\(track.id))")
        logQueueState("insertTrackNext BEFORE")

        if let existingItem = queue.item(forTrackId: track.id) {
            // Track already in queue - move it to front
            guard queue.index(ofTrackId: track.id) != 0 else {
                logDebug(.queue, "insertTrackNext: track already at front, no-op")
                HapticManager.success()
                return  // Already at front
            }

            let fromIndex = queue.index(ofTrackId: track.id)!
            logDebug(.queue, "insertTrackNext: moving existing track from index \(fromIndex) to front")
            queue.remove(trackId: track.id)
            queue.insertNext(existingItem)
            logQueueState("insertTrackNext AFTER move")
            notifyQueueChanged()

            // Sync reorder to backend
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: 0)
            }
            logDebug(.queue, "insertTrackNext: Convex reorder SUCCESS")

            HapticManager.success()
        } else {
            // Track not in queue - add to Convex then move to front
            logDebug(.queue, "insertTrackNext: track not in queue, adding to Convex")
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
            }
            logDebug(.queue, "insertTrackNext: Convex returned queueTrackId=\(queueTrackId)")

            let item = QueueItem(
                id: queueTrackId,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )

            // Add to front locally
            queue.insertNext(item)
            soundCloudTracks[track.id] = soundCloudTrack
            logQueueState("insertTrackNext AFTER insert")
            notifyQueueChanged()

            // If there are other items, reorder on backend (we added at end, need to move to front)
            if queue.count > 1 {
                let fromIndex = queue.count - 1  // Was added at end by Convex
                logDebug(.queue, "insertTrackNext: reordering on backend from \(fromIndex) to 0")
                try await BackgroundExecutor.run {
                    try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: 0)
                }
            }

            HapticManager.success()
        }
    }

    // MARK: - Remove Operations

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track, silent: Bool = false) async throws {
        logInfo(.queue, "removeTrack: '\(track.title)' (trackId=\(track.id), silent=\(silent))")
        logQueueState("removeTrack BEFORE")

        guard let item = queue.item(forTrackId: track.id) else {
            logWarning(.queue, "removeTrack: track NOT FOUND in queue")
            throw ConvexError.notFound
        }

        let originalIndex = queue.index(ofTrackId: track.id)!
        let removedItem = queue.remove(trackId: track.id)!
        logInfo(.queue, "removeTrack: removed from index \(originalIndex), id=\(item.id)")
        logQueueState("removeTrack AFTER")
        notifyQueueChanged()

        if !silent {
            HapticManager.warning()
        }

        do {
            logDebug(.queue, "removeTrack: syncing to Convex")
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
            }
            logDebug(.queue, "removeTrack: Convex SUCCESS")
        } catch {
            // Rollback on failure
            logError(.queue, "removeTrack: Convex FAILED, rolling back: \(error)")
            queue.reinsert(removedItem, at: originalIndex)
            notifyQueueChanged()
            throw error
        }
    }

    /// Remove item at index - synchronous local mutation for instant UI feedback
    /// Returns the removed item for rollback, or nil if index invalid
    @discardableResult
    func removeAtLocal(index: Int, silent: Bool = false) -> QueueItem? {
        logInfo(.queue, "removeAtLocal: index=\(index), silent=\(silent)")
        logQueueState("removeAtLocal BEFORE")

        guard let item = queue.items[safe: index] else {
            logWarning(.queue, "removeAtLocal: index \(index) OUT OF BOUNDS")
            return nil
        }

        let removedItem = queue.remove(at: index)
        logInfo(.queue, "removeAtLocal: removed '\(removedItem?.track.title ?? "nil")' from index \(index)")
        logQueueState("removeAtLocal AFTER")
        notifyQueueChanged()

        if !silent {
            HapticManager.warning()
        }

        return removedItem
    }

    /// Sync a remove operation to backend (call after removeAtLocal)
    func syncRemoveToBackend(item: QueueItem, originalIndex: Int) async {
        logDebug(.queue, "syncRemoveToBackend: syncing to Convex id=\(item.id)")
        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
            }
            logDebug(.queue, "syncRemoveToBackend: Convex SUCCESS")
        } catch {
            // Rollback on failure
            logError(.queue, "syncRemoveToBackend: Convex FAILED, rolling back: \(error)")
            queue.reinsert(item, at: originalIndex)
            notifyQueueChanged()
            HapticManager.error()
        }
    }

    /// Remove item by QueueItem - synchronous local mutation
    @discardableResult
    func removeItemLocal(_ item: QueueItem, silent: Bool = false) -> Int? {
        logInfo(.queue, "removeItemLocal: item=\(item.track.title), silent=\(silent)")
        guard let index = queue.items.firstIndex(where: { $0.id == item.id }) else {
            logWarning(.queue, "removeItemLocal: item not found in queue")
            return nil
        }

        queue.remove(id: item.id)
        logInfo(.queue, "removeItemLocal: removed from index \(index)")
        notifyQueueChanged()

        if !silent {
            HapticManager.warning()
        }

        return index
    }

    // MARK: - Reorder Operations

    /// Move item in queue - synchronous local mutation for instant UI feedback
    /// Call syncMoveToBackend() after to persist
    func moveItemLocal(from sourceIndex: Int, to destinationIndex: Int) {
        guard queue.items.indices.contains(sourceIndex) else { return }
        guard sourceIndex != destinationIndex else { return }

        queue.move(from: sourceIndex, to: destinationIndex)
        notifyQueueChanged()
    }

    /// Sync a move operation to backend (call after moveItemLocal)
    func syncMoveToBackend(from sourceIndex: Int, to destinationIndex: Int) async {
        // Calculate actual destination for Convex (List.onMove destination adjusts)
        let toIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: sourceIndex, toIndex: toIndex)
            }
        } catch {
            logError(.queue, "Failed to sync move to backend: \(error)")
            // Rollback - move back
            let actualDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
            queue.move(from: actualDestination, to: sourceIndex)
            notifyQueueChanged()
            HapticManager.error()
        }
    }

    // MARK: - Batch Operations

    /// Replace entire queue with new tracks
    func setQueue(items: [TrackItem], startIndex: Int = 0) async throws {
        logInfo(.queue, "setQueue: \(items.count) items, startIndex=\(startIndex)")
        guard !items.isEmpty else {
            logDebug(.queue, "setQueue: empty items, returning")
            return
        }

        let tracksToSet = Array(items.suffix(from: min(startIndex, items.count)))
        guard !tracksToSet.isEmpty else {
            logDebug(.queue, "setQueue: no tracks after startIndex, returning")
            return
        }

        logDebug(.queue, "setQueue: setting \(tracksToSet.count) tracks")
        let soundCloudTracksToSet = tracksToSet.map { $0.soundCloudTrack }

        // Call Convex and get back the IDs
        logDebug(.queue, "setQueue: calling Convex setQueue")
        let results = try await BackgroundExecutor.run {
            try await ConvexService.shared.setQueue(tracks: soundCloudTracksToSet)
        }
        logDebug(.queue, "setQueue: Convex returned \(results.count) results")

        // Build queue items with IDs from Convex
        var newItems: [QueueItem] = []
        var newSoundCloudTracks: [String: SoundCloudTrack] = [:]

        for trackItem in tracksToSet {
            let scTrack = trackItem.soundCloudTrack

            // Find matching result by trackId
            let trackId = String(scTrack.id)
            let convexId = results.first { $0.trackId == trackId }?._id ?? trackId

            if results.first(where: { $0.trackId == trackId }) == nil {
                logWarning(.queue, "setQueue: no Convex ID found for trackId=\(trackId), using fallback")
            }

            let item = QueueItem(
                id: convexId,
                trackId: trackId,
                track: trackItem.track,
                soundCloudTrack: scTrack
            )
            newItems.append(item)
            newSoundCloudTracks[trackId] = scTrack
        }

        queue.replaceAll(newItems)
        soundCloudTracks = newSoundCloudTracks
        logQueueState("setQueue AFTER")
        notifyQueueChanged()

        HapticManager.success()
    }

    /// Append multiple tracks to end of queue
    func appendTracks(_ items: [TrackItem]) async throws {
        logInfo(.queue, "appendTracks: \(items.count) items")
        logQueueState("appendTracks BEFORE")

        guard !items.isEmpty else {
            logDebug(.queue, "appendTracks: empty items, returning")
            return
        }

        // Filter out tracks already in queue
        let newItems = items.filter { !isInQueue($0.track.id) }
        guard !newItems.isEmpty else {
            logDebug(.queue, "appendTracks: all tracks already in queue, returning")
            return
        }

        logDebug(.queue, "appendTracks: adding \(newItems.count) new tracks (filtered from \(items.count))")
        let soundCloudTracksToAdd = newItems.map { $0.soundCloudTrack }

        // Call Convex and get back the IDs
        logDebug(.queue, "appendTracks: calling Convex addTracksToQueueBatch")
        let results = try await BackgroundExecutor.run {
            try await ConvexService.shared.addTracksToQueueBatch(tracks: soundCloudTracksToAdd)
        }
        logDebug(.queue, "appendTracks: Convex returned \(results.count) results")

        // Build queue items with IDs from Convex
        for trackItem in newItems {
            let scTrack = trackItem.soundCloudTrack

            let trackId = String(scTrack.id)
            let convexId = results.first { $0.trackId == trackId }?._id ?? trackId

            if results.first(where: { $0.trackId == trackId }) == nil {
                logWarning(.queue, "appendTracks: no Convex ID found for trackId=\(trackId), using fallback")
            }

            let item = QueueItem(
                id: convexId,
                trackId: trackId,
                track: trackItem.track,
                soundCloudTrack: scTrack
            )
            queue.append(item)
            soundCloudTracks[trackId] = scTrack
        }

        logQueueState("appendTracks AFTER")
        notifyQueueChanged()
        HapticManager.success()
    }

    // MARK: - Load & Clear

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        logInfo(.queue, "loadQueue: userId=\(userId)")
        isLoading = true
        defer { isLoading = false }

        logDebug(.queue, "loadQueue: fetching from Convex")
        let queueData = try await BackgroundExecutor.run {
            try await ConvexService.shared.getQueueTracks(userId: userId)
        }
        logDebug(.queue, "loadQueue: Convex returned \(queueData.count) tracks")

        let orderedTracks = queueData.sorted { $0.position < $1.position }

        var newItems: [QueueItem] = []
        var newSoundCloudTracks: [String: SoundCloudTrack] = [:]

        for queueTrack in orderedTracks {
            let track = queueTrack.trackData.toTrack()
            let item = QueueItem(
                id: queueTrack._id,
                trackId: queueTrack.trackId,
                track: track,
                soundCloudTrack: queueTrack.trackData
            )
            newItems.append(item)
            newSoundCloudTracks[queueTrack.trackId] = queueTrack.trackData
            logDebug(.queue, "loadQueue: loaded '\(track.title)' id=\(queueTrack._id) pos=\(queueTrack.position)")
        }

        queue.replaceAll(newItems)
        soundCloudTracks = newSoundCloudTracks
        logQueueState("loadQueue COMPLETE")

        // Trigger prefetching after queue loads
        PlaybackCoordinator.shared.prefetchQueue()
    }

    /// Clear entire queue (local only)
    func clearQueue() {
        logInfo(.queue, "clearQueue (local only)")
        logQueueState("clearQueue BEFORE")
        queue.clear()
        soundCloudTracks.removeAll()
        logInfo(.queue, "clearQueue: queue cleared locally")
        notifyQueueChanged()
    }

    /// Clear entire queue with backend sync
    func clearQueueWithSync() async throws {
        logInfo(.queue, "clearQueueWithSync")
        logQueueState("clearQueueWithSync BEFORE")

        logDebug(.queue, "clearQueueWithSync: calling Convex clearQueue")
        try await BackgroundExecutor.run {
            try await ConvexService.shared.clearQueue()
        }
        logDebug(.queue, "clearQueueWithSync: Convex SUCCESS")

        queue.clear()
        soundCloudTracks.removeAll()
        logInfo(.queue, "clearQueueWithSync: queue cleared")
        notifyQueueChanged()

        HapticManager.warning()
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
