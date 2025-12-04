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
