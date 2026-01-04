//
//  PlayHistory.swift
//  MixBridgeDomain
//
//  Model for tracking play history - no GRDB dependencies.
//

import Foundation

public struct PlayHistory: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case trackId, playCount, lastPlayedPosition, listenedPercentage, createdAt, updatedAt
    }

    public var trackId: String
    public var playCount: Int
    public var lastPlayedPosition: Double
    public var listenedPercentage: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        trackId: String,
        playCount: Int = 1,
        lastPlayedPosition: Double = 0,
        listenedPercentage: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.trackId = trackId
        self.playCount = playCount
        self.lastPlayedPosition = lastPlayedPosition
        self.listenedPercentage = listenedPercentage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
