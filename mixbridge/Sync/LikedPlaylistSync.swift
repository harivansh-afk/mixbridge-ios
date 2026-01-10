//
//  LikedPlaylistSync.swift
//  mixbridge
//
//  Synchronizes liked playlists between Convex backend and local GRDB database.
//

import Foundation
import MixBridgeDB

final class LikedPlaylistSync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = LikedPlaylistSync()
    private init() {}

    // MARK: - Sync Liked Playlists from Backend

    /// Fetch liked playlists from Convex and save to local database
    func syncLikedPlaylists(userId: String, forceRefresh: Bool = false) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch from API
            let scPlaylists = try await convex.getLikedPlaylists(userId: userId, forceRefresh: forceRefresh)

            // 2. Prepare DB payload on MainActor (SoundCloud models are main-actor isolated in this project).
            // SoundCloud returns playlists ordered by most recently liked first.
            // Preserve this order by assigning decreasing timestamps.
            let now = Date()
            let cachedOwner = await MainActor.run { SyncConstants.cachedPlaylistOwner }
            let prepared = await MainActor.run { () -> (persistedPlaylists: [PersistedPlaylist], likedPlaylists: [LikedPlaylist], newLikedIds: Set<String>) in
                let persistedPlaylists = scPlaylists.map { scPlaylist in
                    var persisted = PersistedPlaylist(from: scPlaylist)
                    // Mark as cached playlist (not part of user's library)
                    persisted.libraryOwnerUserId = cachedOwner
                    return persisted
                }
                let likedPlaylists = scPlaylists.enumerated().map { index, playlist in
                    // Most recent (index 0) gets `now`, older playlists get earlier timestamps
                    let likedAt = now.addingTimeInterval(-Double(index))
                    return LikedPlaylist(playlistId: String(playlist.id), likedAt: likedAt)
                }
                let newLikedIds = Set(likedPlaylists.map(\.playlistId))
                return (persistedPlaylists, likedPlaylists, newLikedIds)
            }

            // 3. Save to DB
            try await db.writer.write { db in
                // Get current liked playlist IDs
                let currentLikedIds = try LikedPlaylist.fetchAll(db).map(\.playlistId)

                // Remove playlists no longer liked
                for playlistId in currentLikedIds where !prepared.newLikedIds.contains(playlistId) {
                    _ = try LikedPlaylist.deleteOne(db, key: playlistId)
                }

                // Add/update liked playlists
                for (playlist, likedPlaylist) in zip(prepared.persistedPlaylists, prepared.likedPlaylists) {
                    // Only upsert playlist if it doesn't exist or is a cache playlist
                    // Don't overwrite library playlists
                    let existing = try PersistedPlaylist.fetchOne(db, key: playlist.id)
                    if existing == nil || existing?.libraryOwnerUserId == cachedOwner {
                        try playlist.upsert(db)
                    }
                    try likedPlaylist.upsert(db)
                }
            }

            await MainActor.run {
                logInfo(.sync, "Synced \(scPlaylists.count) liked playlists")
            }
        }
    }

    // MARK: - Check Like Status

    /// Check if a playlist is liked locally
    func isPlaylistLiked(playlistId: String) async -> Bool {
        do {
            return try await db.reader.read { db in
                try LikedPlaylist.exists(db, key: playlistId)
            }
        } catch {
            return false
        }
    }

    // MARK: - Local Queries

    /// Get liked playlists from local database, ordered by most recently liked
    func getLocalLikedPlaylists() async throws -> [LikedPlaylistWithPlaylist] {
        try await db.reader.read { db in
            try LikedPlaylist
                .including(required: LikedPlaylist.playlist)
                .order(LikedPlaylist.Columns.likedAt.desc)
                .asRequest(of: LikedPlaylistWithPlaylist.self)
                .fetchAll(db)
        }
    }
}
