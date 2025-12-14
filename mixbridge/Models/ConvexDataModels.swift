import Foundation

// MARK: - Convex Base Types

typealias ConvexId = String

// MARK: - Queue Models

struct ConvexQueue: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let name: String?
    let currentPosition: Double
    let currentTime: Double
    let playbackState: String
}

struct ConvexQueueTrack: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let queueId: ConvexId
    let trackId: String
    let source: String
    let title: String
    let artist: String
    let duration: Double
    let artworkUrl: String?
    let trackData: SoundCloudTrack
    let position: Double
}

// MARK: - Cached Data Models

struct ConvexUserProfile: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let profile: SoundCloudProfile
    let updatedAt: Double
}

struct ConvexCachedLikedTracks: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let tracks: [SoundCloudTrack]
    let updatedAt: Double
}

struct ConvexCachedPlaylists: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let playlists: [SoundCloudPlaylist]
    let updatedAt: Double
}

struct ConvexPlaylistTracks: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let playlistId: String
    let tracks: [SoundCloudTrack]
    let updatedAt: Double
}

// MARK: - Play History Models

struct ConvexPlayHistory: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let trackId: String
    let source: String
    let trackData: SoundCloudTrack
    let playedAt: Double
    // Position tracking fields (optional for backward compatibility)
    let sessionId: String?
    let queueIndex: Int?
    let playbackPosition: Double?
    let duration: Double?
    let listenedPercentage: Double?
    let lastUpdated: Double?
}

// MARK: - Discovery Models

struct ConvexDiscovery: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let userId: String
    let trackId: String
    let trackData: SoundCloudTrack
    let discoveryReason: String
    let searchQuery: String
    let vibeMatch: String
    let qualityScore: Double
    let discoveredAt: Double
    let addedToQueue: Bool?
}

// MARK: - Track Analysis Models

struct ConvexTrackAnalysis: Codable {
    let _id: ConvexId
    let _creationTime: Double
    let trackId: String
    let source: String
    let bpm: Double?
    let key: String?
    let mode: String?
    let energy: Double?
    let danceability: Double?
    let loudness: Double?
    let valence: Double?
    let acousticness: Double?
    let instrumentalness: Double?
    let timeSignature: Double?
    let error: String?
}

// MARK: - Queue Response

struct QueueWithTracksResponse: Codable {
    let _id: ConvexId?
    let _creationTime: Double?
    let userId: String?
    let currentPosition: Double?
    let currentTime: Double?
    let playbackState: String?
    let tracks: [ConvexQueueTrack]
    let continueCursor: String?
    let isDone: Bool?
}

// MARK: - Stream Response

/// Response from Convex stream action with OAuth token for direct CDN access
struct ConvexStreamResponse: Codable {
    let stream_url: String
    let stream_type: String
    let quality: String
    let access_token: String
    let track_id: String
}
