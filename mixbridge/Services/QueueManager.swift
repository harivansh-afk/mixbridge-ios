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

    var queueTracks: [Track] = []
    private(set) var isLoading = false
    private var queueTrackIds: [String: String] = [:] // Track.id -> Convex queue track ID

    private init() {}

    // MARK: - Queue Operations

    /// Check if a track is already in the queue
    func isInQueue(_ trackId: String) -> Bool {
        return queueTracks.contains(where: { $0.id == trackId })
    }

    /// Add track to queue with optimistic update
    func addTrack(_ track: Track, rawData: [String: Any]) async throws {
        print("🎵 [QueueManager] Adding track: \(track.title)")

        // Check for duplicates
        if isInQueue(track.id) {
            print("⚠️ [QueueManager] Track already in queue")
            throw ConvexError.alreadyInQueue
        }

        // Call API (not optimistic - wait for server response to get queue track ID)
        do {
            let queueTrackId = try await ConvexService.shared.addTrackToQueue(
                trackId: track.id,
                trackData: rawData
            )

            // Update state after successful API call
            queueTracks.append(track)
            queueTrackIds[track.id] = queueTrackId

            print("✅ [QueueManager] Track added successfully")
            print("✅ [QueueManager] Queue now has \(queueTracks.count) tracks")
            print("✅ [QueueManager] Stored mapping: \(track.id) -> \(queueTrackId)")
        } catch ConvexError.alreadyInQueue {
            print("ℹ️ [QueueManager] Track already in queue (409)")
            throw ConvexError.alreadyInQueue
        } catch {
            print("❌ [QueueManager] Failed to add track: \(error)")
            throw error
        }
    }

    /// Remove track from queue with optimistic update
    func removeTrack(_ track: Track) async throws {
        guard let convexQueueTrackId = queueTrackIds[track.id] else {
            print("❌ [QueueManager] No queue track ID found for: \(track.id)")
            throw ConvexError.notFound
        }

        print("🗑️ [QueueManager] Removing track: \(track.title)")

        // Store original state for rollback
        let removedTrack = track
        let originalIndex = queueTracks.firstIndex(where: { $0.id == track.id })

        // 1. Optimistically remove from UI - INSTANT
        queueTracks.removeAll { $0.id == track.id }
        queueTrackIds.removeValue(forKey: track.id)
        print("⚡ [QueueManager] Optimistically removed - queue now has \(queueTracks.count) tracks")

        // 2. Call API in background
        do {
            try await ConvexService.shared.removeTrackFromQueue(queueTrackId: convexQueueTrackId)
            print("✅ [QueueManager] Track deleted from server successfully")
        } catch {
            print("❌ [QueueManager] Failed to delete from server: \(error)")

            // Rollback: re-insert track at original position
            if let index = originalIndex {
                queueTracks.insert(removedTrack, at: min(index, queueTracks.count))
                queueTrackIds[track.id] = convexQueueTrackId
                print("↩️ [QueueManager] Rolled back delete")
            }
            throw error
        }
    }

    /// Load queue from server
    func loadQueue(userId: String) async throws {
        print("🔄 [QueueManager] Loading queue for userId: \(userId)")
        isLoading = true

        do {
            let queueData = try await ConvexService.shared.getQueueTracks(userId: userId)

            var tracks: [Track] = []
            var trackIdMap: [String: String] = [:]

            for queueTrack in queueData {
                let artworkUrl = queueTrack.artworkUrl ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                let track = Track(
                    id: queueTrack.trackId,
                    title: queueTrack.title,
                    artist: queueTrack.artist,
                    album: "",
                    artwork: highQualityArtwork,
                    duration: queueTrack.duration
                )

                tracks.append(track)
                trackIdMap[queueTrack.trackId] = queueTrack._id
            }

            self.queueTracks = tracks
            self.queueTrackIds = trackIdMap

            print("✅ [QueueManager] Loaded \(queueTracks.count) queue tracks")
        } catch {
            print("❌ [QueueManager] Failed to load queue: \(error)")
            throw error
        }

        isLoading = false
    }

    /// Clear entire queue
    func clearQueue() {
        queueTracks.removeAll()
        queueTrackIds.removeAll()
        print("🗑️ [QueueManager] Queue cleared")
    }
}
