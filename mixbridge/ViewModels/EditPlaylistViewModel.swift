//
//  EditPlaylistViewModel.swift
//  mixbridge
//
//  ViewModel for editing existing playlists.
//  Manages track additions, removals, and metadata updates.
//

import Foundation
import MixBridgeDB
import UIKit

@Observable
@MainActor
final class EditPlaylistViewModel {
    // MARK: - Playlist Info
    
    let playlistId: String
    let isUserCreated: Bool
    var playlistName: String = ""
    var customArtworkImage: UIImage?
    private(set) var originalName: String = ""
    private(set) var originalArtwork: String = ""
    
    // MARK: - Track State
    
    private(set) var currentTracks: [TrackItem] = []
    private(set) var tracksToAdd: [TrackItem] = []
    private var trackIdsToRemove: Set<String> = []
    
    // MARK: - Selection State
    
    var selectedTrackIds: Set<String> = []
    
    // MARK: - UI State
    
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var error: Error?
    
    // MARK: - Add Tracks State (for nested picker)
    
    var searchText: String = ""
    private(set) var likedTracks: [TrackItem] = []
    private(set) var recentlyPlayed: [TrackItem] = []
    private(set) var libraryPlaylists: [Playlist] = []
    private(set) var searchResults: [TrackItem] = []
    private(set) var isSearching = false
    
    // MARK: - Dependencies
    
    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared
    private let convex = ConvexService.shared
    
    // MARK: - Computed Properties
    
    var hasChanges: Bool {
        playlistName != originalName ||
        !tracksToAdd.isEmpty ||
        !trackIdsToRemove.isEmpty ||
        customArtworkImage != nil
    }
    
    var displayTracks: [TrackItem] {
        var tracks = currentTracks.filter { !trackIdsToRemove.contains($0.id) }
        tracks.append(contentsOf: tracksToAdd)
        return tracks
    }
    
    var canSave: Bool {
        !displayTracks.isEmpty && !playlistName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var selectedCount: Int {
        selectedTrackIds.count
    }
    
    // MARK: - Initialization
    
    init(playlist: Playlist) {
        self.playlistId = playlist.id
        self.isUserCreated = playlist.isUserCreated
        self.playlistName = playlist.name
        self.originalName = playlist.name
        self.originalArtwork = playlist.artwork
    }
    
    // MARK: - Load Data
    
    func loadPlaylist(userId: String) async {
        isLoading = true
        
        do {
            let tracks = try await playlistSync.getLocalPlaylistTracks(playlistId: playlistId)
            currentTracks = tracks.compactMap { track -> TrackItem? in
                guard let scTrack = track.soundCloudTrack else { return nil }
                return TrackItem(soundCloudTrack: scTrack)
            }
        } catch {
            logError(.db, "Failed to load playlist tracks: \(error)")
            self.error = error
        }
        
        isLoading = false
    }
    
    // MARK: - Track Management
    
    func removeTrack(_ trackId: String) {
        HapticManager.light()
        if tracksToAdd.contains(where: { $0.id == trackId }) {
            tracksToAdd.removeAll { $0.id == trackId }
        } else {
            trackIdsToRemove.insert(trackId)
        }
        selectedTrackIds.remove(trackId)
    }
    
    func removeSelectedTracks() {
        HapticManager.medium()
        for trackId in selectedTrackIds {
            if tracksToAdd.contains(where: { $0.id == trackId }) {
                tracksToAdd.removeAll { $0.id == trackId }
            } else {
                trackIdsToRemove.insert(trackId)
            }
        }
        selectedTrackIds.removeAll()
    }
    
    func toggleTrackSelection(_ trackId: String) {
        HapticManager.selection()
        if selectedTrackIds.contains(trackId) {
            selectedTrackIds.remove(trackId)
        } else {
            selectedTrackIds.insert(trackId)
        }
    }
    
    func isTrackSelected(_ trackId: String) -> Bool {
        selectedTrackIds.contains(trackId)
    }
    
    func clearSelection() {
        selectedTrackIds.removeAll()
    }
    
    // MARK: - Add Tracks
    
    func addTrack(_ item: TrackItem) {
        HapticManager.selection()
        guard !isTrackInPlaylist(item.id) else { return }
        tracksToAdd.append(item)
    }
    
    func isTrackInPlaylist(_ trackId: String) -> Bool {
        let inCurrent = currentTracks.contains { $0.id == trackId } && !trackIdsToRemove.contains(trackId)
        let inToAdd = tracksToAdd.contains { $0.id == trackId }
        return inCurrent || inToAdd
    }
    
    // MARK: - Load Track Sources (for Add Tracks view)
    
    func loadTrackSources(userId: String) async {
        async let likedTask: () = loadLikedTracks()
        async let recentTask: () = loadRecentlyPlayed(userId: userId)
        async let playlistsTask: () = loadLibraryPlaylists(userId: userId)
        
        _ = await (likedTask, recentTask, playlistsTask)
    }
    
    private func loadLikedTracks() async {
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
            let history = try await convex.getPlayHistory(userId: userId, limit: 50)
            
            var seenIds = Set<Int>()
            recentlyPlayed = history.compactMap { record -> TrackItem? in
                let trackData = record.trackData
                
                guard trackData.id > 0,
                      !trackData.title.trimmingCharacters(in: .whitespaces).isEmpty,
                      !trackData.user.username.trimmingCharacters(in: .whitespaces).isEmpty
                else { return nil }
                
                guard !seenIds.contains(trackData.id) else { return nil }
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
                    .filter(PersistedPlaylist.Columns.isHiddenFromLibrary == false)
                    .filter(PersistedPlaylist.Columns.id != playlistId)
                    .order(PersistedPlaylist.Columns.lastUpdated.desc)
                    .limit(20)
                    .fetchAll(db)
            }
            
            libraryPlaylists = playlists.map { $0.toPlaylist() }
        } catch {
            logError(.db, "Failed to load playlists: \(error)")
        }
    }
    
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
    
