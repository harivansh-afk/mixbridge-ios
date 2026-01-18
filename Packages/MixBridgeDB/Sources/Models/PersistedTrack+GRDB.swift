//
//  PersistedTrack+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedTrack.
//

import Foundation
import GRDB
import MixBridgeDomain

// MARK: - TableRecord

extension PersistedTrack: @retroactive TableRecord {
    public static let databaseTableName = "tracks"
}

// MARK: - FetchableRecord, PersistableRecord

extension PersistedTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let title = Column(CodingKeys.title)
        public static let artist = Column(CodingKeys.artist)
        public static let artistId = Column(CodingKeys.artistId)
        public static let album = Column(CodingKeys.album)
        public static let artwork = Column(CodingKeys.artwork)
        public static let duration = Column(CodingKeys.duration)
        public static let playbackCount = Column(CodingKeys.playbackCount)
        public static let likesCount = Column(CodingKeys.likesCount)
        public static let genre = Column(CodingKeys.genre)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
        public static let soundCloudData = Column(CodingKeys.soundCloudData)
        public static let source = Column(CodingKeys.source)
    }
}

// MARK: - Associations

extension PersistedTrack {
    public static let playlistTracks = hasMany(PlaylistTrack.self, using: ForeignKey(["trackId"]))
    public static let playHistory = hasOne(PlayHistory.self, using: ForeignKey(["trackId"]))
    public static let likedTrack = hasOne(LikedTrack.self, using: ForeignKey(["trackId"]))
}
