//
//  PlaylistTrack+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PlaylistTrack.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PlaylistTrack: @retroactive TableRecord {
    public static let databaseTableName = "playlist_tracks"
}

// MARK: - FetchableRecord, PersistableRecord

extension PlaylistTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let playlistId = Column(CodingKeys.playlistId)
        public static let trackId = Column(CodingKeys.trackId)
        public static let position = Column(CodingKeys.position)
        public static let addedAt = Column(CodingKeys.addedAt)
    }

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}

// MARK: - Associations

extension PlaylistTrack {
    public static let playlist = belongsTo(PersistedPlaylist.self, using: ForeignKey(["playlistId"]))
    public static let track = belongsTo(PersistedTrack.self, using: ForeignKey(["trackId"]))
}
