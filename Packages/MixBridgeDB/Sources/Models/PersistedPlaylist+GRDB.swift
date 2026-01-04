//
//  PersistedPlaylist+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedPlaylist.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PersistedPlaylist: @retroactive TableRecord {
    public static let databaseTableName = "playlists"
}

// MARK: - FetchableRecord, PersistableRecord

extension PersistedPlaylist: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let creator = Column(CodingKeys.creator)
        public static let creatorId = Column(CodingKeys.creatorId)
        public static let artwork = Column(CodingKeys.artwork)
        public static let trackCount = Column(CodingKeys.trackCount)
        public static let duration = Column(CodingKeys.duration)
        public static let description = Column(CodingKeys.description)
        public static let genre = Column(CodingKeys.genre)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let lastUpdated = Column(CodingKeys.lastUpdated)
        public static let soundCloudData = Column(CodingKeys.soundCloudData)
    }
}

// MARK: - Associations

extension PersistedPlaylist {
    public static let playlistTracks = hasMany(PlaylistTrack.self, using: ForeignKey(["playlistId"]))
}
