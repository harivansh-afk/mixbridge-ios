//
//  PersistedQueue+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedQueue.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PersistedQueue: @retroactive TableRecord {
    public static let databaseTableName = "queues"
}

// MARK: - FetchableRecord, PersistableRecord

extension PersistedQueue: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let convexQueueId = Column(CodingKeys.convexQueueId)
        public static let name = Column(CodingKeys.name)
        public static let currentPosition = Column(CodingKeys.currentPosition)
        public static let currentTime = Column(CodingKeys.currentTime)
        public static let playbackState = Column(CodingKeys.playbackState)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

