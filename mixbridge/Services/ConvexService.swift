import Foundation

/// Convex HTTP API client - no SDK needed, works immediately
final class ConvexService {
    static let shared = ConvexService()

    private let deploymentUrl = "https://avid-falcon-471.convex.cloud"

    private init() {}

    // MARK: - API Base URL

    private let apiBaseUrl = "https://mixbridge.app"

    // MARK: - Query

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

        if let value = convexResponse.value {
            return value
        } else {
            throw ConvexError.noData
        }
    }

    // MARK: - Mutation

    private func mutation<T: Codable>(_ path: String, args: [String: Any] = [:]) async throws -> T {
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

        if let value = convexResponse.value {
            return value
        } else {
            throw ConvexError.noData
        }
    }

    @discardableResult
    private func mutationVoid(_ path: String, args: [String: Any] = [:]) async throws -> String? {
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

        let convexResponse = try JSONDecoder().decode(ConvexResponse<String>.self, from: data)

        guard convexResponse.status == "success" else {
            throw ConvexError.mutationFailed(convexResponse.errorMessage ?? "Unknown error")
        }

        return convexResponse.value
    }

    // MARK: - User Profile

    func getUserProfile(userId: String) async throws -> ConvexUserProfile? {
        return try await query("cache:getProfile", args: ["userId": userId])
    }

    // MARK: - Liked Tracks

    func getLikedTracks(userId: String) async throws -> ConvexCachedLikedTracks? {
        return try await query("cache:getLikedTracks", args: ["userId": userId])
    }

    // MARK: - Playlists

    func getPlaylists(userId: String) async throws -> ConvexCachedPlaylists? {
        return try await query("cache:getPlaylists", args: ["userId": userId])
    }

    func getPlaylistTracks(userId: String, playlistId: String) async throws -> ConvexPlaylistTracks? {
        return try await query(
            "cache:getPlaylistTracks",
            args: [
                "userId": userId,
                "playlistId": playlistId
            ]
        )
    }

    // MARK: - Discoveries

    func getDiscoveries(userId: String, limit: Int = 20) async throws -> [ConvexDiscovery] {
        return try await query(
            "discoveries:getDiscoveries",
            args: [
                "userId": userId,
                "limit": limit
            ]
        )
    }

    // MARK: - Play History

    func getPlayHistory(userId: String, limit: Int = 100) async throws -> [ConvexPlayHistory] {
        return try await query(
            "playHistory:getPlayHistory",
            args: [
                "userId": userId,
                "limit": limit
            ]
        )
    }

    /// Log a track play to history (matches Next.js webapp implementation)
    func addPlay(userId: String, trackId: String, trackData: [String: Any]) async throws {
        try await mutationVoid(
            "playHistory:addPlay",
            args: [
                "userId": userId,
                "trackId": trackId,
                "source": "soundcloud",
                "trackData": trackData
            ]
        )
    }

    // MARK: - Queue

    func getQueue(userId: String) async throws -> ConvexQueue? {
        return try await query(
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

    func getQueueTracks(userId: String) async throws -> [ConvexQueueTrack] {
        let queueData: QueueWithTracksResponse? = try await query(
            "queues:getByUserId",
            args: [
                "userId": userId,
                "paginationOpts": [
                    "numItems": 1000,
                    "cursor": NSNull()
                ] as [String: Any]
            ]
        )

        return queueData?.tracks ?? []
    }

    // MARK: - Queue Mutations

    func addTrackToQueue(trackId: String, trackData: [String: Any]) async throws -> String {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.requestFailed
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["track": trackData]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        if httpResponse.statusCode == 409 {
            throw ConvexError.alreadyInQueue
        }

        if httpResponse.statusCode == 401 {
            throw ConvexError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let track = json["track"] as? [String: Any],
           let queueTrackId = track["id"] as? String {
            return queueTrackId
        }

        throw ConvexError.noData
    }

    func reorderQueue(fromIndex: Int, toIndex: Int) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.requestFailed
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue/reorder")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "fromIndex": fromIndex,
            "toIndex": toIndex
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    func removeTrackFromQueue(queueTrackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.requestFailed
        }

        let url = URL(string: "\(apiBaseUrl)/api/queue/\(queueTrackId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    // MARK: - Like Mutations

    func likeTrack(trackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.requestFailed
        }

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    func unlikeTrack(trackId: String) async throws {
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            throw ConvexError.requestFailed
        }

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvexError.requestFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConvexError.requestFailed
        }
    }

    // MARK: - Account Deletion

    func deleteAllUserData(userId: String) async throws {
        try await mutationVoid(
            "accountDeletion:deleteAllUserData",
            args: ["userId": userId]
        )
    }
}

// MARK: - Response Models

struct ConvexResponse<T: Codable>: Codable {
    let status: String
    let value: T?
    let errorMessage: String?
}

// MARK: - Errors

enum ConvexError: LocalizedError {
    case requestFailed
    case queryFailed(String)
    case mutationFailed(String)
    case noData
    case alreadyInQueue
    case unauthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request to Convex failed"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .mutationFailed(let message):
            return "Mutation failed: \(message)"
        case .noData:
            return "No data in cache"
        case .alreadyInQueue:
            return "Track is already in your queue"
        case .unauthorized:
            return "Authentication required"
        case .notFound:
            return "Item not found"
        }
    }
}
