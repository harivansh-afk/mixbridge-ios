//
//  PersistedUserProfile.swift
//  MixBridgeDomain
//
//  Cached user profile. Full SoundCloudProfile stored in soundCloudData blob.
//

import Foundation

public struct PersistedUserProfile: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var updatedAt: Date
    public var soundCloudData: Data

    public init(id: String, updatedAt: Date = Date(), soundCloudData: Data) {
        self.id = id
        self.updatedAt = updatedAt
        self.soundCloudData = soundCloudData
    }
}
