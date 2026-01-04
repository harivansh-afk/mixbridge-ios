//
//  PlayHistory+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PlayHistory.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PlayHistory: @retroactive TableRecord {
    public static let databaseTableName = "play_history"
}

// MARK: - FetchableRecord, PersistableRecord

extension PlayHistory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let trackId = Column(CodingKeys.trackId)
        public static let playCount = Column(CodingKeys.playCount)
        public static let lastPlayedPosition = Column(CodingKeys.lastPlayedPosition)
        public static let listenedPercentage = Column(CodingKeys.listenedPercentage)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}

// MARK: - Associations

extension PlayHistory {
    public static let track = belongsTo(PersistedTrack.self, using: ForeignKey(["trackId"]))
}

// MARK: - Helper Structs

public struct PlayHistoryWithTrack: Codable, FetchableRecord, Sendable {
    public var playHistory: PlayHistory
    public var track: PersistedTrack
}
