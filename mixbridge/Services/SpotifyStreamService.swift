//
//  SpotifyStreamService.swift
//  mixbridge
//
//  Handles Spotify streaming via spotdl Railway API.
//  Converts Spotify URLs to direct HTTPS stream URLs for playback and download.
//

import Foundation

/// Response from /spotify/stream endpoint
nonisolated(unsafe) struct SpotifyStreamResponse: Codable, Sendable {
    let streamURL: String
    let format: String
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
    let coverUrl: String
    let youtubeUrl: String

    enum CodingKeys: String, CodingKey {
        case streamURL = "stream_url"
        case format
        case title
        case artist
        case album
        case durationMs = "duration_ms"
        case coverUrl = "cover_url"
        case youtubeUrl = "youtube_url"
    }
}

/// Spotify streaming service using Railway spotdl API
actor SpotifyStreamService {
    static let shared = SpotifyStreamService()

    private let apiURL = "https://exemplary-mindfulness-production.up.railway.app"

    private init() {}

    /// Get stream URL for a Spotify track
    /// - Parameter spotifyUrl: Full Spotify URL (e.g., https://open.spotify.com/track/xxx)
    /// - Returns: Stream response with direct HTTPS URL (expires in ~6 hours)
    func getStreamURL(spotifyUrl: String) async throws -> SpotifyStreamResponse {
        guard spotifyUrl.contains("spotify.com") || spotifyUrl.contains("spotify:") else {
            throw SpotifyStreamError.invalidURL
        }

        guard let url = URL(string: "\(apiURL)/spotify/stream") else {
            throw SpotifyStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": spotifyUrl])
        request.timeoutInterval = 60

        logInfo(.network, "Fetching Spotify stream URL for: \(spotifyUrl)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyStreamError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            logError(.network, "Spotify stream request failed: HTTP \(httpResponse.statusCode)")
            if let errorBody = String(data: data, encoding: .utf8) {
                logError(.network, "Error body: \(errorBody)")
            }
            throw SpotifyStreamError.serverError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(SpotifyStreamResponse.self, from: data)
        logInfo(.network, "Got Spotify stream: \(decoded.format)")
        return decoded
    }

    /// Download a Spotify track as binary audio
    /// - Parameter spotifyUrl: Full Spotify URL
    /// - Returns: Audio data and metadata headers
    func downloadTrack(spotifyUrl: String) async throws -> (data: Data, title: String?, artist: String?, album: String?) {
        guard spotifyUrl.contains("spotify.com") || spotifyUrl.contains("spotify:") else {
            throw SpotifyStreamError.invalidURL
        }

        guard let url = URL(string: "\(apiURL)/spotify/download") else {
            throw SpotifyStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": spotifyUrl])
        request.timeoutInterval = 120

        logInfo(.downloads, "Downloading Spotify track: \(spotifyUrl)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyStreamError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            logError(.downloads, "Spotify download failed: HTTP \(httpResponse.statusCode)")
            throw SpotifyStreamError.serverError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw SpotifyStreamError.emptyResponse
        }

        let title = httpResponse.value(forHTTPHeaderField: "X-Track-Title")
        let artist = httpResponse.value(forHTTPHeaderField: "X-Track-Artist")
        let album = httpResponse.value(forHTTPHeaderField: "X-Track-Album")

        logInfo(.downloads, "Spotify download complete: \(data.count) bytes")
        return (data, title, artist, album)
    }
}

enum SpotifyStreamError: LocalizedError {
    case invalidURL
    case networkError
    case serverError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Spotify URL"
        case .networkError:
            return "Network error"
        case .serverError(let code):
            return "Server error (\(code))"
        case .emptyResponse:
            return "Empty response from server"
        }
    }
}
