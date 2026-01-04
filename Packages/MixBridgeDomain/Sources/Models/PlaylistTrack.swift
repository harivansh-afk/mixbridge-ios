//
//  PlaylistTrack.swift
//  MixBridgeDomain
//
//  Junction model connecting playlists to tracks - no GRDB dependencies.
//

import Foundation

public struct PlaylistTrack: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case playlistId, trackId, position, addedAt
    }

    public var playlistId: String
    public var trackId: String
    public var position: Int
    public var addedAt: Date

    public init(
        playlistId: String,
        trackId: String,
        position: Int = 0,
        addedAt: Date = Date()
    ) {
        self.playlistId = playlistId
        self.trackId = trackId
        self.position = position
        self.addedAt = addedAt
    }
}
