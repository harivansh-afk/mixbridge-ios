//
//  DownloadedTrack+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for DownloadedTrack.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension DownloadedTrack: @retroactive TableRecord {
    public static let databaseTableName = "downloadedTracks"
}

// MARK: - FetchableRecord, PersistableRecord

extension DownloadedTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let trackId = Column(CodingKeys.trackId)
        public static let localPath = Column(CodingKeys.localPath)
        public static let fileSize = Column(CodingKeys.fileSize)
        public static let downloadedAt = Column(CodingKeys.downloadedAt)
        public static let expiresAt = Column(CodingKeys.expiresAt)
    }
}

// MARK: - Associations

extension DownloadedTrack {
    public static let track = belongsTo(PersistedTrack.self, using: ForeignKey(["trackId"]))
}
