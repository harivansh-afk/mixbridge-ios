//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    @State private var showingAccount = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(QueueManager.self) private var queueManager

    @State private var trackItems: [TrackItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await loadHomeData()
                }
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
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

    @ViewBuilder
    private var content: some View {
        if isLoading && !hasLoaded {
            skeletonLoadingView
        } else if let error {
            errorView(error)
        } else if queueManager.queueTracks.isEmpty && trackItems.isEmpty {
            emptyState
        } else {
            homeList
        }
    }

    private var skeletonLoadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadHomeData() }
            }
            .buttonStyle(.bordered)
        }
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
                    Color.clear
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
                    userName: profileManager.displayName
                )
                .onTapGesture {
                    HapticManager.light()
                    showingAccount.toggle()
                }
            }
        }
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
            if !trackItems.isEmpty {
                Section {
                    Text("Recents")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)

                    ForEach(Array(trackItems.prefix(100).enumerated()), id: \.element.id) { index, item in
                        TrackRow(
                            item.track,
                            number: index + 1,
                            showCover: true,
                            soundCloudTrack: item.soundCloudTrack
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
    }

    private func loadHomeData() async {
        guard let userId = authManager.currentUserId else { return }
        if isLoading { return }

        isLoading = true
        error = nil

        // Load queue
        do {
            try await queueManager.loadQueue(userId: userId)
        } catch {
            // Queue errors are non-fatal
        }

        // Load play history
        do {
            let history = try await BackgroundExecutor.run {
                try await ConvexService.shared.getPlayHistory(userId: userId, limit: 20)
            }

            var items: [TrackItem] = []
            var seen = Set<String>()

            for playItem in history {
                let key = "\(playItem.trackData.title.lowercased())|\(playItem.trackData.user.username.lowercased())"
                if seen.insert(key).inserted {
                    items.append(TrackItem(soundCloudTrack: playItem.trackData))
                }
            }

            self.trackItems = items
        } catch {
            self.error = error
        }

        hasLoaded = true
        isLoading = false
    }
}

#Preview("Light Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.dark)
}
