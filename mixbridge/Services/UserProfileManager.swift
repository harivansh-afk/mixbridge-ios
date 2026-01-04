import Foundation
import SwiftUI

/// Manages user profile data with offline-first loading.
/// Loads from local database first, then syncs from Convex in the background.
@Observable
@MainActor
class UserProfileManager {
    static let shared = UserProfileManager()

    // MARK: - State

    var profile: SoundCloudProfile?
    var isLoading = false
    var errorMessage: String?

    private let profileSync = UserProfileSync.shared

    private init() {}

    // MARK: - Load Profile (Offline-First)

    func loadProfile(userId: String) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        // 1. Load from local database first (instant)
        do {
            let localProfile = try await BackgroundExecutor.run {
                try await self.profileSync.getLocalSoundCloudProfile(userId: userId)
            }
            if let localProfile {
                self.profile = localProfile
            }
        } catch {
            logError(.sync, "Failed to load local profile: \(error)")
        }

        // 2. Sync from backend (updates local DB)
        do {
            let freshProfile = try await BackgroundExecutor.run {
                try await self.profileSync.syncProfile(userId: userId)
            }
            if let freshProfile {
                self.profile = freshProfile
            }
        } catch {
            if profile == nil {
                errorMessage = error.localizedDescription
            }
            logError(.sync, "Failed to sync profile: \(error)")
        }

        isLoading = false
    }

    // MARK: - Convenience Accessors

    var avatarUrl: String? {
        profile?.avatar_url
    }

    var displayName: String {
        profile?.full_name ?? profile?.username ?? KeychainManager.shared.getUsername() ?? "User"
    }

    var username: String {
        profile?.username ?? KeychainManager.shared.getUsername() ?? "user"
    }

    var followersCount: Int {
        profile?.followers_count ?? 0
    }

    var playlistCount: Int {
        profile?.playlist_count ?? 0
    }
}
