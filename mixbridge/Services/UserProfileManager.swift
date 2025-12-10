import Foundation
import SwiftUI

/// Manages user profile data from Convex, shared across the app
@Observable
@MainActor
class UserProfileManager {
    static let shared = UserProfileManager()

    // MARK: - State

    var profile: SoundCloudProfile?
    var isLoading = false
    var errorMessage: String?

    private init() {}

    // MARK: - Load Profile

    func loadProfile(userId: String) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedProfile = try await BackgroundExecutor.run {
                try await ConvexService.shared.getUserProfile(userId: userId)
            }
            self.profile = fetchedProfile
        } catch {
            errorMessage = error.localizedDescription
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
