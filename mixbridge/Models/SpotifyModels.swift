//
//  SpotifyModels.swift
//  mixbridge
//
//  Spotify Web API models - matches official Spotify API structure
//  https://developer.spotify.com/documentation/web-api
//

import Foundation

// MARK: - Spotify Track

struct SpotifyTrack: Codable, Sendable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let duration_ms: Int
    let explicit: Bool?
    let popularity: Int?
    let uri: String?
    let preview_url: String?
    let track_number: Int?
    let disc_number: Int?
    let is_local: Bool?
    let external_urls: SpotifyExternalUrls?

    /// Primary artist name (joined if multiple)
    var artistName: String {
        artists.map { $0.name }.joined(separator: ", ")
    }

    /// Primary artwork URL (largest image from album)
    var artworkUrl: String? {
        album?.images?.first?.url
    }

    /// Duration in seconds
    var durationSeconds: Double {
        Double(duration_ms) / 1000.0
    }
}

// MARK: - Spotify Artist

struct SpotifyArtist: Codable, Sendable {
    let id: String
    let name: String
    let uri: String?
    let external_urls: SpotifyExternalUrls?
    let images: [SpotifyImage]?
    let genres: [String]?
    let popularity: Int?
    let followers: SpotifyFollowers?

    /// Primary image URL
    var imageUrl: String? {
        images?.first?.url
    }
}

// MARK: - Spotify Album

struct SpotifyAlbum: Codable, Sendable {
    let id: String
    let name: String
    let album_type: String?
    let artists: [SpotifyArtist]?
    let images: [SpotifyImage]?
    let release_date: String?
    let total_tracks: Int?
    let uri: String?
    let external_urls: SpotifyExternalUrls?

    /// Primary artwork URL
    var artworkUrl: String? {
        images?.first?.url
    }
}

// MARK: - Spotify Playlist

struct SpotifyPlaylistFull: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let owner: SpotifyOwner
    let images: [SpotifyImage]?
    let tracks: SpotifyPlaylistTracksRef?
    let uri: String?
    let external_urls: SpotifyExternalUrls?
    let collaborative: Bool?
    let `public`: Bool?
    let snapshot_id: String?
    let followers: SpotifyFollowers?

    /// Primary artwork URL
    var artworkUrl: String? {
        images?.first?.url
    }

    /// Track count
    var trackCount: Int {
        tracks?.total ?? 0
    }
}

// MARK: - Spotify Owner (Playlist owner)

struct SpotifyOwner: Codable, Sendable {
    let id: String
    let display_name: String?
    let uri: String?
    let external_urls: SpotifyExternalUrls?

    /// Display name with fallback
    var name: String {
        display_name ?? id
    }
}

// MARK: - Spotify User Profile

struct SpotifyUserProfile: Codable, Sendable {
    let id: String
    let display_name: String?
    let email: String?
    let images: [SpotifyImage]?
    let uri: String?
    let external_urls: SpotifyExternalUrls?
    let followers: SpotifyFollowers?
    let country: String?
    let product: String?  // "free", "premium", etc.

    /// Display name with fallback
    var name: String {
        display_name ?? id
    }

    /// Primary avatar URL
    var avatarUrl: String? {
        images?.first?.url
    }
}

// MARK: - Supporting Types

struct SpotifyImage: Codable, Sendable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyExternalUrls: Codable, Sendable {
    let spotify: String?
}

struct SpotifyFollowers: Codable, Sendable {
    let total: Int?
}

struct SpotifyPlaylistTracksRef: Codable, Sendable {
    let total: Int
    let href: String?
}

// MARK: - Saved Items (Library)

struct SpotifySavedTrack: Codable, Sendable {
    let added_at: String
    let track: SpotifyTrack
}

struct SpotifySavedAlbum: Codable, Sendable {
    let added_at: String
    let album: SpotifyAlbum
}

struct SpotifyPlaylistTrackItem: Codable, Sendable {
    let added_at: String?
    let track: SpotifyTrack?
    let added_by: SpotifyOwner?
}

