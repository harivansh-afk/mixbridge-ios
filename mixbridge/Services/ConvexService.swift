import Foundation

/// Convex client for all data operations
/// Calls Convex actions that handle caching and SoundCloud API fetching automatically
final class ConvexService {
    nonisolated static let shared = ConvexService()

    private let deploymentUrl = "https://avid-falcon-471.convex.cloud"
    private let apiBaseUrl = "https://mixbridge.app"

    private init() {}

    // MARK: - Core API Methods

    private func query<T: Codable>(_ path: String, args: [String: Any] = [:]) async throws -> T {
        let url = URL(string: "\(deploymentUrl)/api/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": path,
            "args": args,
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }

        let convexResponse = try JSONDecoder().decode(ConvexResponse<T>.self, from: data)

        guard convexResponse.status == "success" else {
            throw ConvexError.queryFailed(convexResponse.errorMessage ?? "Unknown error")
        }

        guard let value = convexResponse.value else {
            throw ConvexError.noData
        }

        return value
    }

    private func action<T: Codable>(_ path: String, args: [String: Any] = [:]) async throws -> T {
        let url = URL(string: "\(deploymentUrl)/api/action")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": path,
            "args": args,
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }

        let convexResponse = try JSONDecoder().decode(ConvexResponse<T>.self, from: data)

        guard convexResponse.status == "success" else {
            throw ConvexError.actionFailed(convexResponse.errorMessage ?? "Unknown error")
        }

        guard let value = convexResponse.value else {
            throw ConvexError.noData
        }

