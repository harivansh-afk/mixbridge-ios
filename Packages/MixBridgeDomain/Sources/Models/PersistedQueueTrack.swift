//
//  PersistedQueueTrack.swift
//  MixBridgeDomain
//
//  Local representation of a Convex `queueTracks` document.
//  Uses a stable local primary key and stores the Convex document ID separately.
//

import Foundation

public struct PersistedQueueTrack: Codable, Equatable, Identifiable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case id
        case serverId
        case queueUserId
        case trackId
        case source
        case title
        case artist
        case duration
        case artworkUrl
        case trackData
        case position
        case createdAt
        case updatedAt
    }

    /// Local primary key. For server-synced rows we use the Convex `_id`.
    public var id: String

    /// Convex `queueTracks._id` (optional while pending local sync).
    public var serverId: String?

    /// References `PersistedQueue.id` (which is the app userId).
    public var queueUserId: String

    public var trackId: String
    public var source: String
    public var title: String
    public var artist: String
    public var duration: Double
    public var artworkUrl: String?

    /// JSON-encoded SoundCloud track data (mirrors Convex `trackData: v.any()`).
    public var trackData: Data

    /// 0-based position in the upcoming queue (mirrors Convex `position`).
    public var position: Int

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        serverId: String? = nil,
        queueUserId: String,
        trackId: String,
        source: String,
        title: String,
        artist: String,
        duration: Double,
        artworkUrl: String? = nil,
        trackData: Data,
        position: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.queueUserId = queueUserId
        self.trackId = trackId
        self.source = source
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artworkUrl = artworkUrl
        self.trackData = trackData
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

