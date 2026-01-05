//
//  PlaylistSync.swift
//  mixbridge
//
//  Synchronizes playlists between Convex backend and local GRDB database.
//

import Foundation
import MixBridgeDB

final class PlaylistSync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = PlaylistSync()
    private init() {}

    // MARK: - Sync Playlists

    /// Fetch all playlists from Convex and save to local database
    func syncPlaylists(userId: String, forceRefresh: Bool = false) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch from API
            let scPlaylists = try await convex.getPlaylists(userId: userId, forceRefresh: forceRefresh)

            // 2. Sync to DB (add/update + remove deleted)
            try await db.writer.write { db in
                // Backfill legacy databases (pre-v2) where playlists were already local-first but not scoped.
                // At this point, only library playlists existed; cached playlists use a sentinel and won't match NULL.
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == nil)
                    .updateAll(db, PersistedPlaylist.Columns.libraryOwnerUserId.set(to: userId))

                // Get current local playlist IDs
                let currentLocalIds = try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                    .fetchAll(db)
                    .map(\.id)
                let newPlaylistIds = Set(scPlaylists.map { String($0.id) })

                // Remove playlists no longer in backend (unfollowed/deleted)
                for playlistId in currentLocalIds where !newPlaylistIds.contains(playlistId) {
                    // Keep the cached playlist row, but remove it from the user's Library scope.
                    // This prevents cached/search playlists from disappearing while still updating the Library UI.
                    try PersistedPlaylist
                        .filter(PersistedPlaylist.Columns.id == playlistId)
                        .updateAll(db, PersistedPlaylist.Columns.libraryOwnerUserId.set(to: SyncConstants.cachedPlaylistOwner))
                }

                // Add/update playlists
                for scPlaylist in scPlaylists {
                    var persisted = PersistedPlaylist(from: scPlaylist)
                    persisted.libraryOwnerUserId = userId
                    try persisted.upsert(db)
                }
            }

            logInfo(.sync, "Synced \(scPlaylists.count) playlists")
        }
    }

    // MARK: - Sync Playlist Tracks

    /// Fetch tracks for a specific playlist and save to local database
    func syncPlaylistTracks(userId: String, playlistId: String, forceRefresh: Bool = false) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch playlist (including tracks) from API
            let scPlaylist = try await convex.getPlaylist(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: forceRefresh
            )
            let scTracks = scPlaylist.tracks ?? []

            // 2. Save tracks and junction records
            try await db.writer.write { db in
                // Ensure playlist exists locally so the junction table's foreign key is satisfied.
                // Preserve Library scoping if this playlist is already part of the user's library.
                let existing = try PersistedPlaylist.fetchOne(db, key: playlistId)
                var persisted = PersistedPlaylist(from: scPlaylist)
                persisted.libraryOwnerUserId = existing?.libraryOwnerUserId ?? SyncConstants.cachedPlaylistOwner
                try persisted.upsert(db)

                // Clear existing junction records for this playlist
                try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .deleteAll(db)

                let now = Date()

                for (index, scTrack) in scTracks.enumerated() {
                    // Save track
                    var track = PersistedTrack(from: scTrack)
                    try track.upsert(db)

                    // Create junction record with position
                    var junction = PlaylistTrack(
                        playlistId: playlistId,
                        trackId: String(scTrack.id),
                        position: index,
                        addedAt: now
                    )
                    try junction.insert(db)
                }

                // Update playlist track count
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.id == playlistId)
                    .updateAll(db, PersistedPlaylist.Columns.trackCount.set(to: scTracks.count))
            }

            logInfo(.sync, "Synced \(scTracks.count) tracks for playlist \(playlistId)")
        }
    }

    // MARK: - Local Queries

    /// Get all playlists from local database
    func getLocalPlaylists() async throws -> [PersistedPlaylist] {
        try await db.reader.read { db in
            try PersistedPlaylist
                .order(PersistedPlaylist.Columns.lastUpdated.desc)
                .fetchAll(db)
        }
    }

    /// Get tracks for a playlist from local database
    func getLocalPlaylistTracks(playlistId: String) async throws -> [PersistedTrack] {
        try await db.reader.read { db in
            // Fetch tracks via the junction table, ordered by position
            let playlistTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position)
                .fetchAll(db)

            let trackIds = playlistTracks.map(\.trackId)
            let tracksDict = try PersistedTrack
                .filter(trackIds.contains(PersistedTrack.Columns.id))
                .fetchAll(db)
                .reduce(into: [String: PersistedTrack]()) { $0[$1.id] = $1 }

            return trackIds.compactMap { tracksDict[$0] }
        }
    }
}
