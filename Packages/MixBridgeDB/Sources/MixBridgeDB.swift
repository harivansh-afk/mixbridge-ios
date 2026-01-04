//
//  MixBridgeDB.swift
//  MixBridgeDB
//
//  Local-first database layer using GRDB.
//

import Foundation
@_exported import GRDB
@_exported import MixBridgeDomain

public struct MixBridgeDB: Sendable {
    private let dbWriter: DatabaseWriter

    public init(_ writer: DatabaseWriter) throws {
        dbWriter = writer
        try migrator.migrate(writer)
    }

    public var reader: DatabaseReader { dbWriter }
    public var writer: DatabaseWriter { dbWriter }
}

// MARK: - Configuration

extension MixBridgeDB {
    public static func makeConfiguration(_ base: Configuration = Configuration()) -> Configuration {
        var config = base
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        return config
    }
}

// MARK: - Delete All Data

extension MixBridgeDB {
    public func deleteAll() async throws {
        try await writer.write { db in
            try LikedTrack.deleteAll(db)
            try PlayHistory.deleteAll(db)
            try PlaylistTrack.deleteAll(db)
            try PersistedPlaylist.deleteAll(db)
            try PersistedTrack.deleteAll(db)
            try PersistedUserProfile.deleteAll(db)
        }
    }
}
