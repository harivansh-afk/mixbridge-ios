//
//  LikedSync.swift
//  mixbridge
//
//  Synchronizes liked tracks between Convex backend and local GRDB database.
//  Supports optimistic updates with rollback on failure.
//

import Foundation
import MixBridgeDB

final class LikedSync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = LikedSync()
    private init() {}

    // MARK: - Sync Liked Tracks from Backend

    /// Fetch liked tracks from Convex and save to local database
    func syncLikedTracks(userId: String, forceRefresh: Bool = false) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch from API
            let scTracks = try await convex.getLikedTracks(userId: userId, forceRefresh: forceRefresh)

            // 2. Prepare DB payload on MainActor (SoundCloud models are main-actor isolated in this project).
            let now = Date()
            let prepared = await MainActor.run { () -> (persistedTracks: [PersistedTrack], likedTracks: [LikedTrack], newLikedIds: Set<String>) in
                let persistedTracks = scTracks.map { PersistedTrack(from: $0) }
                let likedTracks = scTracks.map { LikedTrack(trackId: String($0.id), likedAt: now) }
                let newLikedIds = Set(likedTracks.map(\.trackId))
                return (persistedTracks, likedTracks, newLikedIds)
            }

            // 3. Save to DB
            try await db.writer.write { db in
                // Get current liked track IDs
                let currentLikedIds = try LikedTrack.fetchAll(db).map(\.trackId)

                // Remove tracks no longer liked
                for trackId in currentLikedIds where !prepared.newLikedIds.contains(trackId) {
                    _ = try LikedTrack.deleteOne(db, key: trackId)
                }

                // Add/update liked tracks
                for (track, likedTrack) in zip(prepared.persistedTracks, prepared.likedTracks) {
                    try track.upsert(db)
                    try likedTrack.upsert(db)
                }
            }

            await MainActor.run {
                logInfo(.sync, "Synced \(scTracks.count) liked tracks")
            }
        }
    }

    // MARK: - Optimistic Like/Unlike

    /// Like a track with optimistic update and rollback on failure
    func likeTrack(_ scTrack: SoundCloudTrack) async throws {
        let trackId = String(scTrack.id)
        let now = Date()
        let persistedTrack = await MainActor.run { PersistedTrack(from: scTrack) }
        let likedTrack = LikedTrack(trackId: trackId, likedAt: now)

        // 1. Optimistic update
        try await db.writer.write { db in
            // Save track
            try persistedTrack.upsert(db)
            try likedTrack.upsert(db)
        }

        // 2. Sync to backend
        do {
            try await convex.likeTrack(trackId: trackId)
        } catch {
            // 3. Rollback on failure
            try await db.writer.write { db in
                _ = try LikedTrack.deleteOne(db, key: trackId)
            }
            throw error
        }
    }

    /// Unlike a track with optimistic update and rollback on failure
    func unlikeTrack(trackId: String) async throws {
        // 1. Snapshot for rollback
        let existingLikedTrack = try await db.reader.read { db in
            try LikedTrack.fetchOne(db, key: trackId)
        }

        // 2. Optimistic delete
        try await db.writer.write { db in
            _ = try LikedTrack.deleteOne(db, key: trackId)
        }

        // 3. Sync to backend
        do {
            try await convex.unlikeTrack(trackId: trackId)
        } catch {
            // 4. Rollback on failure
            if let likedTrack = existingLikedTrack {
                try await db.writer.write { db in
                    try likedTrack.insert(db)
                }
            }
            throw error
        }
    }

    // MARK: - Check Like Status

    /// Check if a track is liked locally
    func isTrackLiked(trackId: String) async -> Bool {
        do {
            return try await db.reader.read { db in
                try LikedTrack.exists(db, key: trackId)
            }
        } catch {
            return false
        }
    }

    // MARK: - Local Queries

    /// Get liked tracks from local database, ordered by most recently liked
    func getLocalLikedTracks() async throws -> [LikedTrackWithTrack] {
        try await db.reader.read { db in
            try LikedTrack
                .including(required: LikedTrack.track)
                .order(LikedTrack.Columns.likedAt.desc)
                .asRequest(of: LikedTrackWithTrack.self)
                .fetchAll(db)
        }
    }
}
