//
//  PersistedSearchCache.swift
//  MixBridgeDomain
//
//  Local representation of Convex `searchCache` documents (TTL-managed on client).
//

import Foundation

public struct PersistedSearchCache: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case userId
        case query
        case tracksData
        case playlistsData
        case usersData
        case updatedAt
    }

    public var userId: String
    public var query: String

    /// JSON-encoded arrays (mirrors Convex `tracks/playlists/users: v.any()`).
    public var tracksData: Data
    public var playlistsData: Data
    public var usersData: Data

    public var updatedAt: Date

    public init(
        userId: String,
        query: String,
        tracksData: Data,
        playlistsData: Data,
        usersData: Data,
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.query = query
        self.tracksData = tracksData
        self.playlistsData = playlistsData
        self.usersData = usersData
        self.updatedAt = updatedAt
    }
}

