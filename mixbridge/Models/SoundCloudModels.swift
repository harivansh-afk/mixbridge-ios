import Foundation

// MARK: - SoundCloud Track Models

struct SoundCloudTrack: Codable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case user
        case duration
        case artwork_url
        case permalink_url
        case playback_count
        case genre
        case description
        case created_at
        case waveform_url
        case likes_count
        case comment_count
        case reposts_count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyInt(forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        user = try container.decode(SoundCloudUser.self, forKey: .user)
        duration = try container.decode(Int.self, forKey: .duration)
        artwork_url = try container.decodeIfPresent(String.self, forKey: .artwork_url)
        permalink_url = try container.decodeIfPresent(String.self, forKey: .permalink_url)
        playback_count = try container.decodeIfPresent(Int.self, forKey: .playback_count)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
        waveform_url = try container.decodeIfPresent(String.self, forKey: .waveform_url)
        likes_count = try container.decodeIfPresent(Int.self, forKey: .likes_count)
        comment_count = try container.decodeIfPresent(Int.self, forKey: .comment_count)
        reposts_count = try container.decodeIfPresent(Int.self, forKey: .reposts_count)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(user, forKey: .user)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(artwork_url, forKey: .artwork_url)
        try container.encodeIfPresent(permalink_url, forKey: .permalink_url)
        try container.encodeIfPresent(playback_count, forKey: .playback_count)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(created_at, forKey: .created_at)
        try container.encodeIfPresent(waveform_url, forKey: .waveform_url)
        try container.encodeIfPresent(likes_count, forKey: .likes_count)
        try container.encodeIfPresent(comment_count, forKey: .comment_count)
        try container.encodeIfPresent(reposts_count, forKey: .reposts_count)
    }
}

struct SoundCloudUser: Codable, Sendable {
    let id: Int
    let username: String
    let avatar_url: String?
    let permalink_url: String?
    let followers_count: Int?
    let followings_count: Int?
}

struct SoundCloudPlaylist: Codable, Sendable {
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

struct SoundCloudProfile: Codable, Sendable {
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

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) throws -> Int {
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try decodeIfPresent(String.self, forKey: key),
           let intValue = Int(stringValue) {
            return intValue
        }
        let context = DecodingError.Context(
            codingPath: codingPath + [key],
            debugDescription: "Expected Int or String convertible to Int."
        )
        throw DecodingError.typeMismatch(Int.self, context)
    }
}

// MARK: - Track Conversion

extension SoundCloudTrack {
    /// Convert SoundCloud track to app's Track model
    func toTrack() -> Track {
        let artworkUrl = artwork_url ?? user.avatar_url ?? ""
        let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

        return Track(
            id: String(id),
            title: title,
            artist: user.username,
            album: genre ?? "",
            artwork: highQualityArtwork,
            duration: Double(duration) / 1000.0
        )
    }
}

extension Array where Element == SoundCloudTrack {
    /// Convert array of SoundCloud tracks to app's Track models
    func toTracks() -> [Track] {
        map { $0.toTrack() }
    }
}

// MARK: - Playlist Helpers

extension SoundCloudPlaylist {
    /// Best-effort artwork for a playlist.
    /// 1) Use playlist artwork if present.
    /// 2) Otherwise fall back to the first track's artwork (when tracks are included).
    /// 3) Otherwise return an empty string so UI can show a neutral placeholder
    ///    instead of the user's profile picture.
    var primaryArtworkUrl: String {
        if let artwork_url {
            return artwork_url.upgradeArtworkQuality()
        }

        if let trackArtwork = tracks?.first?.artwork_url {
            return trackArtwork.upgradeArtworkQuality()
        }

        return ""
    }
}
