//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
    @State private var showingAccount = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(QueueManager.self) private var queueManager
    @State private var likedTracks: [Track] = []
    @State private var likedTracksData: [String: [String: Any]] = [:] // Track ID -> raw data
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Liked")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileAvatar
                    }
                }
                .sheet(isPresented: $showingAccount) {
                    AccountBottomSheet(
                        isPresented: $showingAccount,
                        userName: profileManager.displayName,
                        userEmail: nil,
                        profileImage: nil
                    )
                }
                .task {
                    if let userId = authManager.currentUserId {
                        await profileManager.loadProfile(userId: userId)
                    }
                }
                .onAppear {
                    if !hasLoaded {
                        Task {
                            await loadLikedTracks()
                        }
                    }
                }
        }
    }

    private func loadLikedTracks() async {
        guard let userId = authManager.currentUserId else {
            print("❌ [LikedView] No userId")
            return
        }

        guard !isLoading else {
            print("⏭️ [LikedView] Already loading, skipping")
            return
        }

        isLoading = true
        print("🔄 [LikedView] Starting load...")

        // Try Convex cache first
        print("📡 [LikedView] Fetching liked tracks from Convex for userId: \(userId)")
        do {
            let cached = try await ConvexService.shared.getLikedTracks(userId: userId)

            if let cached = cached {
                let (tracks, tracksData) = convertToTracksWithData(cached.tracks)
                self.likedTracks = tracks
                self.likedTracksData = tracksData
                print("✅ [LikedView] Loaded \(likedTracks.count) liked tracks from Convex cache!")
                hasLoaded = true
                isLoading = false
                return
            }
        } catch ConvexError.noData {
            print("⚠️ [LikedView] No cache, will try backend")
        } catch {
            print("❌ [LikedView] Convex error: \(error)")
        }

        // Fallback: Fetch from backend (fresh from SoundCloud)
        print("📡 [LikedView] Fetching from backend API...")
        do {
            let response = try await BackendAPI.shared.getLikedTracks(limit: 50)
            let (tracks, tracksData) = convertToTracksWithData(response.tracks)
            self.likedTracks = tracks
            self.likedTracksData = tracksData
            print("✅ [LikedView] Loaded \(likedTracks.count) liked tracks from backend!")
        } catch {
            print("❌ [LikedView] Backend error: \(error)")
        }

        hasLoaded = true
        isLoading = false
    }

    private func convertToTracksWithData(_ soundcloudTracks: [SoundCloudTrack]) -> ([Track], [String: [String: Any]]) {
        var tracks: [Track] = []
        var tracksData: [String: [String: Any]] = [:]

        for soundcloudTrack in soundcloudTracks {
            let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
            let highQualityArtwork = artworkUrl.upgradeArtworkQuality()
            let trackId = String(soundcloudTrack.id)

            let track = Track(
                id: trackId,
                title: soundcloudTrack.title,
                artist: soundcloudTrack.user.username,
                album: soundcloudTrack.genre ?? "",
                artwork: highQualityArtwork,
                duration: Double(soundcloudTrack.duration)
            )

            tracks.append(track)

            // Store raw data for queue operations
            if let rawDict = try? JSONSerialization.jsonObject(
                with: JSONEncoder().encode(soundcloudTrack),
                options: []
            ) as? [String: Any] {
                tracksData[trackId] = rawDict
            }
        }

        return (tracks, tracksData)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if likedTracks.isEmpty {
            emptyState
        } else {
            likedList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }

    private var profileAvatar: some View {
        HStack {
            if let avatarUrl = profileManager.avatarUrl,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(.gray.opacity(0.3))
                }
                .frame(width: 35, height: 35)
                .clipShape(Circle())
                .onTapGesture {
                    HapticManager.light()
                    showingAccount.toggle()
                }
            } else {
                ProfileCircleView(
                    profileImage: nil,
                    userName: profileManager.displayName,
                )
                .onTapGesture {
                    HapticManager.light()
                    showingAccount.toggle()
                }
            }
        }
    }

    private var likedList: some View {
        List {
            Section {
                ForEach(Array(likedTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track,
                        number: index + 1,
                        showCover: true,
                        trackData: likedTracksData[track.id]
                    )
                    .redacted(reason: track.title.isEmpty ? .placeholder : [])
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
    }
}

#Preview("Light Mode") {
    LikedView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LikedView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.dark)
}
