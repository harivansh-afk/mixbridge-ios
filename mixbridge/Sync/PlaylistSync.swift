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
                        // Preserve local modifications (custom name, hidden status)
                        persisted.customName = existing.customName
                        persisted.isHiddenFromLibrary = existing.isHiddenFromLibrary
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

                // Get current local SoundCloud playlist IDs (exclude user-created and hidden playlists)
                let soundCloudPlaylistIds = try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                    .filter(PersistedPlaylist.Columns.isUserCreated == false)
                    .filter(PersistedPlaylist.Columns.isHiddenFromLibrary == false)
                    .fetchAll(db)
                    .map(\.id)

                // Remove SoundCloud playlists no longer in backend (unfollowed/deleted)
                // User-created playlists are preserved since they don't come from SoundCloud
                // Hidden playlists are already excluded and won't be affected
                for playlistId in soundCloudPlaylistIds where !prepared.newPlaylistIds.contains(playlistId) {
                    try PersistedPlaylist
                        .filter(PersistedPlaylist.Columns.id == playlistId)
                        .updateAll(db, PersistedPlaylist.Columns.libraryOwnerUserId.set(to: prepared.cachedOwner))
                }

                // Add/update playlists (skip hidden ones to avoid re-adding them)
                for persisted in prepared.persistedPlaylists {
                    // Skip if hidden - don't re-add removed playlists
                    if persisted.isHiddenFromLibrary {
                        continue
                    }
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
        updatePlaylistRow: Bool = false
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

                // Update playlist track count only when explicitly updating playlist metadata.
                // Otherwise, avoid touching the playlists table (prevents Library cover churn).
                if updatePlaylistRow {
                    try PersistedPlaylist
                        .filter(PersistedPlaylist.Columns.id == playlistId)
                        .updateAll(db, PersistedPlaylist.Columns.trackCount.set(to: prepared.trackCount))
                }
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

    // MARK: - User-Created Playlists

    /// Create a new user playlist locally and sync to Convex
    func createUserPlaylist(userId: String, name: String, description: String? = nil) async throws -> String {
        let playlistId = UUID().uuidString
        let now = Date()
        print("🎵 [PlaylistSync] Creating playlist: \(name) with id: \(playlistId)")

        let playlist = PersistedPlaylist(
            id: playlistId,
            name: name,
            creator: "You",
            creatorId: 0,
            artwork: "",
            trackCount: 0,
            duration: 0,
            description: description,
            createdAt: now,
            lastUpdated: now,
            libraryOwnerUserId: userId,
            isUserCreated: true
        )

        do {
            try await db.writer.write { db in
                try playlist.insert(db)
            }
            print("🎵 [PlaylistSync] Successfully inserted playlist into DB")
        } catch {
            print("🎵 [PlaylistSync] DB insert failed: \(error)")
            throw error
        }

        Task {
            do {
                try await convex.createCustomPlaylist(
                    userId: userId,
                    playlistId: playlistId,
                    name: name,
                    description: description
                )
                print("🎵 [PlaylistSync] Convex sync successful")
            } catch {
                print("🎵 [PlaylistSync] Convex sync failed: \(error)")
            }
        }

        logInfo(.sync, "Created user playlist: \(name)")
        return playlistId
    }

    /// Create a new user playlist with tracks atomically (Apple Music-style flow)
    /// Ensures no empty playlists are created - artwork inherits from first track unless custom artwork is provided
    func createUserPlaylistWithTracks(
        userId: String,
        name: String,
        description: String? = nil,
        tracks: [PersistedTrack],
        sourcePlaylistId: String? = nil,
        customArtworkData: Data? = nil
    ) async throws -> String {
        guard !tracks.isEmpty else {
            throw PlaylistSyncError.emptyPlaylistNotAllowed
        }

        let playlistId = UUID().uuidString
        let now = Date()
        let firstTrackArtwork = tracks.first?.artwork ?? ""
        let totalDuration = tracks.reduce(0) { $0 + Int($1.duration * 1000) }

        logInfo(.sync, "Creating playlist '\(name)' with \(tracks.count) tracks")

        let playlist = PersistedPlaylist(
            id: playlistId,
            name: name,
            creator: "You",
            creatorId: 0,
            artwork: firstTrackArtwork,
            trackCount: tracks.count,
            duration: totalDuration,
            description: description,
            createdAt: now,
            lastUpdated: now,
            libraryOwnerUserId: userId,
            isUserCreated: true,
            sourcePlaylistId: sourcePlaylistId,
            customArtworkData: customArtworkData
        )
        
        try await db.writer.write { db in
            try playlist.insert(db)
            
            for (index, track) in tracks.enumerated() {
                try track.upsert(db)
                
                let junction = PlaylistTrack(
                    playlistId: playlistId,
                    trackId: track.id,
                    position: index,
                    addedAt: now
                )
                try junction.insert(db)
            }
        }
        
        Task {
            do {
                try await convex.createCustomPlaylist(
                    userId: userId,
                    playlistId: playlistId,
                    name: name,
                    description: description
                )
                
                for track in tracks {
                    try await convex.addTrackToCustomPlaylist(
                        userId: userId,
                        playlistId: playlistId,
                        track: track
                    )
                }
                logInfo(.sync, "Synced playlist '\(name)' with \(tracks.count) tracks to Convex")
            } catch {
                logError(.sync, "Failed to sync playlist to Convex: \(error)")
            }
        }
        
        return playlistId
    }
    
    /// Delete a user-created playlist
    func deleteUserPlaylist(userId: String, playlistId: String) async throws {
        try await db.writer.write { db in
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .deleteAll(db)
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .deleteAll(db)
        }

        Task {
            try? await convex.deleteCustomPlaylist(userId: userId, playlistId: playlistId)
        }

        logInfo(.sync, "Deleted user playlist: \(playlistId)")
    }

    /// Rename a user-created playlist
    func renameUserPlaylist(userId: String, playlistId: String, name: String) async throws {
        _ = try await db.writer.write { db in
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.name.set(to: name),
                    PersistedPlaylist.Columns.lastUpdated.set(to: Date())
                )
        }

        do {
            try await convex.renameCustomPlaylist(userId: userId, playlistId: playlistId, name: name)
        } catch {
            logError(.sync, "Failed to sync playlist rename to Convex: \(error)")
        }

        logInfo(.sync, "Renamed user playlist \(playlistId) to: \(name)")
    }

    /// Update custom artwork for a user-created playlist
    func updateUserPlaylistArtwork(playlistId: String, customArtworkData: Data?) async throws {
        _ = try await db.writer.write { db in
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.customArtworkData.set(to: customArtworkData),
                    PersistedPlaylist.Columns.lastUpdated.set(to: Date())
                )
        }

        logInfo(.sync, "Updated custom artwork for playlist \(playlistId)")
    }

    /// Rename a SoundCloud playlist (syncs to Convex for sharing)
    /// Uses customName to preserve original name and survive syncs
    func renameSoundCloudPlaylist(userId: String, playlistId: String, name: String) async throws {
        _ = try await db.writer.write { db in
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.customName.set(to: name),
                    PersistedPlaylist.Columns.lastUpdated.set(to: Date())
                )
        }

        do {
            try await convex.setSoundCloudPlaylistCustomName(userId: userId, playlistId: playlistId, customName: name)
        } catch {
            logError(.sync, "Failed to sync SoundCloud playlist rename to Convex: \(error)")
        }

        logInfo(.sync, "Renamed SoundCloud playlist \(playlistId) to: \(name)")
    }

    /// Remove a SoundCloud playlist from the user's library (syncs to Convex)
    /// Uses isHiddenFromLibrary flag to survive syncs
    func removeSoundCloudPlaylistFromLibrary(userId: String, playlistId: String) async throws {
        _ = try await db.writer.write { db in
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db, PersistedPlaylist.Columns.isHiddenFromLibrary.set(to: true))
        }

        Task {
            try? await convex.setSoundCloudPlaylistHidden(userId: userId, playlistId: playlistId, isHidden: true)
        }

        logInfo(.sync, "Removed SoundCloud playlist \(playlistId) from library")
    }

    /// Add a track to a user-created playlist
    func addTrackToUserPlaylist(userId: String, playlistId: String, track: PersistedTrack) async throws {
        let now = Date()

        try await db.writer.write { db in
            try track.upsert(db)

            let currentCount = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .fetchCount(db)

            let junction = PlaylistTrack(
                playlistId: playlistId,
                trackId: track.id,
                position: currentCount,
                addedAt: now
            )
            try junction.insert(db)

            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.trackCount.set(to: currentCount + 1),
                    PersistedPlaylist.Columns.lastUpdated.set(to: now)
                )

            if currentCount == 0 {
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.id == playlistId)
                    .updateAll(db, PersistedPlaylist.Columns.artwork.set(to: track.artwork))
            }
        }

        do {
            try await convex.addTrackToCustomPlaylist(
                userId: userId,
                playlistId: playlistId,
                track: track
            )
        } catch {
            logError(.sync, "Failed to sync track addition to Convex: \(error)")
        }

        logInfo(.sync, "Added track \(track.id) to playlist \(playlistId)")
    }

    /// Add a track to a SoundCloud playlist (persisted across syncs)
    /// This stores the track in a separate table that gets merged during playlist fetch
    func addTrackToSoundCloudPlaylist(
        userId: String,
        playlistId: String,
        track: PersistedTrack,
        soundCloudTrack: SoundCloudTrack
    ) async throws {
        let now = Date()

        // Store locally in the junction table for immediate display
        try await db.writer.write { db in
            try track.upsert(db)

            // Check if already exists
            let existing = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == track.id)
                .fetchOne(db)

            if existing == nil {
                let currentCount = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .fetchCount(db)

                let junction = PlaylistTrack(
                    playlistId: playlistId,
                    trackId: track.id,
                    position: currentCount,
                    addedAt: now
                )
                try junction.insert(db)

                // Update playlist track count
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.id == playlistId)
                    .updateAll(db,
                        PersistedPlaylist.Columns.trackCount.set(to: currentCount + 1),
                        PersistedPlaylist.Columns.lastUpdated.set(to: now)
                    )
            }
        }

        // Sync to Convex (stored in playlistUserTracks table)
        // This must complete before returning to ensure the track persists across syncs
        try await convex.addTrackToSoundCloudPlaylist(
            userId: userId,
            playlistId: playlistId,
            track: soundCloudTrack
        )

        logInfo(.sync, "Added track \(track.id) to SoundCloud playlist \(playlistId)")
    }

    /// Remove a track from a user-created playlist
    func removeTrackFromUserPlaylist(userId: String, playlistId: String, trackId: String) async throws {
        try await db.writer.write { db in
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .deleteAll(db)

            let remainingTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position)
                .fetchAll(db)

            for (index, var track) in remainingTracks.enumerated() {
                track.position = index
                try track.update(db)
            }

            let newCount = remainingTracks.count
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.trackCount.set(to: newCount),
                    PersistedPlaylist.Columns.lastUpdated.set(to: Date())
                )
        }

        do {
            try await convex.removeTrackFromCustomPlaylist(
                userId: userId,
                playlistId: playlistId,
                trackId: trackId
            )
        } catch {
            logError(.sync, "Failed to sync track removal to Convex: \(error)")
        }

        logInfo(.sync, "Removed track \(trackId) from playlist \(playlistId)")
    }

    /// Remove a user-added track from a SoundCloud playlist
    func removeTrackFromSoundCloudPlaylist(userId: String, playlistId: String, trackId: String) async throws {
        try await db.writer.write { db in
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .filter(PlaylistTrack.Columns.trackId == trackId)
                .deleteAll(db)

            let remainingTracks = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId)
                .order(PlaylistTrack.Columns.position)
                .fetchAll(db)

            for (index, var track) in remainingTracks.enumerated() {
                track.position = index
                try track.update(db)
            }

            let newCount = remainingTracks.count
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .updateAll(db,
                    PersistedPlaylist.Columns.trackCount.set(to: newCount),
                    PersistedPlaylist.Columns.lastUpdated.set(to: Date())
                )
        }

        do {
            try await convex.removeTrackFromSoundCloudPlaylist(
                userId: userId,
                playlistId: playlistId,
                trackId: trackId
            )
        } catch {
            logError(.sync, "Failed to sync SoundCloud track removal to Convex: \(error)")
        }

        logInfo(.sync, "Removed track \(trackId) from SoundCloud playlist \(playlistId)")
    }

    /// Sync user-created playlists from Convex
    func syncUserPlaylists(userId: String) async throws {
        let remotePlaylists = try await convex.getCustomPlaylists(userId: userId)

        try await db.writer.write { db in
            for remote in remotePlaylists {
                let existing = try PersistedPlaylist.fetchOne(db, key: remote.playlistId)
                if existing == nil {
                    let playlist = PersistedPlaylist(
                        id: remote.playlistId,
                        name: remote.name,
                        creator: "You",
                        creatorId: 0,
                        artwork: remote.artwork ?? "",
                        trackCount: remote.trackIds.count,
                        description: remote.description,
                        createdAt: Date(timeIntervalSince1970: Double(remote.createdAt) / 1000),
                        lastUpdated: Date(timeIntervalSince1970: Double(remote.updatedAt) / 1000),
                        libraryOwnerUserId: userId,
                        isUserCreated: true
                    )
                    try playlist.insert(db)
                }
            }
        }

        logInfo(.sync, "Synced \(remotePlaylists.count) user playlists from Convex")
    }
}

// MARK: - Errors

enum PlaylistSyncError: LocalizedError {
    case emptyPlaylistNotAllowed
    
    var errorDescription: String? {
        switch self {
        case .emptyPlaylistNotAllowed:
            return "Playlists must contain at least one track"
        }
    }
}
