//
//  Track.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artwork: String
    let duration: Double

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String = "",
        artwork: String = "",
        duration: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
    }
}

// MARK: - Sample Data
extension Track {
    static let sampleTracks: [Track] = [
        Track(title: "Facilita", artist: "Fred again...", album: "Hindi Hits", artwork: "https://i1.sndcdn.com/artworks-000130423102-7uii2q-t500x500.jpg"),
        Track(title: "Samjho Na", artist: "Aditya Rikhari", album: "Romantic", artwork: "music.note"),
        Track(title: "Shendur Laal Chadh", artist: "Ravindra Sathe", album: "Devotional", artwork: "music.note"),
        Track(title: "Bhar Do Jholi Meri", artist: "Pritam & Adnan Sami", album: "Bajrangi Bhaijaan", artwork: "music.note"),
        Track(title: "Namo Namo", artist: "Amit Trivedi", album: "Kedarnath", artwork: "music.note"),
        Track(title: "Obsessed", artist: "Riar Saab & Abhijay Sharma", album: "Single", artwork: "music.note"),
        Track(title: "Thug Love", artist: "Various Artists", album: "Compilation", artwork: "music.note")
    ]
}