// MARK: - Paginated Responses

struct SpotifyPaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?
    let previous: String?
}

typealias SpotifySavedTracksResponse = SpotifyPaginatedResponse<SpotifySavedTrack>
typealias SpotifyPlaylistsResponse = SpotifyPaginatedResponse<SpotifyPlaylistFull>
typealias SpotifyPlaylistTracksResponse = SpotifyPaginatedResponse<SpotifyPlaylistTrackItem>

// MARK: - Search Response

struct SpotifySearchResponse: Codable, Sendable {
    let tracks: SpotifyPaginatedResponse<SpotifyTrack>?
    let artists: SpotifyPaginatedResponse<SpotifyArtist>?
    let albums: SpotifyPaginatedResponse<SpotifyAlbum>?
    let playlists: SpotifyPaginatedResponse<SpotifyPlaylistFull>?
}

// MARK: - Conversion to App Models

extension SpotifyTrack {
    /// Convert to unified SoundCloudTrack for compatibility with existing UI
    func toSoundCloudTrack() -> SoundCloudTrack {
        SoundCloudTrack(
            id: "spotify:\(id)",
            title: name,
            user: SoundCloudUser(
                id: artists.first?.id ?? "0",
                username: artistName,
                avatar_url: artists.first?.imageUrl,
                permalink_url: external_urls?.spotify,
                followers_count: nil,
                followings_count: nil
            ),
            duration: duration_ms,
            artwork_url: artworkUrl,
            permalink_url: external_urls?.spotify,
            playback_count: nil,
            genre: nil,
            description: nil,
            created_at: nil,
            waveform_url: nil,
            likes_count: nil,
            comment_count: nil,
            reposts_count: nil,
            _source: "spotify"
        )
    }
}

extension SpotifyPlaylistFull {
    /// Convert to unified SoundCloudPlaylist for compatibility with existing UI
    func toSoundCloudPlaylist() -> SoundCloudPlaylist? {
        // Create a JSON representation and decode as SoundCloudPlaylist
        let playlistData: [String: Any] = [
            "id": "spotify:\(id)",
            "title": name,
            "user": [
                "id": owner.id,
                "username": owner.name
            ],
            "duration": 0,
            "artwork_url": artworkUrl as Any,
            "track_count": trackCount,
            "_source": "spotify"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: playlistData),
              let playlist = try? JSONDecoder().decode(SoundCloudPlaylist.self, from: jsonData) else {
            return nil
        }
        return playlist
    }
}

extension SpotifyArtist {
    /// Convert to SoundCloudUser for compatibility
    func toSoundCloudUser() -> SoundCloudUser {
        SoundCloudUser(
            id: "spotify:\(id)",
            username: name,
            avatar_url: imageUrl,
            permalink_url: external_urls?.spotify,
            followers_count: followers?.total,
            followings_count: nil
        )
    }
}

extension SpotifyUserProfile {
    /// Convert to SoundCloudProfile for compatibility
    func toSoundCloudProfile() -> SoundCloudProfile? {
        // Create a JSON representation and decode as SoundCloudProfile
        let profileData: [String: Any] = [
            "id": "spotify:\(id)",
            "username": name,
            "avatar_url": avatarUrl as Any,
            "followers_count": followers?.total as Any,
            "_source": "spotify"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: profileData),
              let profile = try? JSONDecoder().decode(SoundCloudProfile.self, from: jsonData) else {
            return nil
        }
        return profile
    }
}

// MARK: - Array Conversions

extension Array where Element == SpotifyTrack {
    func toSoundCloudTracks() -> [SoundCloudTrack] {
        map { $0.toSoundCloudTrack() }
    }
}

extension Array where Element == SpotifySavedTrack {
    func toSoundCloudTracks() -> [SoundCloudTrack] {
        map { $0.track.toSoundCloudTrack() }
    }
}

extension Array where Element == SpotifyArtist {
    func toSoundCloudUsers() -> [SoundCloudUser] {
        map { $0.toSoundCloudUser() }
    }
}
