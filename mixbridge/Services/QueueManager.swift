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

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track) async throws {
        guard let convexQueueTrackId = queueTrackIds[track.id] else {
            throw ConvexError.notFound
        }

        let removedTrack = track
        let originalIndex = queueTracks.firstIndex { $0.id == track.id }
        let removedSoundCloudTrack = soundCloudTracks[track.id]

        // Optimistically remove from UI
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

    /// Clear entire queue
    func clearQueue() {
        queueTracks.removeAll()
        queueTrackIds.removeAll()
        soundCloudTracks.removeAll()
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
}
