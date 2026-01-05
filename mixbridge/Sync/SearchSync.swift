//
//  SearchSync.swift
//  mixbridge
//
//  Local-first search:
//  - Reads cached results from local GRDB instantly
//  - Refreshes from Convex/SoundCloud in background
//  - Mirrors Convex `searchCache` fields (see mixbridge-web/convex/schema.ts)
//

import Foundation
import MixBridgeDB

final class SearchSync: Sendable {
    static let shared = SearchSync()

    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    /// Matches Convex search cache TTL (10 minutes).
    private let ttl: TimeInterval = 10 * 60

    private init() {}

    // MARK: - Local Cache

    func getLocalSearchResult(userId: String, query: String) async throws -> (result: SearchResult, updatedAt: Date)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cached: PersistedSearchCache? = try await db.reader.read { db in
            try PersistedSearchCache
                .filter(PersistedSearchCache.Columns.userId == userId)
                .filter(PersistedSearchCache.Columns.query == trimmed)
                .fetchOne(db)
        }

        guard let cached else { return nil }

        return await MainActor.run {
            do {
                let tracks = try JSONDecoder().decode([SoundCloudTrack].self, from: cached.tracksData)
                let playlists = try JSONDecoder().decode([SoundCloudPlaylist].self, from: cached.playlistsData)
                let users = try JSONDecoder().decode([SoundCloudUser].self, from: cached.usersData)
                return (SearchResult(tracks: tracks, playlists: playlists, users: users), cached.updatedAt)
            } catch {
                return nil
            }
        }
    }

    func isLocalCacheFresh(updatedAt: Date) -> Bool {
        Date().timeIntervalSince(updatedAt) < ttl
    }

    // MARK: - Refresh from Network

    /// Fetch from Convex and persist to local DB.
    /// Safe to call repeatedly; operations are serialized to avoid racey overwrites.
    func fetchAndStoreSearch(userId: String, query: String, limit: Int = 20, forceRefresh: Bool = false) async throws -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConvexError.noData }

        return try await operationQueue.run { [self] in
            let result = try await convex.search(
                userId: userId,
                query: trimmed,
                limit: limit,
                forceRefresh: forceRefresh
            )

            // Pre-encode/cache payloads on MainActor to avoid global-actor issues inside DB transactions.
            let payload = try await MainActor.run { () -> (tracks: Data, playlists: Data, users: Data, persistedTracks: [PersistedTrack], persistedPlaylists: [PersistedPlaylist]) in
                let encoder = JSONEncoder()
                let tracksData = try encoder.encode(result.tracks)
                let playlistsData = try encoder.encode(result.playlists)
                let usersData = try encoder.encode(result.users)

                let persistedTracks = result.tracks.map { PersistedTrack(from: $0) }
                let persistedPlaylists = result.playlists.map { PersistedPlaylist(from: $0) }

                return (tracksData, playlistsData, usersData, persistedTracks, persistedPlaylists)
            }

            try await db.writer.write { db in
                let cached = PersistedSearchCache(
                    userId: userId,
                    query: trimmed,
                    tracksData: payload.tracks,
                    playlistsData: payload.playlists,
                    usersData: payload.users,
                    updatedAt: Date()
                )
                try cached.upsert(db)

                // Persist tracks globally (safe: not directly listed in UI without joins).
                for persisted in payload.persistedTracks {
                    var persisted = persisted
                    try persisted.upsert(db)
                }

                // Persist playlists for offline PlaylistDetail access.
                // IMPORTANT: Preserve `libraryOwnerUserId` so cached playlists never appear in Library.
                for playlist in payload.persistedPlaylists {
                    let playlistId = playlist.id
                    let existing = try PersistedPlaylist.fetchOne(db, key: playlistId)
                    var persisted = playlist
                    persisted.libraryOwnerUserId = existing?.libraryOwnerUserId ?? SyncConstants.cachedPlaylistOwner
                    try persisted.upsert(db)
                }
            }

            return result
        }
    }
}
