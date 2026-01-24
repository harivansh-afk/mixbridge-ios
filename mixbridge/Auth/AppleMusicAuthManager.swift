//
//  AppleMusicAuthManager.swift
//  mixbridge
//
//  Manages Apple Music authorization using native MusicKit.
//  Uses MusicAuthorization.request() for user consent.
//

import Foundation
import MusicKit

/// Manages Apple Music OAuth via MusicKit
@MainActor
final class AppleMusicAuthManager {
    static let shared = AppleMusicAuthManager()

    private let keychain = KeychainManager.shared

    private init() {}

    // MARK: - Authorization Status

    /// Current MusicKit authorization status
    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    /// Check if user is authorized for Apple Music
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Authorization Flow

    /// Request Apple Music authorization
    /// Returns the authorization status after user interaction
    func requestAuthorization() async throws -> AppleMusicAuthResult {
        let status = await MusicAuthorization.request()

        switch status {
        case .authorized:
            // Fetch user token and profile info
            return try await fetchUserProfile()

        case .denied:
            throw AppleMusicAuthError.denied

        case .restricted:
            throw AppleMusicAuthError.restricted

        case .notDetermined:
            throw AppleMusicAuthError.notDetermined

        @unknown default:
            throw AppleMusicAuthError.unknown
        }
    }

    /// Fetch user profile after authorization
    private func fetchUserProfile() async throws -> AppleMusicAuthResult {
        // Get the user's music subscription
        let subscription = try await MusicSubscription.current

        // Generate a unique user ID based on subscription status
        // Apple Music doesn't expose a direct user ID, so we create one
        let userId = "applemusic:\(UUID().uuidString)"

        // Get storefront for the user's region
        let storefront = try await MusicDataRequest.currentCountryCode

        return AppleMusicAuthResult(
            userId: userId,
            storefront: storefront,
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
    }

    /// Save auth result to keychain
    func saveAuthResult(_ result: AppleMusicAuthResult) throws {
        try keychain.saveUserId(result.userId)
        try keychain.saveUsername("Apple Music User")
        try keychain.saveProvider("applemusic")

        // Set long expiry (30 days) - MusicKit manages actual authorization
        let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
        try keychain.saveTokenExpiry(expiry)

        // Store a marker token for isAuthenticated checks
        try keychain.saveAccessToken("applemusic:\(result.userId)")
    }

    /// Check if user has valid Apple Music subscription
    func checkSubscription() async -> Bool {
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent
        } catch {
            return false
        }
    }
}

// MARK: - Types

struct AppleMusicAuthResult {
    let userId: String
    let storefront: String
    let canPlayCatalogContent: Bool
    let hasCloudLibraryEnabled: Bool
}

enum AppleMusicAuthError: LocalizedError {
    case denied
    case restricted
    case notDetermined
    case unknown
    case noSubscription

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Apple Music access was denied. Please enable it in Settings."
        case .restricted:
            return "Apple Music access is restricted on this device."
        case .notDetermined:
            return "Apple Music authorization was not completed."
        case .unknown:
            return "An unknown error occurred with Apple Music authorization."
        case .noSubscription:
            return "An active Apple Music subscription is required."
        }
    }
}
