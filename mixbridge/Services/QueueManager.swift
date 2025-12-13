//
//  QueueManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
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

    private var prefetchTask: Task<Void, Never>?

    var queueTracks: [Track] = [] {
        didSet {
            prefetchTask?.cancel()
            prefetchTask = Task {
                try? await Task.sleep(for: .milliseconds(100))  // Debounce rapid changes
                guard !Task.isCancelled else { return }
                await TrackPrefetcher.shared.prefetchForQueue(queueTracks, currentIndex: 0)
                PlaybackCoordinator.shared.prefetchQueue()
            }
        }
    }
    private(set) var isLoading = false
    private var queueTrackIds: [String: String] = [:]  // Track.id -> Convex queue track ID
    private var soundCloudTracks: [String: SoundCloudTrack] = [:]  // Track.id -> SoundCloud data

    /// Check if queue has any tracks
    var hasQueue: Bool { !queueTracks.isEmpty }

    private init() {}

    // MARK: - Queue Operations

    /// Check if a track is already in the queue
    func isInQueue(_ trackId: String) -> Bool {
        queueTracks.contains { $0.id == trackId }
    }

    /// Add track to queue
    func addTrack(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        if isInQueue(track.id) {
            throw ConvexError.alreadyInQueue
        }

        do {
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
            }

            queueTracks.append(track)
            queueTrackIds[track.id] = queueTrackId
            soundCloudTracks[track.id] = soundCloudTrack

            HapticManager.success()

        } catch ConvexError.alreadyInQueue {
            throw ConvexError.alreadyInQueue
        }
    }

    /// Insert track as "next up" (right after currently playing track)
    func insertTrackNext(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
        if isInQueue(track.id) {
            throw ConvexError.alreadyInQueue
        }

        // Add track to queue first (appends to end)
        let queueTrackId = try await BackgroundExecutor.run {
            try await ConvexService.shared.addTrackToQueue(track: soundCloudTrack)
        }

        // Calculate the target position (after current track)
        let currentIndex = PlayerState.shared.currentQueueIndex
        let targetIndex = max(0, currentIndex) + 1
        let fromIndex = queueTracks.count // It was appended at the end

        // Update local state first (optimistic)
        queueTracks.append(track)
        queueTrackIds[track.id] = queueTrackId
        soundCloudTracks[track.id] = soundCloudTrack

        // Move to target position if needed
        if fromIndex != targetIndex && targetIndex < queueTracks.count {
            // Move in local array
            let movedTrack = queueTracks.remove(at: fromIndex)
            queueTracks.insert(movedTrack, at: targetIndex)

            // Sync reorder to backend
            try await BackgroundExecutor.run {
                try await ConvexService.shared.reorderQueue(fromIndex: fromIndex, toIndex: targetIndex)
            }
        }

        HapticManager.success()
    }

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track) async throws {
        guard let convexQueueTrackId = queueTrackIds[track.id] else {
            throw ConvexError.notFound
        }

        let removedTrack = track
        let originalIndex = queueTracks.firstIndex { $0.id == track.id }
        let removedSoundCloudTrack = soundCloudTracks[track.id]

        // Optimistically remove from UI (SwiftUI List handles animation)
        queueTracks.removeAll { $0.id == track.id }
        queueTrackIds.removeValue(forKey: track.id)
        soundCloudTracks.removeValue(forKey: track.id)

        HapticManager.warning()

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: convexQueueTrackId)
            }
        } catch {
            // Rollback on failure
            if let index = originalIndex {
                queueTracks.insert(removedTrack, at: min(index, queueTracks.count))
                queueTrackIds[track.id] = convexQueueTrackId
                if let scTrack = removedSoundCloudTrack {
                    soundCloudTracks[track.id] = scTrack
                }
            }
            throw error
        }
    }

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        isLoading = true
        defer { isLoading = false }  // Always reset, even on error

        let queueData = try await BackgroundExecutor.run {
            try await ConvexService.shared.getQueueTracks(userId: userId)
        }

        var tracks: [Track] = []
        var trackIdMap: [String: String] = [:]
        var scTracks: [String: SoundCloudTrack] = [:]

        let orderedTracks = queueData.sorted { $0.position < $1.position }

        for queueTrack in orderedTracks {
            let track = queueTrack.trackData.toTrack()
            tracks.append(track)
            trackIdMap[queueTrack.trackId] = queueTrack._id
            scTracks[queueTrack.trackId] = queueTrack.trackData
        }

        self.queueTracks = tracks
        self.queueTrackIds = trackIdMap
        self.soundCloudTracks = scTracks

        // Trigger prefetching after queue loads
        PlaybackCoordinator.shared.prefetchQueue()
    }

    /// Clear entire queue (local only)
    func clearQueue() {
        queueTracks.removeAll()
        queueTrackIds.removeAll()
        soundCloudTracks.removeAll()
    }

    /// Clear entire queue with backend sync
    func clearQueueWithSync() async throws {
        // Clear backend first
        try await BackgroundExecutor.run {
            try await ConvexService.shared.clearQueue()
        }

        // Clear local state
        queueTracks.removeAll()
        queueTrackIds.removeAll()
        soundCloudTracks.removeAll()

        HapticManager.warning()
    }

    /// Replace entire queue with new tracks (synced to backend)
    /// - Parameters:
    ///   - items: Array of TrackItems to set as the new queue
    ///   - startIndex: Index in items array to start from (default 0)
    func setQueue(items: [TrackItem], startIndex: Int = 0) async throws {
        guard !items.isEmpty else { return }

        // Get tracks from startIndex onwards
        let tracksToSet = Array(items.suffix(from: min(startIndex, items.count)))
        guard !tracksToSet.isEmpty else { return }

        // Extract SoundCloud tracks (filter out items without soundCloudTrack)
        let soundCloudTracksToSet = tracksToSet.compactMap { $0.soundCloudTrack }
        guard !soundCloudTracksToSet.isEmpty else { return }

        // Sync to backend
        try await BackgroundExecutor.run {
            try await ConvexService.shared.setQueue(tracks: soundCloudTracksToSet)
        }

        // Update local state
        var tracks: [Track] = []
        var scTracks: [String: SoundCloudTrack] = [:]

        for item in tracksToSet {
            tracks.append(item.track)
            scTracks[item.track.id] = item.soundCloudTrack
        }

        self.queueTracks = tracks
        self.queueTrackIds = [:] // Will be populated on next loadQueue
        self.soundCloudTracks = scTracks

        HapticManager.success()
    }

    /// Append multiple tracks to end of queue (synced to backend)
    /// - Parameter items: Array of TrackItems to append
    func appendTracks(_ items: [TrackItem]) async throws {
        guard !items.isEmpty else { return }

        // Filter out tracks already in queue
        let newItems = items.filter { !isInQueue($0.track.id) }
        guard !newItems.isEmpty else { return }

        // Extract SoundCloud tracks
        let soundCloudTracksToAdd = newItems.compactMap { $0.soundCloudTrack }
        guard !soundCloudTracksToAdd.isEmpty else { return }

        // Sync to backend
        try await BackgroundExecutor.run {
            try await ConvexService.shared.addTracksToQueueBatch(tracks: soundCloudTracksToAdd)
        }

        // Update local state
        for item in newItems {
            queueTracks.append(item.track)
            soundCloudTracks[item.track.id] = item.soundCloudTrack
        }

        HapticManager.success()
    }

    // MARK: - Helpers

    func soundCloudTrack(for trackId: String) -> SoundCloudTrack? {
        soundCloudTracks[trackId]
    }

    func indexOfTrack(withId trackId: String) -> Int? {
        queueTracks.firstIndex { $0.id == trackId }
    }

    func nextTrack(after index: Int) -> (track: Track, index: Int)? {
        let nextIndex = index + 1
        guard queueTracks.indices.contains(nextIndex) else { return nil }
        return (queueTracks[nextIndex], nextIndex)
    }

    func previousTrack(before index: Int) -> (track: Track, index: Int)? {
        let previousIndex = index - 1
        guard queueTracks.indices.contains(previousIndex) else { return nil }
        return (queueTracks[previousIndex], previousIndex)
    }

    /// Check if track is in queue and return its position info
    /// Used to sync player state with queue when playing from external sources
    func queuePosition(for trackId: String) -> (index: Int, hasNext: Bool, hasPrevious: Bool)? {
        guard let index = queueTracks.firstIndex(where: { $0.id == trackId }) else {
            return nil
        }
        return (
            index: index,
            hasNext: index < queueTracks.count - 1,
            hasPrevious: index > 0
        )
    }

    /// Returns true if the track at the given index can navigate forward
    func canPlayNext(from index: Int) -> Bool {
        return queueTracks.indices.contains(index + 1)
    }

    /// Returns true if the track at the given index can navigate backward
    func canPlayPrevious(from index: Int) -> Bool {
        return queueTracks.indices.contains(index - 1)
    }
}
