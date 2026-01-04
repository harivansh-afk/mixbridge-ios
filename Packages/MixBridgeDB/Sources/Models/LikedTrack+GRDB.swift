//
//  LikedTrack+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for LikedTrack.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension LikedTrack: @retroactive TableRecord {
    public static let databaseTableName = "liked_tracks"
}

// MARK: - FetchableRecord, PersistableRecord

extension LikedTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let trackId = Column(CodingKeys.trackId)
        public static let likedAt = Column(CodingKeys.likedAt)
    }

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}

// MARK: - Associations

extension LikedTrack {
    public static let track = belongsTo(PersistedTrack.self, using: ForeignKey(["trackId"]))
}

// MARK: - Helper Structs

public struct LikedTrackWithTrack: Codable, FetchableRecord, Sendable {
    public var likedTrack: LikedTrack
    public var track: PersistedTrack
}
