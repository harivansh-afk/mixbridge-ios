//
//  LikedPlaylist+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for LikedPlaylist.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension LikedPlaylist: @retroactive TableRecord {
    public static let databaseTableName = "liked_playlists"
}

// MARK: - FetchableRecord, PersistableRecord

extension LikedPlaylist: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let playlistId = Column(CodingKeys.playlistId)
        public static let likedAt = Column(CodingKeys.likedAt)
    }

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}

// MARK: - Associations

extension LikedPlaylist {
    public static let playlist = belongsTo(PersistedPlaylist.self, using: ForeignKey(["playlistId"]))
}

// MARK: - Helper Structs

public struct LikedPlaylistWithPlaylist: Codable, FetchableRecord, Sendable {
    public var likedPlaylist: LikedPlaylist
    public var playlist: PersistedPlaylist
}
