//
//  Playlist.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import Foundation

struct Playlist: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let creator: String
    let artwork: String
    let tracks: [Track]
    let lastUpdated: Date
    let isUserCreated: Bool
    let customArtworkData: Data?
    /// If set, this playlist belongs in the signed-in user's Library UI.
    let libraryOwnerUserId: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        creator: String,
        artwork: String = "",
        tracks: [Track] = [],
        lastUpdated: Date = Date(),
        isUserCreated: Bool = false,
        customArtworkData: Data? = nil,
        libraryOwnerUserId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.creator = creator
        self.artwork = artwork
        self.tracks = tracks
        self.lastUpdated = lastUpdated
        self.isUserCreated = isUserCreated
        self.customArtworkData = customArtworkData
        self.libraryOwnerUserId = libraryOwnerUserId
    }
}

/// A playlist with its underlying SoundCloud data for API operations
struct PlaylistItem: Identifiable, Equatable, Sendable {
    let playlist: Playlist
    let soundCloudPlaylist: SoundCloudPlaylist?

    var id: String { playlist.id }

    init(soundCloudPlaylist: SoundCloudPlaylist) {
        self.playlist = Playlist(
            id: String(soundCloudPlaylist.id),
            name: soundCloudPlaylist.title,
            creator: soundCloudPlaylist.user.username,
            artwork: soundCloudPlaylist.primaryArtworkUrl,
            tracks: [],
            lastUpdated: Date()
        )
        self.soundCloudPlaylist = soundCloudPlaylist
    }

    init(playlist: Playlist, soundCloudPlaylist: SoundCloudPlaylist?) {
        self.playlist = playlist
        self.soundCloudPlaylist = soundCloudPlaylist
    }

    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        lhs.playlist.id == rhs.playlist.id
    }
}
