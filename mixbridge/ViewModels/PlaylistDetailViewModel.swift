//
//  PlaylistDetailViewModel.swift
//  mixbridge
//
//  ViewModel for PlaylistDetailView with GRDB ValueObservation.
//  Observes tracks for a specific playlist from local database.
//

import Foundation
import MixBridgeDB

@Observable
@MainActor
final class PlaylistDetailViewModel {
    // MARK: - Observable State

    private(set) var trackItems: [TrackItem] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    var hasLoaded: Bool {
        !trackItems.isEmpty || (!isLoading && error == nil)
    }

    // MARK: - Configuration

    let playlistId: String

    // MARK: - Dependencies

    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared

    // MARK: - Initialization

    init(playlistId: String) {
        self.playlistId = playlistId
    }

    // MARK: - Database Observation

    /// Start observing playlist tracks from local database
    /// Call this from view's .task modifier
    func observeDatabase() async {
        let playlistId = self.playlistId

        let observation = ValueObservation.tracking { [playlistId] db in
            // Fetch tracks with their junction table data
            try PersistedTrack
                .joining(required: PersistedTrack.playlistTracks
                    .filter(PlaylistTrack.Columns.playlistId == playlistId))
                .order(PlaylistTrack.Columns.position)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await tracks in observation {
                // Convert to TrackItems for UI
                let items = tracks.compactMap { track -> TrackItem? in
                    guard let scTrack = track.soundCloudTrack else { return nil }
                    return TrackItem(soundCloudTrack: scTrack)
                }

                self.trackItems = items
                self.error = nil
            }
        } catch {
            logError(.db, "Failed to observe playlist tracks: \(error)")
            self.error = error
        }
    }

    // MARK: - Refresh from Network

    /// Refresh playlist tracks from Convex backend
    /// Call this on pull-to-refresh or first appear
    func refresh(userId: String, forceRefresh: Bool = false) async {
        // Only show loading if truly empty
        isLoading = trackItems.isEmpty

        do {
            try await playlistSync.syncPlaylistTracks(
                userId: userId,
                playlistId: playlistId,
                forceRefresh: forceRefresh
            )
            error = nil
        } catch {
            logError(.sync, "Failed to sync playlist tracks: \(error)")
            self.error = error
        }

        isLoading = false
    }
}
