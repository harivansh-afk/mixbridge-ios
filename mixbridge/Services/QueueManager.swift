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

    private init() {}

    // MARK: - Queue Change Notification

    /// Called internally after queue mutations to notify playback system
    private func notifyQueueChanged() {
        prefetchTask?.cancel()
        prefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(100))  // Debounce rapid changes
            guard !Task.isCancelled else { return }
            PlaybackCoordinator.shared.handleQueueChanged()
            await TrackPrefetcher.shared.prefetchForQueue(queueTracks, currentIndex: 0)
            PlaybackCoordinator.shared.prefetchQueue()
        }
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
        guard let item = queue.pop() else { return nil }
        notifyQueueChanged()

        // Sync removal to backend (fire-and-forget with logging)
        Task {
            do {
                try await BackgroundExecutor.run {
                    try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
                }
            } catch {
                logWarning("Failed to sync queue removal: \(error)")
                // Don't rollback - track already played
            }
        }

        return item
    }

    // MARK: - Add Operations

    /// Add track to queue
    func addTrack(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        if isInQueue(track.id) {
            throw ConvexError.alreadyInQueue
        }

        do {
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
            }

            let item = QueueItem(
                id: queueTrackId,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )
            queue.append(item)
            soundCloudTracks[track.id] = soundCloudTrack
            notifyQueueChanged()

            HapticManager.success()

        } catch ConvexError.alreadyInQueue {
            throw ConvexError.alreadyInQueue
        }
    }

    /// Insert track as "next up" (right after currently playing)
    func insertTrackNext(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        if let existingItem = queue.item(forTrackId: track.id) {
            // Track already in queue - move it to front
            guard queue.index(ofTrackId: track.id) != 0 else {
                HapticManager.success()
                return  // Already at front
            }

            let fromIndex = queue.index(ofTrackId: track.id)!
            queue.remove(trackId: track.id)
            queue.insertNext(existingItem)
            notifyQueueChanged()

            // Sync reorder to backend
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: 0)
            }

            HapticManager.success()
        } else {
            // Track not in queue - add to Convex then move to front
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
            }

            let item = QueueItem(
                id: queueTrackId,
                trackId: track.id,
                track: track,
                soundCloudTrack: soundCloudTrack
            )

            // Add to front locally
            queue.insertNext(item)
            soundCloudTracks[track.id] = soundCloudTrack
            notifyQueueChanged()

            // If there are other items, reorder on backend (we added at end, need to move to front)
            if queue.count > 1 {
                let fromIndex = queue.count - 1  // Was added at end by Convex
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
        guard let item = queue.item(forTrackId: track.id) else {
            throw ConvexError.notFound
        }

        let originalIndex = queue.index(ofTrackId: track.id)!
        let removedItem = queue.remove(trackId: track.id)!
        notifyQueueChanged()

        if !silent {
            HapticManager.warning()
        }

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
            }
        } catch {
            // Rollback on failure
            queue.reinsert(removedItem, at: originalIndex)
            notifyQueueChanged()
            throw error
        }
    }

    /// Remove item at specific index (for UI swipe-to-delete)
    func removeAt(index: Int, silent: Bool = false) async throws {
        guard let item = queue.items[safe: index] else {
            throw ConvexError.notFound
        }

        let removedItem = queue.remove(at: index)!
        notifyQueueChanged()

        if !silent {
            HapticManager.warning()
        }

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: item.id)
            }
        } catch {
            // Rollback on failure
            queue.reinsert(removedItem, at: index)
            notifyQueueChanged()
            throw error
        }
    }

    // MARK: - Reorder Operations

    /// Move item in queue (for UI drag-to-reorder)
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) async throws {
        guard queue.items.indices.contains(sourceIndex) else { return }
        guard sourceIndex != destinationIndex else { return }

        // Local move first (optimistic)
        queue.move(from: sourceIndex, to: destinationIndex)
        notifyQueueChanged()

        // Calculate actual destination for Convex (List.onMove destination adjusts)
        let toIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: sourceIndex, toIndex: toIndex)
            }
        } catch {
            // Rollback - move back
            let actualDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
            queue.move(from: actualDestination, to: sourceIndex)
            notifyQueueChanged()
            throw error
        }
    }

    // MARK: - Batch Operations

    /// Replace entire queue with new tracks
    func setQueue(items: [TrackItem], startIndex: Int = 0) async throws {
        guard !items.isEmpty else { return }

        let tracksToSet = Array(items.suffix(from: min(startIndex, items.count)))
        guard !tracksToSet.isEmpty else { return }

        let soundCloudTracksToSet = tracksToSet.map { $0.soundCloudTrack }

        // Call Convex and get back the IDs
        let results = try await BackgroundExecutor.run {
            try await ConvexService.shared.setQueue(tracks: soundCloudTracksToSet)
        }

        // Build queue items with IDs from Convex
        var newItems: [QueueItem] = []
        var newSoundCloudTracks: [String: SoundCloudTrack] = [:]

        for trackItem in tracksToSet {
            let scTrack = trackItem.soundCloudTrack

            // Find matching result by trackId
            let trackId = String(scTrack.id)
            let convexId = results.first { $0.trackId == trackId }?._id ?? trackId

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
        notifyQueueChanged()

        HapticManager.success()
    }

    /// Append multiple tracks to end of queue
    func appendTracks(_ items: [TrackItem]) async throws {
        guard !items.isEmpty else { return }

        // Filter out tracks already in queue
        let newItems = items.filter { !isInQueue($0.track.id) }
        guard !newItems.isEmpty else { return }

        let soundCloudTracksToAdd = newItems.map { $0.soundCloudTrack }

        // Call Convex and get back the IDs
        let results = try await BackgroundExecutor.run {
            try await ConvexService.shared.addTracksToQueueBatch(tracks: soundCloudTracksToAdd)
        }

        // Build queue items with IDs from Convex
        for trackItem in newItems {
            let scTrack = trackItem.soundCloudTrack

            let trackId = String(scTrack.id)
            let convexId = results.first { $0.trackId == trackId }?._id ?? trackId

            let item = QueueItem(
                id: convexId,
                trackId: trackId,
                track: trackItem.track,
                soundCloudTrack: scTrack
            )
            queue.append(item)
            soundCloudTracks[trackId] = scTrack
        }

        notifyQueueChanged()
        HapticManager.success()
    }

    // MARK: - Load & Clear

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let queueData = try await BackgroundExecutor.run {
            try await ConvexService.shared.getQueueTracks(userId: userId)
        }

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
        }

        queue.replaceAll(newItems)
        soundCloudTracks = newSoundCloudTracks

        // Trigger prefetching after queue loads
        PlaybackCoordinator.shared.prefetchQueue()
    }

    /// Clear entire queue (local only)
    func clearQueue() {
        queue.clear()
        soundCloudTracks.removeAll()
        notifyQueueChanged()
    }

    /// Clear entire queue with backend sync
    func clearQueueWithSync() async throws {
        try await BackgroundExecutor.run {
            try await ConvexService.shared.clearQueue()
        }

        queue.clear()
        soundCloudTracks.removeAll()
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
