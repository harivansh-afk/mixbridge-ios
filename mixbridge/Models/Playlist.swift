//
//  Playlist.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let creator: String
    let artwork: String
    let tracks: [Track]
    let lastUpdated: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        creator: String,
        artwork: String = "",
        tracks: [Track] = [],
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.creator = creator
        self.artwork = artwork
        self.tracks = tracks
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Sample Data
extension Playlist {
    static let samplePlaylists: [Playlist] = [
        Playlist(
            name: "Man I Need",
            creator: "Alex Smith",
            artwork: "music.note",
            tracks: Array(Track.sampleTracks.prefix(5))
        ),
        Playlist(
            name: "Yankeedaddy",
            creator: "Drake",
            artwork: "music.note",
            tracks: Array(Track.sampleTracks.prefix(3))
        ),
        Playlist(
            name: "Folded",
            creator: "Alex Smith",
            artwork: "music.note",
            tracks: Array(Track.sampleTracks.prefix(7))
        ),
        Playlist(
            name: "A-List Pop",
            creator: "Apple Music",
            artwork: "music.note",
            tracks: Track.sampleTracks
        ),
        Playlist(
            name: "Fall",
            creator: "Alex Smith",
            artwork: "music.note",
            tracks: Array(Track.sampleTracks.suffix(4))
        ),
        Playlist(
            name: "Zara Larsson",
            creator: "Apple Music",
            artwork: "music.note",
            tracks: Array(Track.sampleTracks.prefix(6))
        )
    ]
}
