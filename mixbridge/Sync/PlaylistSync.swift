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

            // 2. Convert and save to DB
            try await db.writer.write { db in
                for scPlaylist in scPlaylists {
                    var persisted = PersistedPlaylist(from: scPlaylist)
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
            // 1. Fetch tracks from API
            let scTracks = try await convex.getPlaylistTracks(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: forceRefresh
            )

            // 2. Save tracks and junction records
            try await db.writer.write { db in
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
            try PersistedTrack
                .joining(required: PersistedTrack.playlistTracks
                    .filter(PlaylistTrack.Columns.playlistId == playlistId))
                .order(PlaylistTrack.Columns.position)
                .fetchAll(db)
        }
    }
}
