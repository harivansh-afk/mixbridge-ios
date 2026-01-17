import Foundation
import SwiftUI

/// Manages authentication state and SoundCloud OAuth flow
@Observable
@MainActor
class AuthManager {
    static let shared = AuthManager()

    // MARK: - Published State

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var currentUserId: String?
    var errorMessage: String?

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
        } else {
            isAuthenticated = false
            currentUserId = nil
        }
    }

    // MARK: - OAuth Flow (Web-based via backend)

    /// Get backend OAuth URL for mobile
    func getAuthorizationURL() -> URL? {
        return URL(string: "\(backendUrl)/api/auth/mobile")
    }

    /// Handle OAuth callback with session token
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

            // Set long expiry for session token (30 days)
            let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
            try keychain.saveTokenExpiry(expiry)

            isAuthenticated = true
            isLoading = false

            if let userId = currentUserId,
               let username = keychain.getUsername() {
                Analytics.shared.identify(userId: userId, properties: ["username": username])
            }
        } catch {
            errorMessage = "Failed to save session token: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Logout

    func logout() {
        keychain.clearAllTokens()
        isAuthenticated = false
        currentUserId = nil
        Analytics.shared.reset()
    }
}
