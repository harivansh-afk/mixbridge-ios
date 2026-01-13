//
//  PersistedModels+SoundCloud.swift
//  mixbridge
//
//  Extensions to convert SoundCloud models to persisted models.
//

import Foundation
import MixBridgeDB

// MARK: - PersistedTrack + SoundCloudTrack

extension PersistedTrack {
    init(from scTrack: SoundCloudTrack) {
        let artworkUrl = scTrack.artwork_url ?? scTrack.user.avatar_url ?? ""

        self.init(
            id: String(scTrack.id),
            title: scTrack.title,
            artist: scTrack.user.username,
            artistId: scTrack.user.id,
            album: scTrack.genre ?? "",
            artwork: artworkUrl.upgradeArtworkQuality(),
            duration: Double(scTrack.duration) / 1000.0,
            playbackCount: scTrack.playback_count ?? 0,
            likesCount: scTrack.likes_count ?? 0,
            genre: scTrack.genre,
            createdAt: Date(),
            updatedAt: Date(),
            soundCloudData: try? JSONEncoder().encode(scTrack)
        )
    }

    func toTrack() -> Track {
        Track(
            id: id,
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration
        )
    }

    var soundCloudTrack: SoundCloudTrack? {
        guard let data = soundCloudData else { return nil }
        return try? JSONDecoder().decode(SoundCloudTrack.self, from: data)
    }
}

// MARK: - PersistedPlaylist + SoundCloudPlaylist

extension PersistedPlaylist {
    init(from scPlaylist: SoundCloudPlaylist) {
        self.init(
            id: String(scPlaylist.id),
            name: scPlaylist.title,
            creator: scPlaylist.user.username,
            creatorId: scPlaylist.user.id,
            artwork: scPlaylist.primaryArtworkUrl,
            trackCount: scPlaylist.track_count ?? scPlaylist.tracks?.count ?? 0,
            duration: scPlaylist.duration,
            description: scPlaylist.description,
            genre: scPlaylist.genre,
            createdAt: Date(),
            lastUpdated: Date(),
            soundCloudData: try? JSONEncoder().encode(scPlaylist)
        )
    }

    func toPlaylist() -> Playlist {
        Playlist(
            id: id,
            name: name,
            creator: creator,
            artwork: artwork,
            tracks: [],
            lastUpdated: lastUpdated,
            isUserCreated: isUserCreated
        )
    }

    func toPlaylist(with tracks: [Track]) -> Playlist {
        Playlist(
            id: id,
            name: name,
            creator: creator,
            artwork: artwork,
            tracks: tracks,
            lastUpdated: lastUpdated,
            isUserCreated: isUserCreated
        )
    }

    var soundCloudPlaylist: SoundCloudPlaylist? {
        guard let data = soundCloudData else { return nil }
        return try? JSONDecoder().decode(SoundCloudPlaylist.self, from: data)
    }
}
