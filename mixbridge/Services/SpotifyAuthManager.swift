//
//  SpotifyAuthManager.swift
//  mixbridge
//
//  Manages Spotify OAuth authentication flow.
//

import Foundation
import AuthenticationServices
import CryptoKit

/// Manages Spotify authentication state and OAuth flow
@Observable
@MainActor
final class SpotifyAuthManager: NSObject {
    static let shared = SpotifyAuthManager()
    
    // MARK: - Published State
    
    var isConnected: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - Configuration
    
    private let backendUrl = "https://mixbridge.app"
    private let callbackScheme = "mixbridge"
    private let spotifyScopes = [
        "user-read-private",
        "user-read-email",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-read-recently-played",
        "user-top-read",
        "user-follow-read"
    ]
    
    // PKCE state
    private var codeVerifier: String?
    private var authSession: ASWebAuthenticationSession?
    
    private let keychain = KeychainManager.shared
    
    private override init() {
        super.init()
        checkConnectionStatus()
    }
    
    // MARK: - Connection Status
    
    func checkConnectionStatus() {
        // Check if we have a valid Spotify token stored
        isConnected = keychain.getSpotifyAccessToken() != nil
    }
    
    // MARK: - OAuth Flow
    
    /// Generate a cryptographically secure code verifier for PKCE
    private nonisolated func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Generate code challenge from verifier using SHA256
    private nonisolated func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Start the Spotify OAuth flow using ASWebAuthenticationSession
    /// - Parameter presentationAnchor: The window to present the auth session from
    func startOAuthFlow(presentationAnchor: ASPresentationAnchor? = nil) {
        isLoading = true
        errorMessage = nil
        
        // Generate PKCE values
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)
        
        // Build OAuth URL
        guard let authURL = buildAuthorizationURL(codeChallenge: challenge) else {
            errorMessage = "Failed to build authorization URL"
            isLoading = false
            return
        }
        
        // Create auth session
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                if let error = error {
                    if case ASWebAuthenticationSessionError.canceledLogin = error {
                        self.isLoading = false
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                
                guard let callbackURL else {
                    self.errorMessage = "No callback URL received"
                    self.isLoading = false
                    return
                }
                
                await self.handleCallback(url: callbackURL)
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        
        let started = session.start()
        if !started {
            errorMessage = "Failed to start authentication session"
            isLoading = false
        }
    }
    
    /// Build the Spotify authorization URL
    private func buildAuthorizationURL(codeChallenge: String) -> URL? {
        // Route through backend for mobile OAuth
        var components = URLComponents(string: "\(backendUrl)/api/auth/spotify/mobile")
        components?.queryItems = [
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }
    
    /// Handle the OAuth callback URL
    /// - Parameter url: The callback URL containing the authorization code
    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            errorMessage = "Invalid callback URL"
            isLoading = false
            return
        }
        
        // Check for error (mixbridge://spotify-error?error=xxx)
        if url.host == "spotify-error" {
            let error = components.queryItems?.first(where: { $0.name == "error" })?.value ?? "unknown_error"
            errorMessage = "Spotify authentication failed: \(error)"
            isLoading = false
            return
        }
        
        // Get authorization code (mixbridge://spotify-success?code=xxx)
        guard url.host == "spotify-success",
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = "No authorization code received"
            isLoading = false
            return
        }
        
        guard let verifier = codeVerifier else {
            errorMessage = "Missing code verifier"
            isLoading = false
            return
        }
        
        // Check if user is currently authenticated (not just has stale keychain data)
        // Must verify BOTH that AuthManager says we're authenticated AND userId exists
        let isLinking = AuthManager.shared.isAuthenticated && keychain.getUserId() != nil
        
        if isLinking {
            // User already has an account - link Spotify to existing account
            do {
                try await ConvexService.shared.spotifyLinkAccount(code: code, codeVerifier: verifier)
                isConnected = true
                isLoading = false
                codeVerifier = nil
            } catch {
                errorMessage = "Failed to link Spotify: \(error.localizedDescription)"
                isLoading = false
            }
        } else {
            // New user or not logged in - complete full auth flow (signup/login)
            do {
                let authResult = try await ConvexService.shared.spotifyCompleteAuth(
                    code: code,
                    codeVerifier: verifier
                )
                
                // Save user session (same as SoundCloud auth)
                try keychain.saveUserId(authResult.userId)
                try keychain.saveUsername(authResult.displayName)
                try keychain.saveUserPlatform(.spotify)

                // Set long expiry for session (30 days)
                let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
                try keychain.saveTokenExpiry(expiry)
                
                // Notify AuthManager that we're now authenticated
                AuthManager.shared.isAuthenticated = true
                AuthManager.shared.currentUserId = authResult.userId
                
                isConnected = true
                isLoading = false
                codeVerifier = nil
                
                // Track analytics
                Analytics.shared.identify(userId: authResult.userId, properties: [
                    "username": authResult.displayName,
                    "signup_platform": "spotify",
                    "is_new_user": authResult.isNewUser
                ])
            } catch {
                errorMessage = "Failed to complete Spotify login: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    /// Get the current Spotify access token, refreshing if needed
    /// - Returns: A valid access token
    func getAccessToken() async throws -> String {
        // First check local keychain
        if let token = keychain.getSpotifyAccessToken(),
           let expiry = keychain.getSpotifyTokenExpiry(),
           expiry > Date() {
            return token
        }
        
        // Fetch fresh token from Convex
        let tokenResponse = try await ConvexService.shared.spotifyGetAccessToken()
        
        // Cache locally
        try keychain.saveSpotifyAccessToken(tokenResponse.accessToken)
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        try keychain.saveSpotifyTokenExpiry(expiry)
        
        return tokenResponse.accessToken
    }
    
    /// Disconnect Spotify account
    func disconnect() {
        keychain.clearSpotifyTokens()
        isConnected = false
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        
        // Fallback: return first available window
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first {
            return window
        }
        
        // Last resort
        return UIWindow()
    }
}
