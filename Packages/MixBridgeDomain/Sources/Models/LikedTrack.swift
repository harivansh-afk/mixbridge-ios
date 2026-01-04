//
//  LikedTrack.swift
//  MixBridgeDomain
//
//  Model for liked/favorited tracks - no GRDB dependencies.
//

import Foundation

public struct LikedTrack: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case trackId, likedAt
    }

    public var trackId: String
    public var likedAt: Date

    public init(
        trackId: String,
        likedAt: Date = Date()
    ) {
        self.trackId = trackId
        self.likedAt = likedAt
    }
}
