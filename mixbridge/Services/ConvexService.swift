import Foundation

/// Convex HTTP API client - no SDK needed, works immediately
@MainActor
class ConvexService {
    static let shared = ConvexService()

    private let deploymentUrl = "https://fine-marlin-376.convex.cloud"

    private init() {}

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

        print("📤 [Convex] Request to: \(path)")
        print("📤 [Convex] Args: \(args)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Convex] HTTP error: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
            throw ConvexError.requestFailed
        }

        // Debug: Print raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📥 [Convex] Raw response: \(rawResponse)")
        }

        let convexResponse = try JSONDecoder().decode(ConvexResponse<T>.self, from: data)

        guard convexResponse.status == "success" else {
            print("❌ [Convex] Query failed: \(convexResponse.errorMessage ?? "Unknown")")
            throw ConvexError.queryFailed(convexResponse.errorMessage ?? "Unknown error")
        }

        if let value = convexResponse.value {
            print("✅ [Convex] Query succeeded with value!")
            return value
        } else {
            print("⚠️ [Convex] Query succeeded but value is null (not cached yet)")
            throw ConvexError.noData
        }
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
        // Note: The query returns full queue with tracks embedded
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
    case noData

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request to Convex failed"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .noData:
            return "No data in cache"
        }
    }
}
