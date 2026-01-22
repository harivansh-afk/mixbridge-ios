import Foundation
@testable import mixbridge

/// A mock implementation of AuthManager for testing
/// Allows controlling authentication state without actual OAuth flows
@MainActor
final class MockAuthManager {

    // MARK: - State

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var currentUserId: String?
    var errorMessage: String?
    var currentProvider: AuthProvider?

    // MARK: - Call Tracking

    private(set) var loginCallCount = 0
    private(set) var logoutCallCount = 0
    private(set) var checkAuthStatusCallCount = 0
    private(set) var handleCallbackCallCount = 0
    private(set) var handleSpotifyCallbackCallCount = 0

    // MARK: - Stubbed Values

    var stubbedAuthorizationURL: URL?
    var shouldSucceedCallback = true
    var callbackError: String?

    // MARK: - Mock Methods

    func checkAuthStatus() {
        checkAuthStatusCallCount += 1
        // Auth state remains as configured
    }

    func getAuthorizationURL(provider: AuthProvider = .soundcloud) -> URL? {
        if let stubbed = stubbedAuthorizationURL {
            return stubbed
        }
        return URL(string: "https://example.com/auth")
    }

    func handleCallback(url: URL) async {
        handleCallbackCallCount += 1
        isLoading = true

        if shouldSucceedCallback {
            isAuthenticated = true
            currentUserId = currentUserId ?? "test-user-123"
            currentProvider = .soundcloud
            errorMessage = nil
        } else {
            isAuthenticated = false
            errorMessage = callbackError ?? "Mock authentication failed"
        }

        isLoading = false
    }

    func handleSpotifyCallback(url: URL) async {
        handleSpotifyCallbackCallCount += 1
        isLoading = true

        if shouldSucceedCallback {
            isAuthenticated = true
            currentUserId = currentUserId ?? "spotify-user-123"
            currentProvider = .spotify
            errorMessage = nil
        } else {
            isAuthenticated = false
            errorMessage = callbackError ?? "Mock Spotify authentication failed"
        }

        isLoading = false
    }

    func logout() {
        logoutCallCount += 1
        isAuthenticated = false
        currentUserId = nil
        currentProvider = nil
        errorMessage = nil
    }

    // MARK: - Test Helpers

    func reset() {
        isAuthenticated = false
        isLoading = false
        currentUserId = nil
        errorMessage = nil
        currentProvider = nil

        loginCallCount = 0
        logoutCallCount = 0
        checkAuthStatusCallCount = 0
        handleCallbackCallCount = 0
        handleSpotifyCallbackCallCount = 0

        stubbedAuthorizationURL = nil
        shouldSucceedCallback = true
        callbackError = nil
    }

    /// Simulates a logged-in user for testing
    func simulateLoggedIn(
        userId: String = "test-user-123",
        provider: AuthProvider = .soundcloud
    ) {
        isAuthenticated = true
        currentUserId = userId
        currentProvider = provider
        errorMessage = nil
    }

    /// Simulates a logged-out state
    func simulateLoggedOut() {
        isAuthenticated = false
        currentUserId = nil
        currentProvider = nil
    }
}
