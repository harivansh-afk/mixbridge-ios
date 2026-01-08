//
//  LikedPlaylist.swift
//  MixBridgeDomain
//
//  Model for liked/favorited playlists - no GRDB dependencies.
//

import Foundation

public struct LikedPlaylist: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case playlistId, likedAt
    }

    public var playlistId: String
    public var likedAt: Date

    public init(
        playlistId: String,
        likedAt: Date = Date()
    ) {
        self.playlistId = playlistId
        self.likedAt = likedAt
    }
}
