import Foundation

/// API client for Mixbridge backend
@MainActor
class MixbridgeAPI {
    static let shared = MixbridgeAPI()

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
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.notAuthenticated
            }
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - API Methods

    /// Get current user profile
    func getProfile() async throws -> UserProfile {
        return try await makeRequest(path: "/api/mobile/me")
    }

    /// Get user's liked tracks
    func getLikedTracks(limit: Int = 50, offset: Int = 0) async throws -> TracksResponse {
        return try await makeRequest(path: "/api/mobile/tracks/liked?limit=\(limit)&offset=\(offset)")
    }

    /// Get stream URL for a track
    func getStreamURL(trackId: String) async throws -> StreamResponse {
        return try await makeRequest(path: "/api/mobile/stream/\(trackId)")
    }
}

// MARK: - Models

struct UserProfile: Codable {
    let user: User
    let soundcloud: SoundCloudProfile

    struct User: Codable {
        let id: String
        let username: String
        let avatar_url: String?
    }

    struct SoundCloudProfile: Codable {
        let id: Int
        let username: String
        let avatar_url: String?
        let permalink_url: String?
        let followers_count: Int?
        let followings_count: Int?
    }
}

struct TracksResponse: Codable {
    let tracks: [SoundCloudTrack]
    let next_href: String?
}

struct SoundCloudTrack: Codable {
    let id: Int
    let title: String
    let user: TrackUser
    let duration: Int
    let artwork_url: String?
    let permalink_url: String?
    let playback_count: Int?

    struct TrackUser: Codable {
        let id: Int
        let username: String
        let avatar_url: String?
    }
}

struct StreamResponse: Codable {
    let stream_url: String
    let stream_type: String
    let track_id: String
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
