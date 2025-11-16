import Foundation

/// Backend API client for SoundCloud operations
@MainActor
class BackendAPI {
    static let shared = BackendAPI()

    private let baseURL = "https://mixbridge.vercel.app"
    private let keychain = KeychainManager.shared

    private init() {}

    // MARK: - Request Helper

    private func makeRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let sessionToken = keychain.getAccessToken() else {
            print("❌ [BackendAPI] No session token")
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)\(path)") else {
            print("❌ [BackendAPI] Invalid URL: \(baseURL)\(path)")
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        print("📤 [BackendAPI] \(method) \(path)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [BackendAPI] Invalid HTTP response")
            throw APIError.invalidResponse
        }

        print("📊 [BackendAPI] Status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("❌ [BackendAPI] Error \(httpResponse.statusCode): \(errorBody)")

            if httpResponse.statusCode == 401 {
                throw APIError.notAuthenticated
            }
            throw APIError.serverError(httpResponse.statusCode)
        }

        if let responseStr = String(data: data, encoding: .utf8) {
            print("📥 [BackendAPI] Response preview: \(String(responseStr.prefix(200)))...")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - SoundCloud Operations

    /// Get stream URL for a track (requires SoundCloud auth)
    func getStreamURL(trackId: String) async throws -> StreamResponse {
        return try await makeRequest(path: "/api/mobile/stream/\(trackId)")
    }

    /// Get playlist with tracks from backend
    func getPlaylist(playlistId: String) async throws -> PlaylistResponse {
        return try await makeRequest(path: "/api/mobile/playlist/\(playlistId)")
    }

    /// Get liked tracks from backend (fresh from SoundCloud)
    func getLikedTracks(limit: Int = 50, offset: Int = 0) async throws -> LikedTracksResponse {
        return try await makeRequest(path: "/api/mobile/tracks/liked?limit=\(limit)&offset=\(offset)")
    }
}

// MARK: - Response Models

struct StreamResponse: Codable {
    let stream_url: String
    let stream_type: String
    let track_id: String
}

struct PlaylistResponse: Codable {
    let playlist: SoundCloudPlaylist
}

struct LikedTracksResponse: Codable {
    let tracks: [SoundCloudTrack]
    let next_href: String?
}

// MARK: - Errors

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
