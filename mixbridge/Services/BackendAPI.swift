import Foundation

/// Backend API client for streaming operations only
/// All data fetching is handled by ConvexService
final class BackendAPI {
    static let shared = BackendAPI()

    private let baseURL = "https://mixbridge.app"
    private let keychain = KeychainManager.shared

    private init() {}

    // MARK: - Streaming

    /// Get stream URL for a track (required for playback)
    func getStreamURL(trackId: String) async throws -> StreamResponse {
        guard let sessionToken = keychain.getAccessToken() else {
            throw StreamError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/mobile/stream/\(trackId)") else {
            throw StreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            await AuthManager.shared.logout()
            throw StreamError.notAuthenticated
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StreamError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(StreamResponse.self, from: data)
    }
}

// MARK: - Response Models

struct StreamResponse: Codable {
    let stream_url: String
    let stream_type: String
    let track_id: String
}

// MARK: - Errors

enum StreamError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to play music"
        case .invalidURL:
            return "Invalid stream URL"
        case .invalidResponse:
            return "Unable to load stream"
        case .serverError(let code):
            return "Stream error (\(code))"
        }
    }
}
