//
//  CreatePlaylistViewModel.swift
//  mixbridge
//
//  ViewModel for Apple Music-style playlist creation flow.
//  Manages two-step flow: name entry → track selection.
//

import Foundation
import MixBridgeDB

@Observable
@MainActor
final class CreatePlaylistViewModel {
    // MARK: - Flow State
    
    enum Step {
        case nameEntry
        case trackSelection
    }
    
    var currentStep: Step = .nameEntry
    
    // MARK: - Name Entry State
    
    var playlistName: String = ""
    var playlistDescription: String = ""
    
    var canProceedToTrackSelection: Bool {
        !playlistName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // MARK: - Track Selection State
    
    var selectedTracks: [TrackItem] = []
    var searchText: String = ""
    
    var canCreatePlaylist: Bool {
        !selectedTracks.isEmpty && canProceedToTrackSelection
    }
    
    var selectedCount: Int {
        selectedTracks.count
    }
    
    // MARK: - Data Sources
    
    private(set) var likedTracks: [TrackItem] = []
    private(set) var recentlyPlayed: [TrackItem] = []
    private(set) var libraryPlaylists: [Playlist] = []
    private(set) var searchResults: [TrackItem] = []
    
    private(set) var isLoadingData = false
    private(set) var isSearching = false
    private(set) var isCreating = false
    private(set) var error: Error?
    
    // MARK: - Dependencies
    
    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared
    private let convex = ConvexService.shared
    
    // MARK: - Computed Properties
    
    /// First selected track's artwork (for playlist cover)
    var playlistArtwork: String {
        selectedTracks.first?.track.artwork ?? ""
    }
    
    /// Filtered liked tracks based on search
    var filteredLikedTracks: [TrackItem] {
        guard !searchText.isEmpty else { return likedTracks }
        let query = searchText.lowercased()
        return likedTracks.filter {
            $0.track.title.lowercased().contains(query) ||
            $0.track.artist.lowercased().contains(query)
        }
    }
    
    /// Filtered recently played based on search
    var filteredRecentlyPlayed: [TrackItem] {
        guard !searchText.isEmpty else { return recentlyPlayed }
        let query = searchText.lowercased()
        return recentlyPlayed.filter {
            $0.track.title.lowercased().contains(query) ||
            $0.track.artist.lowercased().contains(query)
        }
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Flow Actions
    
    func proceedToTrackSelection() {
        guard canProceedToTrackSelection else { return }
        HapticManager.medium()
        currentStep = .trackSelection
    }
    
    func goBackToNameEntry() {
        HapticManager.light()
        currentStep = .nameEntry
    }
    
    // MARK: - Track Selection Actions
    
    func toggleTrackSelection(_ item: TrackItem) {
        HapticManager.selection()
        if let index = selectedTracks.firstIndex(where: { $0.id == item.id }) {
            selectedTracks.remove(at: index)
        } else {
            selectedTracks.append(item)
        }
    }
    
    func isSelected(_ item: TrackItem) -> Bool {
        selectedTracks.contains { $0.id == item.id }
    }
    
    func removeTrack(at index: Int) {
        guard index < selectedTracks.count else { return }
        HapticManager.light()
        selectedTracks.remove(at: index)
    }
    
    func clearSelection() {
        selectedTracks.removeAll()
    }
    
    // MARK: - Data Loading
    
    func loadTrackSources(userId: String) async {
        isLoadingData = true
        
        async let likedTask: () = loadLikedTracks(userId: userId)
        async let recentTask: () = loadRecentlyPlayed(userId: userId)
        async let playlistsTask: () = loadLibraryPlaylists(userId: userId)
        
        _ = await (likedTask, recentTask, playlistsTask)
        
        isLoadingData = false
    }
    
    private func loadLikedTracks(userId: String) async {
        do {
            let records = try await db.reader.read { db in
                try LikedTrack
                    .including(required: LikedTrack.track)
                    .order(LikedTrack.Columns.likedAt.desc)
                    .limit(50)
                    .asRequest(of: LikedTrackWithTrack.self)
                    .fetchAll(db)
            }
            
            likedTracks = records.compactMap { record -> TrackItem? in
                guard let scTrack = record.track.soundCloudTrack else { return nil }
                return TrackItem(soundCloudTrack: scTrack)
            }
        } catch {
            logError(.db, "Failed to load liked tracks: \(error)")
        }
    }
    
    private func loadRecentlyPlayed(userId: String) async {
        do {
            // Fetch more to account for duplicates after deduping
            let history = try await convex.getPlayHistory(userId: userId, limit: 50)

            // Dedupe by track ID, keeping first occurrence (most recent)
            var seenIds = Set<String>()
            recentlyPlayed = history.compactMap { record -> TrackItem? in
                let trackData = record.trackData

                // Skip invalid/incomplete tracks
                guard !trackData.id.isEmpty,
                      !trackData.title.trimmingCharacters(in: .whitespaces).isEmpty,
                      !trackData.user.username.trimmingCharacters(in: .whitespaces).isEmpty
                else {
                    return nil
                }

                // Skip duplicates
                guard !seenIds.contains(trackData.id) else {
                    return nil
                }
                seenIds.insert(trackData.id)

                return TrackItem(soundCloudTrack: trackData)
            }
        } catch {
            logError(.sync, "Failed to load play history: \(error)")
        }
    }
    
    private func loadLibraryPlaylists(userId: String) async {
        do {
            let playlists = try await db.reader.read { db in
                try PersistedPlaylist
                    .filter(PersistedPlaylist.Columns.libraryOwnerUserId == userId)
                    .filter(PersistedPlaylist.Columns.isUserCreated == false)
                    .order(PersistedPlaylist.Columns.lastUpdated.desc)
                    .limit(20)
                    .fetchAll(db)
            }
            
            libraryPlaylists = playlists.map { $0.toPlaylist() }
        } catch {
            logError(.db, "Failed to load playlists: \(error)")
        }
    }
    
    // MARK: - Search
    
    func search(userId: String) async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            let results = try await convex.search(userId: userId, query: query, limit: 20)
            searchResults = results.tracks.map { TrackItem(soundCloudTrack: $0) }
        } catch {
            logError(.sync, "Search failed: \(error)")
            searchResults = []
        }
        
        isSearching = false
    }
    
