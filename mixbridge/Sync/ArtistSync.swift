//
//  ArtistSync.swift
//  mixbridge
//
//  Local-first artist detail caching:
//  - Stores derived artist tracks/playlists in local GRDB
//  - Refreshes from Convex search in background
//

import Foundation
import MixBridgeDB

final class ArtistSync: Sendable {
    static let shared = ArtistSync()

    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    /// Artist pages can be cached longer than search; refresh opportunistically.
    private let ttl: TimeInterval = 24 * 60 * 60

    private init() {}

    // MARK: - Local Cache

    func getLocalArtistContent(userId: String, artistId: String) async throws -> (tracks: [SoundCloudTrack], playlists: [SoundCloudPlaylist], updatedAt: Date)? {
        let cached: PersistedArtistCache? = try await db.reader.read { db in
            try PersistedArtistCache
                .filter(PersistedArtistCache.Columns.userId == userId)
                .filter(PersistedArtistCache.Columns.artistId == artistId)
                .fetchOne(db)
        }

        guard let cached else { return nil }

        return await MainActor.run {
            do {
                let tracks = try JSONDecoder().decode([SoundCloudTrack].self, from: cached.tracksData)
                let playlists = try JSONDecoder().decode([SoundCloudPlaylist].self, from: cached.playlistsData)
                return (tracks, playlists, cached.updatedAt)
            } catch {
                return nil
            }
        }
    }

    func isLocalCacheFresh(updatedAt: Date) -> Bool {
        Date().timeIntervalSince(updatedAt) < ttl
    }

    // MARK: - Refresh from Network

    func fetchAndStoreArtistContent(
        userId: String,
        artistId: String,
        artistName: String,
        limit: Int = 50,
        forceRefresh: Bool = false
    ) async throws -> (tracks: [SoundCloudTrack], playlists: [SoundCloudPlaylist]) {
        try await operationQueue.run { [self] in
            let results = try await convex.search(
                userId: userId,
                query: artistName,
                limit: limit,
                forceRefresh: forceRefresh
            )

            let content = try await MainActor.run { () -> (tracks: [SoundCloudTrack], playlists: [SoundCloudPlaylist], tracksData: Data, playlistsData: Data, persistedTracks: [PersistedTrack], persistedPlaylists: [PersistedPlaylist], cachedOwner: String) in
                let numericArtistId = Int(artistId) ?? 0
                let tracks = results.tracks.filter { $0.user.id == numericArtistId }
                let playlists = results.playlists.filter { $0.user.id == numericArtistId }

                let encoder = JSONEncoder()
                let tracksData = try encoder.encode(tracks)
                let playlistsData = try encoder.encode(playlists)

                let persistedTracks = tracks.map { PersistedTrack(from: $0) }
                let persistedPlaylists = playlists.map { PersistedPlaylist(from: $0) }

                return (tracks, playlists, tracksData, playlistsData, persistedTracks, persistedPlaylists, SyncConstants.cachedPlaylistOwner)
            }

            try await db.writer.write { db in
                let cached = PersistedArtistCache(
                    userId: userId,
                    artistId: artistId,
                    artistName: artistName,
                    tracksData: content.tracksData,
                    playlistsData: content.playlistsData,
                    updatedAt: Date()
                )
                try cached.upsert(db)

                for persisted in content.persistedTracks {
                    try persisted.upsert(db)
                }

                for playlist in content.persistedPlaylists {
                    let playlistId = playlist.id
                    let existing = try PersistedPlaylist.fetchOne(db, key: playlistId)
                    var persisted = playlist
                    persisted.libraryOwnerUserId = existing?.libraryOwnerUserId ?? content.cachedOwner
                    try persisted.upsert(db)
                }
            }

            return (content.tracks, content.playlists)
        }
    }
}
