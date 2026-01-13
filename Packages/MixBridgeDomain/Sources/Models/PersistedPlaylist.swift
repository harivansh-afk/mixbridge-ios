//
//  PersistedPlaylist.swift
//  MixBridgeDomain
//
//  Base model for persisted playlists - no GRDB dependencies.
//

import Foundation

public struct PersistedPlaylist: Codable, Equatable, Identifiable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case id, name, creator, creatorId, artwork, trackCount, duration
        case description, genre, createdAt, lastUpdated, soundCloudData
        case libraryOwnerUserId, isUserCreated
    }

    public var id: String
    public var name: String
    public var creator: String
    public var creatorId: Int
    public var artwork: String
    public var trackCount: Int
    public var duration: Int
    public var description: String?
    public var genre: String?
    public var createdAt: Date
    public var lastUpdated: Date
    public var soundCloudData: Data?

    /// If set, this playlist belongs in the signed-in user's Library UI.
    /// If nil, the playlist is cached (e.g. search/artist) and should not appear in Library lists.
    public var libraryOwnerUserId: String?

    /// True if this is a user-created playlist (not from SoundCloud)
    public var isUserCreated: Bool

    public init(
        id: String,
        name: String,
        creator: String,
        creatorId: Int,
        artwork: String,
        trackCount: Int = 0,
        duration: Int = 0,
        description: String? = nil,
        genre: String? = nil,
        createdAt: Date = Date(),
        lastUpdated: Date = Date(),
        soundCloudData: Data? = nil,
        libraryOwnerUserId: String? = nil,
        isUserCreated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.creator = creator
        self.creatorId = creatorId
        self.artwork = artwork
        self.trackCount = trackCount
        self.duration = duration
        self.description = description
        self.genre = genre
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.soundCloudData = soundCloudData
        self.libraryOwnerUserId = libraryOwnerUserId
        self.isUserCreated = isUserCreated
    }
}
