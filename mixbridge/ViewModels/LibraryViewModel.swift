//
//  LibraryViewModel.swift
//  mixbridge
//
//  ViewModel for LibraryView with GRDB ValueObservation.
//  Observes playlists from local database.
//

import Foundation
import MixBridgeDB

@Observable
@MainActor
final class LibraryViewModel {
    // MARK: - Observable State

    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    // MARK: - Dependencies

    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared

    // MARK: - Initialization

    init() {}

    // MARK: - Database Observation

    /// Start observing playlists from local database
    /// Call this from view's .task modifier
    func observeDatabase(userId: String) async {
        let observation = ValueObservation.tracking { db in
            try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                .order(PersistedPlaylist.Columns.lastUpdated.desc)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await persistedPlaylists in observation {
                // Convert to display Playlist models
                let next = persistedPlaylists.map { $0.toPlaylist() }
                if self.playlists != next {
                    self.playlists = next
                }
                self.error = nil
            }
        } catch is CancellationError {
            // Expected when the view disappears; don't surface as an error state.
        } catch {
            logError(.db, "Failed to observe playlists: \(error)")
            self.error = error
        }
    }

    // MARK: - Refresh from Network

    /// Refresh playlists from Convex backend
    /// Call this on pull-to-refresh or first appear
    func refresh(userId: String, forceRefresh: Bool = false) async {
        // Only show loading if truly empty (first install)
        isLoading = playlists.isEmpty

        do {
            try await playlistSync.syncPlaylists(userId: userId, forceRefresh: forceRefresh)
            error = nil
        } catch {
            logError(.sync, "Failed to sync playlists: \(error)")
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Preload Playlist Tracks

    /// Preload tracks for a playlist in background
    func preloadPlaylistTracks(userId: String, playlistId: String) async {
        do {
            // Check if this is a user-created playlist - skip preload for those
            let playlist = try await db.reader.read { db in
                try PersistedPlaylist.fetchOne(db, key: playlistId)
            }
            guard let playlist = playlist, !playlist.isUserCreated else { return }

            // If we already have any cached tracks, avoid re-syncing on every cell onAppear.
            let hasAnyLocalTracks = try await db.reader.read { db in
                try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId)
                    .limit(1)
                    .fetchCount(db) > 0
            }
            guard !hasAnyLocalTracks else { return }

            try await playlistSync.syncPlaylistTracks(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: false,
                updatePlaylistRow: false
            )
        } catch is CancellationError {
            // Ignore
        } catch {
            logError(.sync, "Failed to preload playlist tracks: \(error)")
        }
    }
}
