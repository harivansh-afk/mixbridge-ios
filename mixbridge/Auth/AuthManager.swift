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

    private let backendUrl = "https://mixbridge.vercel.app"
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
                print("⚠️ [AuthManager] userId is nil, attempting to extract from token")
                if let extractedUserId = SessionTokenDecoder.getUserId(from: token) {
                    try? keychain.saveUserId(extractedUserId)
                    currentUserId = extractedUserId
                    print("✅ [AuthManager] Re-extracted userId: \(extractedUserId)")
                }
            }

            print("🔐 [AuthManager] Restored session - authenticated: \(isAuthenticated), userId: \(currentUserId ?? "nil")")
        } else {
            isAuthenticated = false
            currentUserId = nil
            print("🔐 [AuthManager] No valid session found")
        }
    }

    // MARK: - OAuth Flow (Web-based via backend)

    /// Get backend OAuth URL for mobile
    func getAuthorizationURL() -> URL? {
        let url = URL(string: "\(backendUrl)/api/auth/mobile")
        print("🔐 Backend OAuth URL: \(url?.absoluteString ?? "nil")")
        return url
    }

    /// Handle OAuth callback with session token
    func handleCallback(url: URL) async {
        isLoading = true
        errorMessage = nil

        print("🔙 Callback URL: \(url.absoluteString)")

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
                print("✅ Extracted and saved userId: \(userId)")
            } else {
                print("⚠️ Failed to extract userId from token")
            }

            // Set long expiry for session token (30 days)
            let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
            try keychain.saveTokenExpiry(expiry)

            isAuthenticated = true
            isLoading = false

            print("✅ Session token saved successfully")
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
    }
}
