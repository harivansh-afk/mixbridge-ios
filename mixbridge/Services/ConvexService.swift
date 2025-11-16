import Foundation

/// Convex HTTP API client - no SDK needed, works immediately
@MainActor
class ConvexService {
    static let shared = ConvexService()

    private let deploymentUrl = "https://avid-falcon-471.convex.cloud"

    private init() {}

    // MARK: - API Base URL

    private let apiBaseUrl = "https://mixbridge.vercel.app"

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
        print("📡 [ConvexService] Fetching queue tracks for userId: \(userId)")

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

        let tracks = queueData?.tracks ?? []
        print("📊 [ConvexService] Convex returned \(tracks.count) queue tracks")

        if !tracks.isEmpty {
            print("📋 [ConvexService] Track IDs from Convex:")
            for track in tracks {
                print("  - [\(track.position)] \(track.trackId): \(track.title)")
            }
        }

        return tracks
    }

    // MARK: - Queue Mutations

    func addTrackToQueue(trackId: String, trackData: [String: Any]) async throws -> String {
        print("🔐 [Queue] Checking authentication...")
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            print("❌ [Queue] No auth token available")
            throw ConvexError.requestFailed
        }
        print("✅ [Queue] Auth token found (length: \(authToken.count))")

        let url = URL(string: "\(apiBaseUrl)/api/queue")!
        print("📤 [Queue] URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["track": trackData]
        print("📦 [Queue] Track data keys: \(trackData.keys.joined(separator: ", "))")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("✅ [Queue] Request body serialized successfully")
        } catch {
            print("❌ [Queue] Failed to serialize request body: \(error)")
            throw error
        }

        print("📤 [Queue] Sending request for trackId: \(trackId)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Queue] Invalid response type")
            throw ConvexError.requestFailed
        }

        print("📥 [Queue] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Queue] HTTP error: \(httpResponse.statusCode)")
            if let errorResponse = String(data: data, encoding: .utf8) {
                print("❌ [Queue] Error response body: \(errorResponse)")
            }
            throw ConvexError.requestFailed
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [Queue] Success response: \(responseString)")

            // Parse response to extract queue track ID
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let track = json["track"] as? [String: Any],
               let queueTrackId = track["id"] as? String {
                print("✅ [Queue] Track added successfully! Queue track ID: \(queueTrackId)")
                return queueTrackId
            }
        }

        print("⚠️ [Queue] Track added but couldn't extract queue track ID")
        throw ConvexError.noData
    }

    func reorderQueue(fromIndex: Int, toIndex: Int) async throws {
        print("🔐 [Queue] Checking authentication for reorder...")
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            print("❌ [Queue] No auth token available")
            throw ConvexError.requestFailed
        }
        print("✅ [Queue] Auth token found")

        let url = URL(string: "\(apiBaseUrl)/api/queue/reorder")!
        print("📤 [Queue] POST URL: \(url.absoluteString)")
        print("📤 [Queue] Reordering: from \(fromIndex) to \(toIndex)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "fromIndex": fromIndex,
            "toIndex": toIndex
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Queue] Invalid response type")
            throw ConvexError.requestFailed
        }

        print("📥 [Queue] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Queue] HTTP error: \(httpResponse.statusCode)")
            if let errorResponse = String(data: data, encoding: .utf8) {
                print("❌ [Queue] Error response body: \(errorResponse)")
            }
            throw ConvexError.requestFailed
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [Queue] Success response: \(responseString)")
        }
        print("✅ [Queue] Tracks reordered successfully!")
    }

    func removeTrackFromQueue(queueTrackId: String) async throws {
        print("🔐 [Queue] Checking authentication for delete...")
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            print("❌ [Queue] No auth token available")
            throw ConvexError.requestFailed
        }
        print("✅ [Queue] Auth token found")

        let url = URL(string: "\(apiBaseUrl)/api/queue/\(queueTrackId)")!
        print("📤 [Queue] DELETE URL: \(url.absoluteString)")
        print("📤 [Queue] Removing queue track ID: \(queueTrackId)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Queue] Invalid response type")
            throw ConvexError.requestFailed
        }

        print("📥 [Queue] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Queue] HTTP error: \(httpResponse.statusCode)")
            if let errorResponse = String(data: data, encoding: .utf8) {
                print("❌ [Queue] Error response body: \(errorResponse)")
            }
            throw ConvexError.requestFailed
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [Queue] Success response: \(responseString)")
        }
        print("✅ [Queue] Track removed successfully!")
    }

    // MARK: - Like Mutations

    func likeTrack(trackId: String) async throws {
        print("🔐 [Like] Checking authentication...")
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            print("❌ [Like] No auth token available")
            throw ConvexError.requestFailed
        }
        print("✅ [Like] Auth token found")

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!
        print("📤 [Like] URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        print("📤 [Like] Sending like request for trackId: \(trackId)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Like] Invalid response type")
            throw ConvexError.requestFailed
        }

        print("📥 [Like] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Like] HTTP error: \(httpResponse.statusCode)")
            if let errorResponse = String(data: data, encoding: .utf8) {
                print("❌ [Like] Error response body: \(errorResponse)")
            }
            throw ConvexError.requestFailed
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [Like] Success response: \(responseString)")
        }
        print("✅ [Like] Track liked successfully!")
    }

    func unlikeTrack(trackId: String) async throws {
        print("🔐 [Unlike] Checking authentication...")
        guard let authToken = KeychainManager.shared.getAccessToken() else {
            print("❌ [Unlike] No auth token available")
            throw ConvexError.requestFailed
        }
        print("✅ [Unlike] Auth token found")

        let url = URL(string: "\(apiBaseUrl)/api/soundcloud/likes/\(trackId)")!
        print("📤 [Unlike] URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        print("📤 [Unlike] Sending unlike request for trackId: \(trackId)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Unlike] Invalid response type")
            throw ConvexError.requestFailed
        }

        print("📥 [Unlike] Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Unlike] HTTP error: \(httpResponse.statusCode)")
            if let errorResponse = String(data: data, encoding: .utf8) {
                print("❌ [Unlike] Error response body: \(errorResponse)")
            }
            throw ConvexError.requestFailed
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [Unlike] Success response: \(responseString)")
        }
        print("✅ [Unlike] Track unliked successfully!")
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
