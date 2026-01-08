//
//  LikedViewModel.swift
//  mixbridge
//
//  ViewModel for LikedView with GRDB ValueObservation.
//  Observes liked tracks and playlists from local database.
//

import Foundation
import MixBridgeDB

@Observable
@MainActor
final class LikedViewModel {
    // MARK: - Observable State

    private(set) var likedTracks: [TrackItem] = []
    private(set) var likedPlaylists: [PlaylistItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingPlaylists = false
    private(set) var error: Error?

    // MARK: - Dependencies

    private let db = MixBridgeDB.shared
    private let likedSync = LikedSync.shared
    private let likedPlaylistSync = LikedPlaylistSync.shared

    // MARK: - Initialization

    init() {}

    // MARK: - Database Observation (Tracks)

    /// Start observing liked tracks from local database
    /// Call this from view's .task modifier
    func observeDatabase() async {
        let observation = ValueObservation.tracking { db in
            try LikedTrack
                .including(required: LikedTrack.track)
                .order(LikedTrack.Columns.likedAt.desc)
                .asRequest(of: LikedTrackWithTrack.self)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await likedRecords in observation {
                // Convert to TrackItems for UI
                let items = likedRecords.compactMap { record -> TrackItem? in
                    guard let scTrack = record.track.soundCloudTrack else { return nil }
                    return TrackItem(soundCloudTrack: scTrack)
                }

                if self.likedTracks != items {
                    self.likedTracks = items
                }
                self.error = nil
            }
        } catch is CancellationError {
            // Expected when the view disappears; don't surface as an error state.
        } catch {
            logError(.db, "Failed to observe liked tracks: \(error)")
            self.error = error
        }
    }

    // MARK: - Database Observation (Playlists)

    /// Start observing liked playlists from local database
    /// Call this from view's .task modifier
    func observePlaylistsDatabase() async {
        let observation = ValueObservation.tracking { db in
            try LikedPlaylist
                .including(required: LikedPlaylist.playlist)
                .order(LikedPlaylist.Columns.likedAt.desc)
                .asRequest(of: LikedPlaylistWithPlaylist.self)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await likedRecords in observation {
                // Convert to PlaylistItems for UI
                let items = likedRecords.compactMap { record -> PlaylistItem? in
                    let playlist = record.playlist.toPlaylist()
                    let scPlaylist = record.playlist.soundCloudPlaylist
                    return PlaylistItem(playlist: playlist, soundCloudPlaylist: scPlaylist)
                }

                if self.likedPlaylists != items {
                    self.likedPlaylists = items
                }
            }
        } catch is CancellationError {
            // Expected when the view disappears; don't surface as an error state.
        } catch {
            logError(.db, "Failed to observe liked playlists: \(error)")
        }
    }

    // MARK: - Refresh from Network

    /// Refresh liked tracks from Convex backend
    /// Call this on pull-to-refresh or first appear
    func refresh(userId: String, forceRefresh: Bool = false) async {
        // Only show loading if truly empty (first install)
        isLoading = likedTracks.isEmpty

        do {
            try await likedSync.syncLikedTracks(userId: userId, forceRefresh: forceRefresh)
            error = nil
        } catch {
            logError(.sync, "Failed to sync liked tracks: \(error)")
            self.error = error
        }

        isLoading = false
    }

    /// Refresh liked playlists from Convex backend
    func refreshPlaylists(userId: String, forceRefresh: Bool = false) async {
        isLoadingPlaylists = likedPlaylists.isEmpty

        do {
            try await likedPlaylistSync.syncLikedPlaylists(userId: userId, forceRefresh: forceRefresh)
        } catch {
            logError(.sync, "Failed to sync liked playlists: \(error)")
        }

        isLoadingPlaylists = false
    }

    // MARK: - Like/Unlike Actions

    /// Like a track with optimistic update
    func likeTrack(_ scTrack: SoundCloudTrack) async throws {
        try await likedSync.likeTrack(scTrack)
    }

    /// Unlike a track with optimistic update
    func unlikeTrack(trackId: String) async throws {
        try await likedSync.unlikeTrack(trackId: trackId)
    }

    /// Check if a track is liked
    func isTrackLiked(trackId: String) async -> Bool {
        await likedSync.isTrackLiked(trackId: trackId)
    }

    /// Check if a playlist is liked
    func isPlaylistLiked(playlistId: String) async -> Bool {
        await likedPlaylistSync.isPlaylistLiked(playlistId: playlistId)
    }
}
