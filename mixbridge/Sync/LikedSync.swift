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

            // 2. Save to DB
            try await db.writer.write { db in
                // Get current liked track IDs
                let currentLikedIds = try LikedTrack.fetchAll(db).map(\.trackId)
                let newLikedIds = Set(scTracks.map { String($0.id) })

                // Remove tracks no longer liked
                for trackId in currentLikedIds where !newLikedIds.contains(trackId) {
                    try LikedTrack.deleteOne(db, key: trackId)
                }

                // Add/update liked tracks
                let now = Date()
                for scTrack in scTracks {
                    // Save track
                    var track = PersistedTrack(from: scTrack)
                    try track.upsert(db)

                    // Save liked junction
                    var likedTrack = LikedTrack(
                        trackId: String(scTrack.id),
                        likedAt: now
                    )
                    try likedTrack.upsert(db)
                }
            }

            logInfo(.sync, "Synced \(scTracks.count) liked tracks")
        }
    }

    // MARK: - Optimistic Like/Unlike

    /// Like a track with optimistic update and rollback on failure
    func likeTrack(_ scTrack: SoundCloudTrack) async throws {
        let trackId = String(scTrack.id)
        let now = Date()

        // 1. Optimistic update
        try await db.writer.write { db in
            // Save track
            var track = PersistedTrack(from: scTrack)
            try track.upsert(db)

            // Add to liked
            var likedTrack = LikedTrack(trackId: trackId, likedAt: now)
            try likedTrack.upsert(db)
        }

        // 2. Sync to backend
        do {
            try await convex.likeTrack(trackId: trackId)
        } catch {
            // 3. Rollback on failure
            try await db.writer.write { db in
                try LikedTrack.deleteOne(db, key: trackId)
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
            try LikedTrack.deleteOne(db, key: trackId)
        }

        // 3. Sync to backend
        do {
            try await convex.unlikeTrack(trackId: trackId)
        } catch {
            // 4. Rollback on failure
            if let likedTrack = existingLikedTrack {
                try await db.writer.write { db in
                    var restored = likedTrack
                    try restored.insert(db)
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
