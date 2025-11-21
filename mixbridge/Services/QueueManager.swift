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

    var queueTracks: [Track] = [] {
        didSet {
            // Prefetch artwork whenever queue changes
            Task {
                await TrackPrefetcher.shared.prefetchForQueue(queueTracks, currentIndex: 0)
            }
        }
    }
    private(set) var isLoading = false
    private var queueTrackIds: [String: String] = [:] // Track.id -> Convex queue track ID
    private var queueTrackData: [String: [String: Any]] = [:] // Track.id -> raw SoundCloud data

    private init() {}

    // MARK: - Queue Operations

    /// Check if a track is already in the queue
    func isInQueue(_ trackId: String) -> Bool {
        return queueTracks.contains(where: { $0.id == trackId })
    }

    /// Add track to queue with optimistic update
    func addTrack(_ track: Track, rawData: [String: Any]) async throws {
        // Check for duplicates
        if isInQueue(track.id) {
            throw ConvexError.alreadyInQueue
        }

        // Call API (not optimistic - wait for server response to get queue track ID)
        do {
            let queueTrackId = try await BackgroundExecutor.run {
                try await ConvexService.shared.addTrackToQueue(
                    trackId: track.id,
                    trackData: rawData
                )
            }

            // Update state after successful API call
            queueTracks.append(track)
            queueTrackIds[track.id] = queueTrackId
            queueTrackData[track.id] = rawData

            // Haptic feedback for success
            HapticManager.success()

        } catch ConvexError.alreadyInQueue {
            throw ConvexError.alreadyInQueue
        } catch {
            throw error
        }
    }

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track) async throws {
        guard let convexQueueTrackId = queueTrackIds[track.id] else {
            throw ConvexError.notFound
        }

        // Store original state for rollback
        let removedTrack = track
        let originalIndex = queueTracks.firstIndex(where: { $0.id == track.id })

        // 1. Optimistically remove from UI - INSTANT
        queueTracks.removeAll { $0.id == track.id }
        queueTrackIds.removeValue(forKey: track.id)
        queueTrackData.removeValue(forKey: track.id)

        // Haptic feedback for delete
        HapticManager.warning()

        // 2. Call API in background
        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.removeTrackFromQueue(queueTrackId: convexQueueTrackId)
            }
        } catch {
            // Rollback: re-insert track at original position
            if let index = originalIndex {
                queueTracks.insert(removedTrack, at: min(index, queueTracks.count))
                queueTrackIds[track.id] = convexQueueTrackId
            }
            throw error
        }
    }

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        isLoading = true

        do {
            let queueData = try await BackgroundExecutor.run {
                try await ConvexService.shared.getQueueTracks(userId: userId)
            }

            var tracks: [Track] = []
            var trackIdMap: [String: String] = [:]
            var rawDataMap: [String: [String: Any]] = [:]

            let orderedTracks = queueData.sorted { $0.position < $1.position }

            for queueTrack in orderedTracks {
                let artworkUrl = queueTrack.artworkUrl ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                let track = Track(
                    id: queueTrack.trackId,
                    title: queueTrack.title,
                    artist: queueTrack.artist,
                    album: "",
                    artwork: highQualityArtwork,
                    duration: queueTrack.duration / 1000.0 // Convert ms to seconds
                )

                tracks.append(track)
                trackIdMap[queueTrack.trackId] = queueTrack._id

                if let encodedData = try? JSONEncoder().encode(queueTrack.trackData),
                   let jsonObject = try? JSONSerialization.jsonObject(with: encodedData) as? [String: Any] {
                    rawDataMap[queueTrack.trackId] = jsonObject
                }
            }

            self.queueTracks = tracks
            self.queueTrackIds = trackIdMap
            self.queueTrackData = rawDataMap

        } catch {
            throw error
        }

        isLoading = false
    }

    /// Clear entire queue
    func clearQueue() {
        queueTracks.removeAll()
        queueTrackIds.removeAll()
        queueTrackData.removeAll()
    }

    // MARK: - Helpers

    func trackData(for trackId: String) -> [String: Any]? {
        queueTrackData[trackId]
    }

    func indexOfTrack(withId trackId: String) -> Int? {
        queueTracks.firstIndex(where: { $0.id == trackId })
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
