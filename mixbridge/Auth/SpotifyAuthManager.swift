import Foundation
import CryptoKit

/// Manages Spotify OAuth with client-side PKCE
/// Unlike SoundCloud (which returns a JWT), Spotify returns a code that must be exchanged via Convex
@MainActor
final class SpotifyAuthManager {
    static let shared = SpotifyAuthManager()

    private let backendUrl = "https://mixbridge.app"
    private let convexUrl = "https://avid-falcon-471.convex.cloud"
    private let keychain = KeychainManager.shared

    /// PKCE code verifier - stored in memory during auth flow
    private var codeVerifier: String?

    private init() {}

    // MARK: - PKCE Generation

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - OAuth Flow

    /// Get the Spotify authorization URL with PKCE challenge
    /// Call this to start the OAuth flow
    func getAuthorizationURL() -> URL? {
        // Generate PKCE pair
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)

        // Store verifier for later exchange
        self.codeVerifier = verifier

        var components = URLComponents(string: "\(backendUrl)/api/auth/spotify/mobile")!
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        return components.url
    }

    /// Handle the callback from Spotify OAuth
    /// Returns user info on success, throws on error
    func handleCallback(url: URL) async throws -> SpotifyAuthResult {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthError.invalidCallback
        }

        // Check for error (mixbridge://spotify-auth-error?error=xxx)
        if url.host == "spotify-auth-error" {
            let error = components.queryItems?.first { $0.name == "error" }?.value ?? "unknown"
            throw SpotifyAuthError.oauthError(error)
        }

        // Get authorization code (mixbridge://spotify-auth-callback?code=xxx)
        guard url.host == "spotify-auth-callback",
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.missingCode
        }

        // Get stored code verifier
        guard let verifier = self.codeVerifier else {
            throw SpotifyAuthError.missingVerifier
        }

        // Clear verifier after use
        defer { self.codeVerifier = nil }

        // Exchange code for tokens via Convex
        return try await exchangeCode(code: code, codeVerifier: verifier)
    }

    // MARK: - Token Exchange via Convex

    private func exchangeCode(code: String, codeVerifier: String) async throws -> SpotifyAuthResult {
        let url = URL(string: "\(convexUrl)/api/action")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "path": "actions/spotify/exchangeCode:exchangeCode",
            "args": [
                "code": code,
                "codeVerifier": codeVerifier
            ],
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyAuthError.exchangeFailed("No HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpotifyAuthError.exchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let convexResponse = try JSONDecoder().decode(SpotifyExchangeResponse.self, from: data)

        guard convexResponse.status == "success",
              let value = convexResponse.value,
              value.success,
              let user = value.user else {
            let errorMsg = convexResponse.value?.error ?? convexResponse.errorMessage ?? "Unknown error"
            throw SpotifyAuthError.exchangeFailed(errorMsg)
        }

        return SpotifyAuthResult(
            userId: user.id,
            username: user.username,
            avatarUrl: user.avatarUrl,
            provider: user.provider
        )
    }

    /// Save auth result to keychain
    func saveAuthResult(_ result: SpotifyAuthResult) throws {
        try keychain.saveUserId(result.userId)
        try keychain.saveUsername(result.username)
        try keychain.saveProvider(result.provider)

        // Set long expiry (30 days) - Convex manages actual token refresh
        let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
        try keychain.saveTokenExpiry(expiry)

        // Store a marker token for isAuthenticated checks
        // Actual Spotify tokens are managed server-side by Convex
        try keychain.saveAccessToken("spotify:\(result.userId)")
    }
}

// MARK: - Types

struct SpotifyAuthResult {
    let userId: String
    let username: String
    let avatarUrl: String?
    let provider: String
}

struct SpotifyExchangeResponse: Codable {
    let status: String
    let value: SpotifyExchangeValue?
    let errorMessage: String?
}

struct SpotifyExchangeValue: Codable {
    let success: Bool
    let error: String?
    let user: SpotifyUser?
    let accessToken: String?
    let expiresAt: Int?
}

struct SpotifyUser: Codable {
    let id: String
    let username: String
    let avatarUrl: String?
    let provider: String
}

enum SpotifyAuthError: LocalizedError {
    case invalidCallback
    case oauthError(String)
    case missingCode
    case missingVerifier
    case exchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid callback URL"
        case .oauthError(let msg):
            return "Spotify error: \(msg)"
        case .missingCode:
            return "No authorization code received"
        case .missingVerifier:
            return "PKCE verifier not found - please try again"
        case .exchangeFailed(let msg):
            return "Failed to complete login: \(msg)"
        }
    }
}
