//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    @State private var showingAccount = false
    @State private var showingDiscover = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(QueueManager.self) private var queueManager
    @Environment(PreloadedDataStore.self) private var dataStore

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
            }
            .fullScreenCover(isPresented: $showingDiscover) {
                DiscoverView(isPresented: $showingDiscover)
            }
            .task {
                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                }
                // Data already loaded by AppDataPreloader
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if dataStore.playHistoryState == .loading && dataStore.playHistory.isEmpty {
            skeletonLoadingView
        } else if case .failed(let error) = dataStore.playHistoryState, dataStore.playHistory.isEmpty {
            errorView(error)
        } else if queueManager.queueTracks.isEmpty && dataStore.playHistory.isEmpty {
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
            // Pages Section
            Section {
                pagesSection
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            // Recents Section
            if !dataStore.playHistory.isEmpty {
                Section {
                    Text("Recents")
                        .font(.title2)
                        .fontWeight(.bold)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)

                    ForEach(Array(dataStore.playHistory.prefix(100).enumerated()), id: \.element.id) { index, item in
                        TrackRow(
                            item.track,
                            number: index + 1,
                            showCover: true,
                            soundCloudTrack: item.soundCloudTrack,
                            listContext: Array(dataStore.playHistory.prefix(100)),
                            indexInList: index
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadHomeData(forceRefresh: true)
        }
    }

    private var pagesSection: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.selection()
                showingDiscover = true
            } label: {
                LibraryNavigationRow(
                    icon: "apple.intelligence",
                    title: "Discover",
                    iconColor: .primary
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)
        }
    }

    private func loadHomeData(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .playHistory)
    }
}

#Preview("Light Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.dark)
}
