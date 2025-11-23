import Foundation
import SwiftUI

/// Manages user profile data from Convex, shared across the app
@Observable
@MainActor
class UserProfileManager {
    static let shared = UserProfileManager()

    // MARK: - State

    var profile: ConvexUserProfile?
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

            if let fetchedProfile = fetchedProfile {
                self.profile = fetchedProfile
            } else {
                errorMessage = "Profile not cached"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Convenience Accessors

    var avatarUrl: String? {
        profile?.profile.avatar_url
    }

    var displayName: String {
        profile?.profile.full_name ?? profile?.profile.username ?? KeychainManager.shared.getUsername() ?? "User"
    }

    var username: String {
        profile?.profile.username ?? KeychainManager.shared.getUsername() ?? "user"
    }

    var followersCount: Int {
        profile?.profile.followers_count ?? 0
    }

    var playlistCount: Int {
        profile?.profile.playlist_count ?? 0
    }
}
