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
    func observeDatabase() async {
        let observation = ValueObservation.trackingConstantRegion { db in
            try PersistedPlaylist
                .order(PersistedPlaylist.Columns.lastUpdated.desc)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await persistedPlaylists in observation {
                // Convert to display Playlist models
                self.playlists = persistedPlaylists.map { $0.toPlaylist() }
                self.error = nil
            }
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
            try await playlistSync.syncPlaylistTracks(userId: userId, playlistId: playlistId)
        } catch {
            logError(.sync, "Failed to preload playlist tracks: \(error)")
        }
    }
}