    var filteredRecentlyPlayed: [TrackItem] {
        guard !searchText.isEmpty else { return recentlyPlayed }
        let query = searchText.lowercased()
        return recentlyPlayed.filter {
            $0.track.title.lowercased().contains(query) ||
            $0.track.artist.lowercased().contains(query)
        }
    }
    
    // MARK: - Save Changes
    
    func saveChanges(userId: String) async -> Bool {
        guard canSave else { return false }
        
        isSaving = true
        HapticManager.medium()
        
        do {
            let trimmedName = playlistName.trimmingCharacters(in: .whitespaces)
            
            // 1. Update name if changed
            if trimmedName != originalName {
                if isUserCreated {
                    try await playlistSync.renameUserPlaylist(userId: userId, playlistId: playlistId, name: trimmedName)
                } else {
                    try await playlistSync.renameSoundCloudPlaylist(userId: userId, playlistId: playlistId, name: trimmedName)
                }
            }

            // 2. Update custom artwork if changed (user-created playlists only)
            if let image = customArtworkImage, isUserCreated {
                let artworkData = image.jpegData(compressionQuality: 0.8)
                try await playlistSync.updateUserPlaylistArtwork(playlistId: playlistId, customArtworkData: artworkData)
            }

            // 3. Remove tracks
            for trackId in trackIdsToRemove {
                if isUserCreated {
                    try await playlistSync.removeTrackFromUserPlaylist(userId: userId, playlistId: playlistId, trackId: trackId)
                } else {
                    try await playlistSync.removeTrackFromSoundCloudPlaylist(userId: userId, playlistId: playlistId, trackId: trackId)
                }
            }

            // 4. Add tracks
            for item in tracksToAdd {
                let persistedTrack = PersistedTrack(from: item.soundCloudTrack)
                if isUserCreated {
                    try await playlistSync.addTrackToUserPlaylist(userId: userId, playlistId: playlistId, track: persistedTrack)
                } else {
                    try await playlistSync.addTrackToSoundCloudPlaylist(
                        userId: userId,
                        playlistId: playlistId,
                        track: persistedTrack,
                        soundCloudTrack: item.soundCloudTrack
                    )
                }
            }
            
            HapticManager.success()
            isSaving = false
            return true
        } catch {
            logError(.sync, "Failed to save playlist changes: \(error)")
            self.error = error
            HapticManager.error()
            isSaving = false
            return false
        }
    }
}
