import Foundation
import SwiftUI

/// Auth provider type
enum AuthProvider: String {
    case soundcloud
    case spotify
}

/// Manages authentication state and OAuth flow
@Observable
@MainActor
class AuthManager {
    static let shared = AuthManager()

    // MARK: - Published State

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var currentUserId: String?
    var errorMessage: String?

    /// Current auth provider (soundcloud or spotify)
    var currentProvider: AuthProvider? {
        guard let provider = keychain.getProvider() else { return nil }
        return AuthProvider(rawValue: provider)
    }

    // MARK: - Configuration

    private let backendUrl = "https://mixbridge.app"
    private let callbackScheme = "mixbridge"

    private let keychain = KeychainManager.shared

    private init() {
        checkAuthStatus()
    }

    // MARK: - Authentication Status

    func checkAuthStatus() {
        if let token = keychain.getAccessToken(),
           let expiry = keychain.getTokenExpiry(),
           expiry > Date() {
            isAuthenticated = true
            currentUserId = keychain.getUserId()

            // If userId is nil, try to extract it from token again
            if currentUserId == nil {
                if let extractedUserId = SessionTokenDecoder.getUserId(from: token) {
                    try? keychain.saveUserId(extractedUserId)
                    currentUserId = extractedUserId
                }
            }

            // If username is nil, try to extract it from token
            if keychain.getUsername() == nil {
                if let extractedUsername = SessionTokenDecoder.getUsername(from: token) {
                    try? keychain.saveUsername(extractedUsername)
                }
            }

            // If provider is nil, try to extract it from token
            if keychain.getProvider() == nil {
                if let extractedProvider = SessionTokenDecoder.getProvider(from: token) {
                    try? keychain.saveProvider(extractedProvider)
                }
            }
        } else {
            isAuthenticated = false
            currentUserId = nil
        }
    }

    // MARK: - OAuth Flow (Web-based via backend)

    /// Get backend OAuth URL for mobile
    func getAuthorizationURL(provider: AuthProvider = .soundcloud) -> URL? {
        switch provider {
        case .soundcloud:
            return URL(string: "\(backendUrl)/api/auth/mobile")
        case .spotify:
            // Spotify uses client-side PKCE - delegate to SpotifyAuthManager
            return SpotifyAuthManager.shared.getAuthorizationURL()
        }
    }

    /// Handle SoundCloud OAuth callback with session token
    func handleCallback(url: URL) async {
        isLoading = true
        errorMessage = nil

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = "Invalid callback URL"
            isLoading = false
            return
        }

        // Check for error (mixbridge://auth-error?error=xxx)
        if url.host == "auth-error" {
            let error = components.queryItems?.first(where: { $0.name == "error" })?.value ?? "unknown_error"
            errorMessage = "Authentication failed: \(error)"
            isLoading = false
            return
        }

        // Get session token (mixbridge://auth-success?token=xxx)
        guard url.host == "auth-success",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            errorMessage = "No session token received"
            isLoading = false
            return
        }

        // Save session token
        do {
            try keychain.saveAccessToken(token)

            // Extract and save userId from JWT
            if let userId = SessionTokenDecoder.getUserId(from: token) {
                try keychain.saveUserId(userId)
                currentUserId = userId
            }

            // Extract and save username from JWT
            if let username = SessionTokenDecoder.getUsername(from: token) {
                try keychain.saveUsername(username)
            }

            // Extract and save provider from JWT
            if let provider = SessionTokenDecoder.getProvider(from: token) {
                try keychain.saveProvider(provider)
            }

            // Set long expiry for session token (30 days)
            let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
            try keychain.saveTokenExpiry(expiry)

            isAuthenticated = true
            isLoading = false

            if let userId = currentUserId,
               let username = keychain.getUsername() {
                Analytics.shared.identify(userId: userId, properties: [
                    "username": username,
                    "provider": keychain.getProvider() ?? "soundcloud"
                ])
            }
        } catch {
            errorMessage = "Failed to save session token: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Handle Spotify OAuth callback - exchanges code via Convex
    func handleSpotifyCallback(url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            // SpotifyAuthManager handles PKCE exchange via Convex
            let result = try await SpotifyAuthManager.shared.handleCallback(url: url)
            try SpotifyAuthManager.shared.saveAuthResult(result)

            currentUserId = result.userId
            isAuthenticated = true

            Analytics.shared.identify(userId: result.userId, properties: [
                "username": result.username,
                "provider": "spotify"
            ])
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Logout

    func logout() {
        keychain.clearAllTokens()
        isAuthenticated = false
        currentUserId = nil
        Analytics.shared.reset()
    }
}
