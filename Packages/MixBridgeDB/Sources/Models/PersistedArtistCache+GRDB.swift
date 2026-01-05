//
//  PersistedArtistCache+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedArtistCache.
//

import Foundation
import GRDB
import MixBridgeDomain

extension PersistedArtistCache: @retroactive TableRecord {
    public static let databaseTableName = "artistCache"
}

extension PersistedArtistCache: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let userId = Column(CodingKeys.userId)
        public static let artistId = Column(CodingKeys.artistId)
        public static let artistName = Column(CodingKeys.artistName)
        public static let tracksData = Column(CodingKeys.tracksData)
        public static let playlistsData = Column(CodingKeys.playlistsData)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

