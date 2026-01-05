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

        migrator.registerMigration("v2_queue_and_cache") { db in
            // Add Library scoping to playlists so we can cache non-library playlists safely.
            try db.alter(table: PersistedPlaylist.databaseTableName) { t in
                t.add(column: "libraryOwnerUserId", .text)
            }
            try db.create(index: "idx_playlists_libraryOwnerUserId", on: PersistedPlaylist.databaseTableName, columns: ["libraryOwnerUserId"])

            // Queues table (one per user) - mirrors Convex `queues` document fields.
            try db.create(table: PersistedQueue.databaseTableName) { t in
                t.column("id", .text).primaryKey() // userId
                t.column("convexQueueId", .text)
                t.column("name", .text)
                t.column("currentPosition", .double).notNull().defaults(to: 0)
                t.column("currentTime", .double).notNull().defaults(to: 0)
                t.column("playbackState", .text).notNull().defaults(to: "stopped")
                t.column("updatedAt", .datetime).notNull()
            }

            // Queue tracks table - mirrors Convex `queueTracks` documents.
            try db.create(table: PersistedQueueTrack.databaseTableName) { t in
                t.column("id", .text).primaryKey() // stable local ID (Convex id for synced rows)
                t.column("serverId", .text).unique(onConflict: .replace)
                t.column("queueUserId", .text).notNull().indexed()
                    .references(PersistedQueue.databaseTableName, onDelete: .cascade)
                t.column("trackId", .text).notNull().indexed()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("duration", .double).notNull()
                t.column("artworkUrl", .text)
                t.column("trackData", .blob).notNull()
                t.column("position", .integer).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_queueTracks_queueUserId_position", on: PersistedQueueTrack.databaseTableName, columns: ["queueUserId", "position"])

            // Search results cache - mirrors Convex `searchCache` document fields.
            try db.create(table: PersistedSearchCache.databaseTableName) { t in
                t.column("userId", .text).notNull()
                t.column("query", .text).notNull()
                t.column("tracksData", .blob).notNull()
                t.column("playlistsData", .blob).notNull()
                t.column("usersData", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["userId", "query"])
            }
            try db.create(index: "idx_searchCache_userId", on: PersistedSearchCache.databaseTableName, columns: ["userId"])

            // Artist detail cache (derived from search).
            try db.create(table: PersistedArtistCache.databaseTableName) { t in
                t.column("userId", .text).notNull()
                t.column("artistId", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("tracksData", .blob).notNull()
                t.column("playlistsData", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["userId", "artistId"])
            }
            try db.create(index: "idx_artistCache_userId", on: PersistedArtistCache.databaseTableName, columns: ["userId"])
        }

        return migrator
    }
}