        return value
    }

    @discardableResult
    private func mutation(_ path: String, args: [String: Any] = [:]) async throws -> String? {
        try await mutationGeneric(path, args: args)
    }

    /// Generic mutation that can decode any Codable return type
    @discardableResult
    private func mutationGeneric<T: Codable>(_ path: String, args: [String: Any] = [:]) async throws -> T? {
        let url = URL(string: "\(deploymentUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "path": path,
            "args": args,
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }

        let convexResponse = try JSONDecoder().decode(ConvexResponse<T>.self, from: data)

        guard convexResponse.status == "success" else {
            throw ConvexError.mutationFailed(convexResponse.errorMessage ?? "Unknown error")
        }

        return convexResponse.value
    }

    // MARK: - Data Fetching (Convex Actions - Auto-fetch from SoundCloud if needed)

    /// Get user's liked tracks
    /// - Parameter forceRefresh: If true, bypasses cache and fetches directly from SoundCloud
    func getLikedTracks(userId: String, forceRefresh: Bool = false) async throws -> [SoundCloudTrack] {
        var args: [String: Any] = ["userId": userId]
        if forceRefresh {
            args["forceRefresh"] = true
        }
        let result: ConvexTracksResponse = try await action(
            "actions/likedTracks:get",
            args: args
        )
        return result.tracks
    }

    /// Get user's playlists
    /// - Parameter forceRefresh: If true, bypasses cache and fetches directly from SoundCloud
    func getPlaylists(userId: String, forceRefresh: Bool = false) async throws -> [SoundCloudPlaylist] {
        var args: [String: Any] = ["userId": userId]
        if forceRefresh {
            args["forceRefresh"] = true
        }
        let result: ConvexPlaylistsResponse = try await action(
            "actions/playlists:getAll",
            args: args
        )
        return result.playlists
    }

    /// Get tracks for a specific playlist
    /// - Parameter forceRefresh: If true, bypasses cache and fetches directly from SoundCloud
    func getPlaylistTracks(userId: String, playlistId: String, forceRefresh: Bool = false) async throws -> [SoundCloudTrack] {
        let playlist = try await getPlaylist(userId: userId, playlistId: playlistId, forceRefresh: forceRefresh)
        return playlist.tracks ?? []
    }

    /// Get playlist metadata (and tracks when included) for a specific playlist.
    /// - Note: This is used to ensure playlist rows exist locally even when opened from Search/Artist.
    func getPlaylist(userId: String, playlistId: String, forceRefresh: Bool = false) async throws -> SoundCloudPlaylist {
        var args: [String: Any] = ["userId": userId, "playlistId": playlistId]
        if forceRefresh {
            args["forceRefresh"] = true
        }
        let result: ConvexPlaylistResponse = try await action(
            "actions/playlists:getTracks",
            args: args
        )
        return result.playlist
    }

    /// Search for tracks, playlists, and users
    /// - Parameter forceRefresh: If true, bypasses cache and fetches directly from SoundCloud
    func search(userId: String, query: String, limit: Int = 20, forceRefresh: Bool = false) async throws -> SearchResult {
        var args: [String: Any] = ["userId": userId, "query": query, "limit": limit]
        if forceRefresh {
            args["forceRefresh"] = true
        }
        return try await action(
            "actions/search:search",
            args: args
        )
    }

    /// Get user profile
    /// - Parameter forceRefresh: If true, bypasses cache and fetches directly from SoundCloud
    func getUserProfile(userId: String, forceRefresh: Bool = false) async throws -> SoundCloudProfile {
        var args: [String: Any] = ["userId": userId]
        if forceRefresh {
            args["forceRefresh"] = true
        }
        let result: ConvexProfileResponse = try await action(
            "actions/profile:get",
            args: args
        )
        return result.profile
    }

    /// Get play history
    func getPlayHistory(userId: String, limit: Int = 100) async throws -> [ConvexPlayHistory] {
        return try await query(
            "playHistory:getPlayHistory",
            args: ["userId": userId, "limit": limit]
        )
    }

    /// Get AI discoveries
    func getDiscoveries(userId: String, limit: Int = 20) async throws -> [ConvexDiscovery] {
        return try await query(
            "discoveries:getDiscoveries",
            args: ["userId": userId, "limit": limit]
        )
    }

    // MARK: - Queue Operations

    /// Get queue document with tracks for a user.
    /// Mirrors Convex `queues:getByUserId` return type.
    func getQueueWithTracks(userId: String) async throws -> QueueWithTracksResponse? {
        try await query(
            "queues:getByUserId",
            args: [
                "userId": userId,
                "paginationOpts": [
                    "numItems": 1000,
                    "cursor": NSNull()
                ] as [String: Any]
            ]
        )
    }

    /// Get queue tracks
    func getQueueTracks(userId: String) async throws -> [ConvexQueueTrack] {
        let queueData = try await getQueueWithTracks(userId: userId)
        return queueData?.tracks ?? []
    }

    /// Add track to queue
    func addTrackToQueue(track: SoundCloudTrack) async throws -> String {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.unauthorized
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let trackData = try JSONEncoder().encode(track)
        let trackDict = try JSONSerialization.jsonObject(with: trackData) as? [String: Any] ?? [:]
        let body: [String: Any] = ["track": trackDict]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        if httpResponse.statusCode == 409 {
            throw ConvexError.alreadyInQueue
        }

        if httpResponse.statusCode == 401 {
            await AuthManager.shared.logout()
            throw ConvexError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let trackResponse = json["track"] as? [String: Any],
           let queueTrackId = trackResponse["id"] as? String {
            return queueTrackId
        }

        throw ConvexError.noData
    }

    /// Remove track from queue
    func removeTrackFromQueue(queueTrackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.unauthorized
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue/\(queueTrackId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    /// Reorder queue
    func reorderQueue(fromIndex: Int, toIndex: Int) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.unauthorized
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue/reorder")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["fromIndex": fromIndex, "toIndex": toIndex]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    /// Replace entire queue with new tracks (clears existing and sets new)
    /// Returns array of inserted queue track documents with Convex IDs
    func setQueue(tracks: [SoundCloudTrack]) async throws -> [QueueBatchResult] {
        guard let userId = KeychainManager.shared.getUserId() else {
            throw ConvexError.unauthorized
        }

        // Get or create queue
        let queueId = try await getOrCreateQueueId(userId: userId)

        // Clear existing tracks
        try await mutation("queues:clearTracks", args: ["queueId": queueId])

        // Add new tracks in batch
        guard !tracks.isEmpty else { return [] }

        let trackData = try tracks.map { track -> [String: Any] in
            let data = try JSONEncoder().encode(track)
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return [
                "trackId": String(track.id),
                "source": "soundcloud",
                "title": track.title,
                "artist": track.user.username,
                "duration": track.duration,
                "artworkUrl": track.artwork_url as Any,
                "trackData": dict
            ]
        }

        let results: [QueueBatchResult]? = try await mutationGeneric("queues:addTracksBatch", args: [
            "queueId": queueId,
            "tracks": trackData,
            "startPosition": 0
        ])

        return results ?? []
    }

    /// Add multiple tracks to queue at once (appends to end)
    /// Returns array of inserted queue track documents with Convex IDs
    func addTracksToQueueBatch(tracks: [SoundCloudTrack]) async throws -> [QueueBatchResult] {
        guard let userId = KeychainManager.shared.getUserId() else {
            throw ConvexError.unauthorized
        }

        // Get or create queue
        let queueId = try await getOrCreateQueueId(userId: userId)

        // Get current queue to find start position and filter duplicates
        let currentQueue = try await getQueueTracks(userId: userId)
        let existingTrackIds = Set(currentQueue.map { $0.trackId })
        let newTracks = tracks.filter { !existingTrackIds.contains(String($0.id)) }

        guard !newTracks.isEmpty else { return [] }

        let startPosition = currentQueue.count

        let trackData = try newTracks.map { track -> [String: Any] in
            let data = try JSONEncoder().encode(track)
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return [
                "trackId": String(track.id),
                "source": "soundcloud",
                "title": track.title,
                "artist": track.user.username,
                "duration": track.duration,
                "artworkUrl": track.artwork_url as Any,
                "trackData": dict
            ]
        }

        let results: [QueueBatchResult]? = try await mutationGeneric("queues:addTracksBatch", args: [
            "queueId": queueId,
            "tracks": trackData,
            "startPosition": startPosition
        ])

        return results ?? []
    }

    /// Clear entire queue
    /// Uses direct Convex mutation - no REST API intermediary
    func clearQueue() async throws {
        guard let userId = KeychainManager.shared.getUserId() else {
            throw ConvexError.unauthorized
        }

        let queueId = try await getOrCreateQueueId(userId: userId)
        try await mutation("queues:clearTracks", args: ["queueId": queueId])
    }

    /// Helper: Get or create queue for user, returns queue ID
    private func getOrCreateQueueId(userId: String) async throws -> String {
        // Try to get existing queue
        let existingQueue: QueueWithTracksResponse? = try await query(
            "queues:getByUserId",
            args: ["userId": userId]
        )

        if let queue = existingQueue, let queueId = queue._id {
            return queueId
        }

        // Create new queue
        let newQueueId: String? = try await mutation("queues:create", args: ["userId": userId])
        guard let queueId = newQueueId else {
            throw ConvexError.noData
        }
        return queueId
    }

    // MARK: - Mutations

    /// Log a track play to history with session tracking
    func addPlay(userId: String, track: SoundCloudTrack, sessionId: String, queueIndex: Int?) async throws {
        let trackData = try JSONEncoder().encode(track)
        let trackDict = try JSONSerialization.jsonObject(with: trackData) as? [String: Any] ?? [:]

        var args: [String: Any] = [
            "userId": userId,
            "trackId": String(track.id),
            "source": "soundcloud",
            "trackData": trackDict,
            "sessionId": sessionId,
            "duration": Double(track.duration) / 1000.0  // Convert ms to seconds
        ]

        if let queueIndex = queueIndex {
            args["queueIndex"] = queueIndex
        }

        try await mutation(
            "playHistory:addPlay",
            args: args
        )
    }

    /// Update playback position for an existing play session
    func updatePlayPosition(sessionId: String, userId: String, playbackPosition: Double, duration: Double) async throws {
        try await mutation(
            "playHistory:updatePlayPosition",
            args: [
                "sessionId": sessionId,
                "userId": userId,
                "playbackPosition": playbackPosition,
                "duration": duration
            ]
        )
    }

    /// Like a track
    func likeTrack(trackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.unauthorized
        }

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    /// Unlike a track
    func unlikeTrack(trackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.unauthorized
        }

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    /// Delete all user data
    func deleteAllUserData(userId: String) async throws {
        try await mutation(
            "accountDeletion:deleteAllUserData",
            args: ["userId": userId]
        )
    }

    // MARK: - Stream URL (Direct CDN Access)

    /// Get stream URL with OAuth token for direct SoundCloud CDN access
    /// This bypasses the HLS proxy, reducing latency by ~200-400ms
    func getDirectStreamURL(trackId: String) async throws -> ConvexStreamResponse {
        guard let userId = KeychainManager.shared.getUserId() else {
            throw ConvexError.notAuthenticated
        }

        return try await action("actions/stream:getStreamUrl", args: [
            "userId": userId,
            "trackId": trackId
        ])
    }
}

// MARK: - Response Types

struct ConvexResponse<T: Codable>: Codable {
    let status: String
    let value: T?
    let errorMessage: String?
}

struct ConvexTracksResponse: Codable {
    let tracks: [SoundCloudTrack]
    let source: String?
}

struct ConvexPlaylistsResponse: Codable {
    let playlists: [SoundCloudPlaylist]
    let source: String?
}

struct ConvexPlaylistResponse: Codable {
    let playlist: SoundCloudPlaylist
    let source: String?
}

struct ConvexProfileResponse: Codable {
    let profile: SoundCloudProfile
    let source: String?
}

struct SearchResult: Codable {
    let tracks: [SoundCloudTrack]
    let playlists: [SoundCloudPlaylist]
    let users: [SoundCloudUser]
}

/// Result from addTracksBatch mutation - contains Convex IDs for each inserted track
struct QueueBatchResult: Codable {
    let _id: String      // Convex queueTracks document ID
    let trackId: String  // SoundCloud track ID
    let position: Int    // Position in queue
}

// MARK: - Errors

enum ConvexError: LocalizedError {
    case requestFailed
    case queryFailed(String)
    case actionFailed(String)
    case mutationFailed(String)
    case noData
    case alreadyInQueue
    case unauthorized
    case notAuthenticated
    case notFound

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Unable to connect. Please check your internet connection."
        case .queryFailed(let message):
            return message
        case .actionFailed(let message):
            return message
        case .mutationFailed(let message):
            return message
        case .noData:
            return "No data available"
        case .alreadyInQueue:
            return "Track is already in your queue"
        case .unauthorized:
            return "Please sign in to continue"
        case .notAuthenticated:
            return "Please sign in to play music"
        case .notFound:
            return "Item not found"
        }
    }
}
