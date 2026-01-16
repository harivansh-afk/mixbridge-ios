//
//  PlaylistDetailViewModel.swift
//  mixbridge
//
//  ViewModel for PlaylistDetailView with GRDB ValueObservation.
//  Observes tracks for a specific playlist from local database.
//

import Foundation
import MixBridgeDB
import MixBridgeDomain

@Observable
@MainActor
final class PlaylistDetailViewModel {
    // MARK: - Observable State

    private(set) var trackItems: [TrackItem] = []
    private(set) var trackRows: [IndexedRow<TrackItem>] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var hasAttemptedLoad = false
    private(set) var playlist: Playlist?

    // MARK: - Configuration

    let playlistId: String
    let isUserCreated: Bool

    // MARK: - Dependencies

    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared

    // MARK: - Initialization

    init(playlistId: String, isUserCreated: Bool = false, initialPlaylist: Playlist? = nil) {
        self.playlistId = playlistId
        self.isUserCreated = isUserCreated
        self.playlist = initialPlaylist
    }

    // MARK: - Database Observation

    /// Start observing playlist and tracks from local database
    /// Call this from view's .task modifier
    func observeDatabase() async {
        let playlistId = self.playlistId
        logInfo(.db, "Starting observation for playlist: \(playlistId)")

        // Observe both playlist metadata and tracks together
        let observation = ValueObservation.tracking { [playlistId] db -> (PersistedPlaylist?, [PersistedTrack]) in
            // Fetch the playlist itself (for name updates)
            let persistedPlaylist = try PersistedPlaylist
                .filter(PersistedPlaylist.Columns.id == playlistId)
                .fetchOne(db)

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

            // Return tracks in the correct order
            let tracks = trackIds.compactMap { tracksDict[$0] }
            return (persistedPlaylist, tracks)
        }
        .values(in: db.reader)

        do {
            for try await (persistedPlaylist, tracks) in observation {
                logInfo(.db, "Observed \(tracks.count) tracks for playlist \(playlistId)")

                // Update playlist if changed
                if let persistedPlaylist {
                    let updatedPlaylist = persistedPlaylist.toPlaylist()
                    if self.playlist != updatedPlaylist {
                        self.playlist = updatedPlaylist
                    }
                }

                // Convert to TrackItems for UI
                let items = tracks.compactMap { track -> TrackItem? in
                    guard let scTrack = track.soundCloudTrack else { return nil }
                    return TrackItem(soundCloudTrack: scTrack)
                }

                if self.trackItems != items {
                    self.trackItems = items
                }
                let nextRows = items.indexedRows()
                if self.trackRows != nextRows {
                    self.trackRows = nextRows
                }
                self.error = nil
            }
        } catch is CancellationError {
            // Expected when the view disappears; don't surface as an error state.
        } catch {
            logError(.db, "Failed to observe playlist tracks: \(error)")
            self.error = error
        }
    }

    // MARK: - Refresh from Network

    /// Refresh playlist tracks from Convex backend
    /// Call this on pull-to-refresh or first appear
    func refresh(userId: String, forceRefresh: Bool = false) async {
        // User-created playlists don't need SoundCloud sync
        guard !isUserCreated else {
            hasAttemptedLoad = true
            return
        }

        // Only show loading if truly empty
        isLoading = trackItems.isEmpty

        do {
            try await playlistSync.syncPlaylistTracks(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: forceRefresh,
                updatePlaylistRow: false
            )
            error = nil
        } catch {
            logError(.sync, "Failed to sync playlist tracks: \(error)")
            self.error = error
        }

        hasAttemptedLoad = true
        isLoading = false
    }
}
