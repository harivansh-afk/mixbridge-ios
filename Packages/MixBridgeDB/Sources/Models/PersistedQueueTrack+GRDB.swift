//
//  PersistedQueueTrack+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedQueueTrack.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PersistedQueueTrack: @retroactive TableRecord {
    public static let databaseTableName = "queueTracks"
}

// MARK: - FetchableRecord, PersistableRecord

extension PersistedQueueTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let serverId = Column(CodingKeys.serverId)
        public static let queueUserId = Column(CodingKeys.queueUserId)
        public static let trackId = Column(CodingKeys.trackId)
        public static let source = Column(CodingKeys.source)
        public static let title = Column(CodingKeys.title)
        public static let artist = Column(CodingKeys.artist)
        public static let duration = Column(CodingKeys.duration)
        public static let artworkUrl = Column(CodingKeys.artworkUrl)
        public static let trackData = Column(CodingKeys.trackData)
        public static let position = Column(CodingKeys.position)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Associations

extension PersistedQueueTrack {
    public static let queue = belongsTo(PersistedQueue.self, using: ForeignKey(["queueUserId"]))
}

