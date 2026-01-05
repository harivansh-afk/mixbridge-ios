//
//  PersistedSearchCache+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedSearchCache.
//

import Foundation
import GRDB
import MixBridgeDomain

extension PersistedSearchCache: @retroactive TableRecord {
    public static let databaseTableName = "searchCache"
}

extension PersistedSearchCache: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let userId = Column(CodingKeys.userId)
        public static let query = Column(CodingKeys.query)
        public static let tracksData = Column(CodingKeys.tracksData)
        public static let playlistsData = Column(CodingKeys.playlistsData)
        public static let usersData = Column(CodingKeys.usersData)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

