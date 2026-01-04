//
//  UserProfileSync.swift
//  mixbridge
//
//  Synchronizes user profile between Convex backend and local GRDB database.
//  Enables offline access to user account information.
//

import Foundation
import MixBridgeDB

final class UserProfileSync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = UserProfileSync()
    private init() {}

    // MARK: - Sync Profile from Backend

    /// Fetch user profile from Convex and save to local database
    func syncProfile(userId: String) async throws -> SoundCloudProfile? {
        try await operationQueue.run { [self] in
            let scProfile = try await convex.getUserProfile(userId: userId)
            let persisted = try PersistedUserProfile(from: scProfile)

            try await db.writer.write { db in
                var profile = persisted
                try profile.upsert(db)
            }

            logInfo(.sync, "Synced user profile for \(scProfile.username)")
            return scProfile
        }
    }

    // MARK: - Local Queries

    /// Get SoundCloudProfile from local database
    func getLocalSoundCloudProfile(userId: String) async throws -> SoundCloudProfile? {
        let persisted = try await db.reader.read { db in
            try PersistedUserProfile.fetchOne(db, key: userId)
        }
        return persisted?.toSoundCloudProfile()
    }
}

// MARK: - Conversions

extension PersistedUserProfile {
    init(from profile: SoundCloudProfile) throws {
        self.init(
            id: String(profile.id),
            soundCloudData: try JSONEncoder().encode(profile)
        )
    }

    func toSoundCloudProfile() -> SoundCloudProfile? {
        try? JSONDecoder().decode(SoundCloudProfile.self, from: soundCloudData)
    }
}
