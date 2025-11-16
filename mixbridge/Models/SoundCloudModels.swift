import Foundation

// MARK: - SoundCloud Track Models

struct SoundCloudTrack: Codable {
    let id: Int
    let title: String
    let user: SoundCloudUser
    let duration: Int
    let artwork_url: String?
    let permalink_url: String?
    let playback_count: Int?
    let genre: String?
    let description: String?
    let created_at: String?
    let waveform_url: String?
    let likes_count: Int?
    let comment_count: Int?
    let reposts_count: Int?
}

struct SoundCloudUser: Codable {
    let id: Int
    let username: String
    let avatar_url: String?
    let permalink_url: String?
    let followers_count: Int?
    let followings_count: Int?
}

struct SoundCloudPlaylist: Codable {
    let id: Int
    let title: String
    let user: SoundCloudUser
    let duration: Int
    let artwork_url: String?
    let permalink_url: String?
    let track_count: Int?
    let tracks: [SoundCloudTrack]?
    let description: String?
    let genre: String?
    let created_at: String?
}

struct SoundCloudProfile: Codable {
    let id: Int
    let username: String
    let full_name: String?
    let first_name: String?
    let last_name: String?
    let avatar_url: String?
    let permalink_url: String?
    let followers_count: Int?
    let followings_count: Int?
    let track_count: Int?
    let playlist_count: Int?
    let likes_count: Int?
    let plan: String?
    let description: String?
    let city: String?
    let country: String?
}
