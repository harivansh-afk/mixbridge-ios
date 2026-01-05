//
//  PersistedArtistCache.swift
//  MixBridgeDomain
//
//  Local cache for artist detail content derived from SoundCloud search.
//  Mirrors Convex-style caching: keyed by (userId, artistId) with JSON payloads and updatedAt.
//

import Foundation

public struct PersistedArtistCache: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case userId
        case artistId
        case artistName
        case tracksData
        case playlistsData
        case updatedAt
    }

    public var userId: String
    public var artistId: String
    public var artistName: String

    public var tracksData: Data
    public var playlistsData: Data

    public var updatedAt: Date

    public init(
        userId: String,
        artistId: String,
        artistName: String,
        tracksData: Data,
        playlistsData: Data,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.artistId = artistId
        self.artistName = artistName
        self.tracksData = tracksData
        self.playlistsData = playlistsData
        self.updatedAt = updatedAt
    }
}

