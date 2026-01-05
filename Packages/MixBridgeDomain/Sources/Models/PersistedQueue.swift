//
//  PersistedQueue.swift
//  MixBridgeDomain
//
//  Local representation of the user's Convex `queues` document (one per user).
//  Mirrors the Convex schema fields and stores the Convex queue ID separately.
//

import Foundation

public struct PersistedQueue: Codable, Equatable, Identifiable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case id
        case convexQueueId
        case name
        case currentPosition
        case currentTime
        case playbackState
        case updatedAt
    }

    /// Local primary key. We use the app userId so there's always exactly one queue per user.
    public var id: String

    /// Convex `queues._id` (optional until first successful sync).
    public var convexQueueId: String?

    public var name: String?
    public var currentPosition: Double
    public var currentTime: Double
    public var playbackState: String
    public var updatedAt: Date

    public init(
        id: String,
        convexQueueId: String? = nil,
        name: String? = nil,
        currentPosition: Double = 0,
        currentTime: Double = 0,
        playbackState: String = "stopped",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.convexQueueId = convexQueueId
        self.name = name
        self.currentPosition = currentPosition
        self.currentTime = currentTime
        self.playbackState = playbackState
        self.updatedAt = updatedAt
    }
}

