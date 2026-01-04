//
//  Migrations.swift
//  MixBridgeDB
//
//  Database migrations.
//

import Foundation
import GRDB
import MixBridgeDomain

extension MixBridgeDB {
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("v1_create_tables") { db in
            // Tracks table
            try db.create(table: PersistedTrack.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("artistId", .integer).notNull().indexed()
                t.column("album", .text).notNull()
                t.column("artwork", .text).notNull()
                t.column("duration", .double).notNull()
                t.column("playbackCount", .integer).notNull().defaults(to: 0)
                t.column("likesCount", .integer).notNull().defaults(to: 0)
                t.column("genre", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("soundCloudData", .blob)
            }

            // Playlists table
            try db.create(table: PersistedPlaylist.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("creator", .text).notNull()
                t.column("creatorId", .integer).notNull().indexed()
                t.column("artwork", .text).notNull()
                t.column("trackCount", .integer).notNull().defaults(to: 0)
                t.column("duration", .integer).notNull().defaults(to: 0)
                t.column("description", .text)
                t.column("genre", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastUpdated", .datetime).notNull().indexed()
                t.column("soundCloudData", .blob)
            }

            // Playlist tracks junction table
            try db.create(table: PlaylistTrack.databaseTableName) { t in
                t.column("playlistId", .text).notNull().indexed()
                    .references(PersistedPlaylist.databaseTableName, onDelete: .cascade)
                t.column("trackId", .text).notNull().indexed()
                    .references(PersistedTrack.databaseTableName, onDelete: .cascade)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["playlistId", "trackId"])
            }

            // Play history table
            try db.create(table: PlayHistory.databaseTableName) { t in
                t.column("trackId", .text).primaryKey()
                    .references(PersistedTrack.databaseTableName, onDelete: .cascade)
                t.column("playCount", .integer).notNull().defaults(to: 1)
                t.column("lastPlayedPosition", .double).notNull().defaults(to: 0)
                t.column("listenedPercentage", .double).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull().indexed()
            }

            // Liked tracks table
            try db.create(table: LikedTrack.databaseTableName) { t in
                t.column("trackId", .text).primaryKey()
                    .references(PersistedTrack.databaseTableName, onDelete: .cascade)
                t.column("likedAt", .datetime).notNull().indexed()
            }

            // User profiles table
            try db.create(table: PersistedUserProfile.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("updatedAt", .datetime).notNull()
                t.column("soundCloudData", .blob).notNull()
            }
        }

        return migrator
    }
}
