//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    // MARK: - State
    @State private var showingAccount = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @State private var queueTracks: [Track] = []
    @State private var recentlyPlayed: [Track] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    // MARK: - Body
    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
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
                        await loadHomeData()
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if queueTracks.isEmpty && recentlyPlayed.isEmpty {
            emptyState
        } else {
            homeList
        }
    }

    private var header: some View {
        HStack {
            Text("Home")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Spacer()

            if let avatarUrl = profileManager.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(.gray.opacity(0.3))
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .onTapGesture {
                    showingAccount.toggle()
                }
            } else {
                ProfileCircleView(
                    profileImage: nil,
                    userName: profileManager.displayName,
                    size: 32
                )
                .onTapGesture {
                    showingAccount.toggle()
                }
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "music.note",
            description: Text("Your queue and listening history will appear here")
        )
    }

    private var homeList: some View {
        List {
            // Header section so it scrolls with content, like Library-style header
            Section {
                header
                    .padding(.top, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }

            // Queue Section
            if !queueTracks.isEmpty {
                Section {
                    // Subheading row
                    Text("Queue")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))

                    // Track rows
                    ForEach(Array(queueTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                        TrackRow(track, number: index + 1, showCover: true)
                    }
                }
            }

            // Recently Played Section
            if !recentlyPlayed.isEmpty {
                Section {
                    // Subheading row
                    Text("Recently Played")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 4, trailing: 16))

                    // Track rows
                    ForEach(Array(recentlyPlayed.prefix(10).enumerated()), id: \.element.id) { index, track in
                        TrackRow(track, number: index + 1, showCover: true)
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
    }

    // MARK: - Data Loading

    private func loadHomeData() async {
        guard let userId = authManager.currentUserId else {
            print("❌ [HomeView] No userId")
            return
        }

        guard !isLoading else {
            print("⏭️ [HomeView] Already loading, skipping")
            return
        }

        isLoading = true
        print("🔄 [HomeView] Starting load...")

        // Load queue
        do {
            print("📡 [HomeView] Fetching queue for userId: \(userId)")
            let queueData = try await ConvexService.shared.getQueueTracks(userId: userId)

            self.queueTracks = queueData.map { queueTrack in
                let artworkUrl = queueTrack.artworkUrl ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                return Track(
                    title: queueTrack.title,
                    artist: queueTrack.artist,
                    album: "",
                    artwork: highQualityArtwork,
                    duration: queueTrack.duration
                )
            }
            print("✅ [HomeView] Loaded \(queueTracks.count) queue tracks!")
        } catch {
            print("❌ [HomeView] Queue error: \(error)")
        }

        // Load recently played
        do {
            print("📡 [HomeView] Fetching play history for userId: \(userId)")
            let history = try await ConvexService.shared.getPlayHistory(userId: userId, limit: 20)

            self.recentlyPlayed = history.map { playItem in
                let track = playItem.trackData
                let artworkUrl = track.artwork_url ?? track.user.avatar_url ?? ""
                let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

                return Track(
                    title: track.title,
                    artist: track.user.username,
                    album: track.genre ?? "",
                    artwork: highQualityArtwork,
                    duration: Double(track.duration)
                )
            }
            print("✅ [HomeView] Loaded \(recentlyPlayed.count) recently played tracks!")
        } catch {
            print("❌ [HomeView] Play history error: \(error)")
        }

        hasLoaded = true
        isLoading = false
    }
}

#Preview("Light Mode") {
    HomeView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .preferredColorScheme(.dark)
}
