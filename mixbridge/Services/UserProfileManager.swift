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
            print("📡 [ProfileManager] Fetching profile from Convex for userId: \(userId)")
            let fetchedProfile = try await ConvexService.shared.getUserProfile(userId: userId)

            if let fetchedProfile = fetchedProfile {
                self.profile = fetchedProfile
                print("✅ [ProfileManager] Profile loaded!")
                print("   Username: \(fetchedProfile.profile.username)")
                print("   Avatar: \(fetchedProfile.profile.avatar_url ?? "N/A")")
            } else {
                print("⚠️ [ProfileManager] No profile found in cache")
                errorMessage = "Profile not cached"
            }
        } catch {
            print("❌ [ProfileManager] Failed to load profile: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Convenience Accessors

    var avatarUrl: String? {
        profile?.profile.avatar_url
    }

    var displayName: String {
        profile?.profile.full_name ?? profile?.profile.username ?? "User"
    }

    var username: String {
        profile?.profile.username ?? "user"
    }

    var followersCount: Int {
        profile?.profile.followers_count ?? 0
    }

    var playlistCount: Int {
        profile?.profile.playlist_count ?? 0
    }
}
