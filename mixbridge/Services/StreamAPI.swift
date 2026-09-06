//
//  StreamAPI.swift
//  mixbridge
//
//  Single source of truth for the yt-dlp extraction service base URL
//  (ytdlp-api repo). Used by DownloadManager and SpotifyStreamService.
//

import Foundation

enum StreamAPI {
    /// Base URL of the yt-dlp extraction service (ytdlp-api on spark,
    /// exposed through the Cloudflare tunnel).
    static let baseURL = "https://mixbridge.harivan.sh"

    /// Exchange the app session for a short-lived extraction credential per request.
    @MainActor
    static func authorizedRequest(path: String, sourceURL: String, timeout: TimeInterval) async throws -> URLRequest {
        guard let session = KeychainManager.shared.getAccessToken(),
              !session.hasPrefix("spotify:"),
              let expiry = SessionTokenDecoder.getExpiry(from: session), expiry > Date() else {
            throw StreamAuthorizationError.signInExpired
        }

        var exchange = URLRequest(url: URL(string: "https://mixbridge.app/api/stream-token")!)
        exchange.httpMethod = "POST"
        exchange.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        exchange.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: exchange)
        guard let response = response as? HTTPURLResponse else {
            throw StreamAuthorizationError.unavailable
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw StreamAuthorizationError.signInExpired
        }
        guard (200...299).contains(response.statusCode) else {
            throw DownloadFailure.response(response, data: data)
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["access_token"] as? String, !token.isEmpty,
              body["token_type"] as? String == "Bearer" else {
            throw StreamAuthorizationError.unavailable
        }
        // A logout or account switch during the exchange must not authorize this request.
        guard KeychainManager.shared.getAccessToken() == session else {
            throw StreamAuthorizationError.signInExpired
        }
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": sourceURL])
        request.timeoutInterval = timeout
        return request
    }

    /// Parse a FastAPI error body ({"detail": "..."}) into a readable message.
    static func serverDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? String,
              !detail.isEmpty else {
            return nil
        }
        return detail
    }
}


enum StreamAuthorizationError: LocalizedError {
    case signInExpired
    case unavailable

    var errorDescription: String? {
        switch self {
        case .signInExpired: return "Your sign-in has expired. Please sign out and sign in again."
        case .unavailable: return "Unable to authorize streaming. Please try again."
        }
    }
}
