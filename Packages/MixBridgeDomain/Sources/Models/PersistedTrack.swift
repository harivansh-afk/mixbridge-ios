//
//  PersistedTrack.swift
//  MixBridgeDomain
//
//  Base model for persisted tracks - no GRDB dependencies.
//

import Foundation

public struct PersistedTrack: Codable, Equatable, Identifiable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case id, title, artist, artistId, album, artwork, duration
        case playbackCount, likesCount, genre, createdAt, updatedAt, soundCloudData
        case source
    }

    public var id: String
    public var title: String
    public var artist: String
    public var artistId: String  // Can be numeric (SoundCloud) or string (Spotify)
    public var album: String
    public var artwork: String
    public var duration: Double
    public var playbackCount: Int
    public var likesCount: Int
    public var genre: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var soundCloudData: Data?
    
    /// The source platform for this track (soundcloud, spotify)
    /// Defaults to soundcloud for backward compatibility
    public var source: String

    public init(
        id: String,
        title: String,
        artist: String,
        artistId: String,
        album: String,
        artwork: String,
        duration: Double,
        playbackCount: Int = 0,
        likesCount: Int = 0,
        genre: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        soundCloudData: Data? = nil,
        source: String = "soundcloud"
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistId = artistId
        self.album = album
        self.artwork = artwork
        self.duration = duration
        self.playbackCount = playbackCount
        self.likesCount = likesCount
        self.genre = genre
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.soundCloudData = soundCloudData
        self.source = source
    }
}
