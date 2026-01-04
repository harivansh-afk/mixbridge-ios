//
//  PersistedUserProfile+GRDB.swift
//  MixBridgeDB
//
//  GRDB conformances for PersistedUserProfile.
//

import GRDB
import MixBridgeDomain

extension PersistedUserProfile: @retroactive TableRecord, @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static let databaseTableName = "user_profiles"

    public static var persistenceConflictPolicy: PersistenceConflictPolicy {
        PersistenceConflictPolicy(insert: .replace, update: .replace)
    }
}
