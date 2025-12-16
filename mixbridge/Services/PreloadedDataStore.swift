//
//  PreloadedDataStore.swift
//  mixbridge
//
//  Centralized store for preloaded app data.
//  Views read from here for instant display.
//

import Foundation
import SwiftUI

/// Loading state for each data type
enum PreloadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(Error)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    static func == (lhs: PreloadState, rhs: PreloadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

/// Centralized store for all preloaded data
/// Views read from this store for instant display
@MainActor
@Observable
final class PreloadedDataStore {
    static let shared = PreloadedDataStore()

    // MARK: - Tier 1: Critical Data (blocks splash conceptually)

    /// User profile data
    private(set) var profile: SoundCloudProfile?
    private(set) var profileState: PreloadState = .idle

    /// Play history for HomeView
    private(set) var playHistory: [TrackItem] = []
    private(set) var playHistoryState: PreloadState = .idle

    /// Playlists for LibraryView
    private(set) var playlists: [Playlist] = []
    private(set) var playlistsState: PreloadState = .idle

    // MARK: - Tier 2: Secondary Data (loads after splash)

    /// Liked tracks for LikedView
    private(set) var likedTracks: [TrackItem] = []
    private(set) var likedTracksState: PreloadState = .idle

    /// Playlist tracks by playlist ID
    private(set) var playlistTracks: [String: [TrackItem]] = [:]
    private(set) var playlistTracksState: [String: PreloadState] = [:]

    // MARK: - Tier 3: Speculative Data

    /// Artists data (computed from liked tracks)
    private(set) var artists: [String: [TrackItem]] = [:]

    /// All songs (combined from various sources)
    private(set) var allSongs: [TrackItem] = []
    private(set) var allSongsState: PreloadState = .idle

    // MARK: - Timestamps for freshness

    private var lastProfileLoad: Date?
    private var lastPlayHistoryLoad: Date?
    private var lastPlaylistsLoad: Date?
    private var lastLikedTracksLoad: Date?
    private var playlistTracksLoadTimes: [String: Date] = [:]

    /// Data older than this will be refreshed in background
    private let freshnessThreshold: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Update Methods (called by AppDataPreloader)

    func updateProfile(_ profile: SoundCloudProfile) {
        self.profile = profile
        self.profileState = .loaded
        self.lastProfileLoad = Date()
    }

    func updatePlayHistory(_ items: [TrackItem]) {
        self.playHistory = items
        self.playHistoryState = .loaded
        self.lastPlayHistoryLoad = Date()
    }

    /// Optimistically prepend or move a track to the top of play history
    /// If track exists (by trackId): move to top, increment playCount, keep metadata
    /// If track doesn't exist: prepend to top
    /// Limits list to 50 items
    func prependOrMovePlayHistoryTrack(_ item: TrackItem) {
        let trackId = item.track.id

        // Check if track already exists
        if let existingIndex = playHistory.firstIndex(where: { $0.track.id == trackId }) {
            // Move to top: remove from current position
            var existingItem = playHistory.remove(at: existingIndex)
            // Increment play count, keep other metadata
            existingItem.playCount += 1
            // Insert at top
            playHistory.insert(existingItem, at: 0)
        } else {
            // New track: prepend
            playHistory.insert(item, at: 0)
        }

        // Limit to 50 items
        if playHistory.count > 50 {
            playHistory = Array(playHistory.prefix(50))
        }

        // Update timestamp to prevent immediate stale refresh
        self.lastPlayHistoryLoad = Date()
    }

    func updatePlaylists(_ playlists: [Playlist]) {
        self.playlists = playlists
        self.playlistsState = .loaded
        self.lastPlaylistsLoad = Date()
    }

    func updateLikedTracks(_ items: [TrackItem]) {
        self.likedTracks = items
        self.likedTracksState = .loaded
        self.lastLikedTracksLoad = Date()

        // Compute artists from liked tracks
        var artistMap: [String: [TrackItem]] = [:]
        for item in items {
            let artist = item.track.artist
            artistMap[artist, default: []].append(item)
        }
        self.artists = artistMap
    }

    func updatePlaylistTracks(playlistId: String, items: [TrackItem]) {
        self.playlistTracks[playlistId] = items
        self.playlistTracksState[playlistId] = .loaded
        self.playlistTracksLoadTimes[playlistId] = Date()
    }

    func updateAllSongs(_ items: [TrackItem]) {
        self.allSongs = items
        self.allSongsState = .loaded
    }

    // MARK: - State Updates

    func setProfileLoading() { profileState = .loading }
    func setPlayHistoryLoading() { playHistoryState = .loading }
    func setPlaylistsLoading() { playlistsState = .loading }
    func setLikedTracksLoading() { likedTracksState = .loading }
    func setPlaylistTracksLoading(_ playlistId: String) {
        playlistTracksState[playlistId] = .loading
    }

    func setProfileFailed(_ error: Error) { profileState = .failed(error) }
    func setPlayHistoryFailed(_ error: Error) { playHistoryState = .failed(error) }
    func setPlaylistsFailed(_ error: Error) { playlistsState = .failed(error) }
    func setLikedTracksFailed(_ error: Error) { likedTracksState = .failed(error) }
    func setPlaylistTracksFailed(_ playlistId: String, _ error: Error) {
        playlistTracksState[playlistId] = .failed(error)
    }

    // MARK: - Freshness Checks

    func isProfileStale() -> Bool {
        guard let lastLoad = lastProfileLoad else { return true }
        return Date().timeIntervalSince(lastLoad) > freshnessThreshold
    }

    func isPlayHistoryStale() -> Bool {
        guard let lastLoad = lastPlayHistoryLoad else { return true }
        return Date().timeIntervalSince(lastLoad) > freshnessThreshold
    }

    func isPlaylistsStale() -> Bool {
        guard let lastLoad = lastPlaylistsLoad else { return true }
        return Date().timeIntervalSince(lastLoad) > freshnessThreshold
    }

    func isLikedTracksStale() -> Bool {
        guard let lastLoad = lastLikedTracksLoad else { return true }
        return Date().timeIntervalSince(lastLoad) > freshnessThreshold
    }

    func isPlaylistTracksStale(_ playlistId: String) -> Bool {
        guard let lastLoad = playlistTracksLoadTimes[playlistId] else { return true }
        return Date().timeIntervalSince(lastLoad) > freshnessThreshold
    }

    // MARK: - Clear (for logout)

    func clearAll() {
        profile = nil
        profileState = .idle
        playHistory = []
        playHistoryState = .idle
        playlists = []
        playlistsState = .idle
        likedTracks = []
        likedTracksState = .idle
        playlistTracks = [:]
        playlistTracksState = [:]
        artists = [:]
        allSongs = []
        allSongsState = .idle

        lastProfileLoad = nil
        lastPlayHistoryLoad = nil
        lastPlaylistsLoad = nil
        lastLikedTracksLoad = nil
        playlistTracksLoadTimes = [:]
    }
}
