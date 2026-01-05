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

            // 2. Load existing rows so we can avoid rewriting unchanged playlists (prevents UI churn).
            let playlistIds = scPlaylists.map { String($0.id) }
            let existingById: [String: PersistedPlaylist] = try await db.reader.read { db in
                let rows = try PersistedPlaylist
                    .filter(playlistIds.contains(PersistedPlaylist.Columns.id))
                    .fetchAll(db)
                return rows.reduce(into: [:]) { $0[$1.id] = $1 }
            }

            // 3. Prepare DB payload on MainActor (SoundCloud models are main-actor isolated in this project).
            let prepared = await MainActor.run { () -> (persistedPlaylists: [PersistedPlaylist], newPlaylistIds: Set<String>, cachedOwner: String) in
                let persistedPlaylists = scPlaylists.map { scPlaylist in
                    var persisted = PersistedPlaylist(from: scPlaylist)
                    persisted.libraryOwnerUserId = userId

                    if let existing = existingById[persisted.id] {
                        // Preserve stable timestamps so Library ordering doesn't reshuffle every sync.
                        persisted.createdAt = existing.createdAt
                        persisted.lastUpdated = existing.lastUpdated
                    }

                    return persisted
                }

                let newPlaylistIds = Set(playlistIds)
                return (persistedPlaylists, newPlaylistIds, SyncConstants.cachedPlaylistOwner)
            }

            // 4. Sync to DB (add/update + remove deleted)
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

                // Remove playlists no longer in backend (unfollowed/deleted)
                for playlistId in currentLocalIds where !prepared.newPlaylistIds.contains(playlistId) {
                    // Keep the cached playlist row, but remove it from the user's Library scope.
                    // This prevents cached/search playlists from disappearing while still updating the Library UI.
                    try PersistedPlaylist
                        .filter(PersistedPlaylist.Columns.id == playlistId)
                        .updateAll(db, PersistedPlaylist.Columns.libraryOwnerUserId.set(to: prepared.cachedOwner))
                }

                // Add/update playlists
                for persisted in prepared.persistedPlaylists {
                    if let existing = existingById[persisted.id], existing == persisted {
                        continue
                    }
                    try persisted.upsert(db)
                }
            }

            await MainActor.run {
                logInfo(.sync, "Synced \(scPlaylists.count) playlists")
            }
        }
    }

    // MARK: - Sync Playlist Tracks

    /// Fetch tracks for a specific playlist and save to local database
    func syncPlaylistTracks(
        userId: String,
        playlistId: String,
        forceRefresh: Bool = false,
        updatePlaylistRow: Bool = true
    ) async throws {
        try await operationQueue.run { [self] in
            // 1. Fetch playlist (including tracks) from API
            let scPlaylist = try await convex.getPlaylist(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: forceRefresh
            )
            let scTracks = scPlaylist.tracks ?? []

            // 2. Prepare DB payload on MainActor (SoundCloud models are main-actor isolated in this project).
            let now = Date()
            let cachedOwner = await MainActor.run { SyncConstants.cachedPlaylistOwner }
            let prepared = await MainActor.run { () -> (playlist: PersistedPlaylist, tracks: [PreparedPlaylistTrack], trackCount: Int) in
                let playlist = PersistedPlaylist(from: scPlaylist)
                let tracks = scTracks.enumerated().map { index, scTrack in
                    PreparedPlaylistTrack(
                        track: PersistedTrack(from: scTrack),
                        junction: PlaylistTrack(
                            playlistId: playlistId,
                            trackId: String(scTrack.id),
                            position: index,
                            addedAt: now
                        )
                    )
                }
                return (playlist, tracks, scTracks.count)
            }

            // 3. Save tracks and junction records
            try await db.writer.write { db in
                if updatePlaylistRow {
                    // Ensure playlist exists locally so the junction table's foreign key is satisfied.
                    // Preserve Library scoping if this playlist is already part of the user's library.
                    let existing = try PersistedPlaylist.fetchOne(db, key: playlistId)
                    var persisted = prepared.playlist
                    persisted.libraryOwnerUserId = existing?.libraryOwnerUserId ?? cachedOwner
                    // Avoid reordering the Library UI during background/preload syncs:
                    // keep the existing playlist timestamps stable when updating tracks.
                    if let existing {
                        persisted.createdAt = existing.createdAt
                        persisted.lastUpdated = existing.lastUpdated
                    }
                    try persisted.upsert(db)
                } else {
                    // Preload path: avoid touching playlists table to prevent Library UI churn.
                    // Ensure the playlist exists for foreign key integrity (library playlists already do).
                    if try PersistedPlaylist.fetchOne(db, key: playlistId) == nil {
                        var persisted = prepared.playlist
                        persisted.libraryOwnerUserId = cachedOwner
                        try persisted.insert(db)
                    }
                }

                // Clear existing junction records for this playlist
                try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .deleteAll(db)

                for item in prepared.tracks {
                    try item.track.upsert(db)
                    try item.junction.insert(db)
                }

                // Update playlist track count
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.id == playlistId)
                    .updateAll(db, PersistedPlaylist.Columns.trackCount.set(to: prepared.trackCount))
            }

            await MainActor.run {
                logInfo(.sync, "Synced \(prepared.trackCount) tracks for playlist \(playlistId)")
            }
        }
    }

    private struct PreparedPlaylistTrack: Sendable {
        let track: PersistedTrack
        let junction: PlaylistTrack
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
