//
//  PersistedQueueModels+SoundCloud.swift
//  mixbridge
//
//  Convenience helpers for queue persistence models.
//

import Foundation
import MixBridgeDB

extension PersistedQueueTrack {
    var soundCloudTrack: SoundCloudTrack? {
        try? JSONDecoder().decode(SoundCloudTrack.self, from: trackData)
    }
}