    // MARK: - Playlist Creation
    
    func createPlaylist(userId: String) async -> String? {
        guard canCreatePlaylist else { return nil }
        
        isCreating = true
        HapticManager.medium()
        
        let trimmedName = playlistName.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = playlistDescription.trimmingCharacters(in: .whitespaces)
        
        // Convert TrackItems to PersistedTracks preserving SoundCloud data
        let persistedTracks = selectedTracks.map { item -> PersistedTrack in
            PersistedTrack(from: item.soundCloudTrack)
        }
        
        do {
            let playlistId = try await playlistSync.createUserPlaylistWithTracks(
                userId: userId,
                name: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                tracks: persistedTracks
            )
            
            logInfo(.sync, "Created playlist '\(trimmedName)' with \(selectedTracks.count) tracks")
            HapticManager.success()
            
            isCreating = false
            return playlistId
        } catch {
            logError(.sync, "Failed to create playlist: \(error)")
            self.error = error
            HapticManager.error()
            isCreating = false
            return nil
        }
    }
    
    // MARK: - Load Tracks from Playlist
    
    func loadPlaylistTracks(userId: String, playlistId: String) async -> [TrackItem] {
        do {
            let tracks = try await playlistSync.getLocalPlaylistTracks(playlistId: playlistId)
            return tracks.compactMap { track -> TrackItem? in
                guard let scTrack = track.soundCloudTrack else { return nil }
                return TrackItem(soundCloudTrack: scTrack)
            }
        } catch {
            logError(.db, "Failed to load playlist tracks: \(error)")
            return []
        }
    }
    
    func addTracksFromPlaylist(_ tracks: [TrackItem]) {
        HapticManager.medium()
        for track in tracks {
            if !isSelected(track) {
                selectedTracks.append(track)
            }
        }
    }
}
