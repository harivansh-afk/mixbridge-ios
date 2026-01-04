//
//  Persistence.swift
//  mixbridge
//
//  Database persistence layer - creates shared MixBridgeDB instance.
//

import Foundation
import MixBridgeDB

extension MixBridgeDB {
    /// Shared database instance for the app
    public static let shared = makeShared()

    public static var databaseFilePath: URL? {
        try? getDatabaseFilePath()
    }

    private static func getDatabaseFilePath() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL.appendingPathComponent("Database", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("mixbridge.sqlite")
    }

    private static func makeShared() -> MixBridgeDB {
        do {
            let databaseURL = try getDatabaseFilePath()
            logInfo(.db, "Database stored at \(databaseURL.path)")
            let dbPool = try DatabasePool(
                path: databaseURL.path,
                configuration: MixBridgeDB.makeConfiguration()
            )
            return try MixBridgeDB(dbPool)
        } catch {
            logError(.db, "Failed to create database: \(error). Returning empty database.")
            return .empty()
        }
    }

    /// Creates an empty in-memory database (fallback or previews)
    public static func empty() -> MixBridgeDB {
        let dbQueue = try! DatabaseQueue(configuration: MixBridgeDB.makeConfiguration())
        return try! MixBridgeDB(dbQueue)
    }
}
