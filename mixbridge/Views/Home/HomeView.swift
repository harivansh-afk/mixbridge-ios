//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showingAccount = false
    @State private var hideToolbarAvatar = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(QueueManager.self) private var queueManager

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                .refreshable {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Home")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .fixedSize()
                            .padding(.leading, -4)
                            .opacity(hideToolbarAvatar ? 0 : 1)
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarItem(placement: .topBarTrailing) {
                        profileAvatar
                            .opacity(hideToolbarAvatar ? 0 : 1)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    selectedDetent: .constant(.large),
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .task(id: authManager.currentUserId) {
                async let observe: Void = viewModel.observeDatabase()

                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                    await viewModel.refresh(userId: userId)
                }

                _ = await observe
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.playHistory.isEmpty {
            skeletonLoadingView
        } else if let error = viewModel.error, viewModel.playHistory.isEmpty {
            errorView(error)
        } else if queueManager.queueTracks.isEmpty && viewModel.playHistory.isEmpty {
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
                Task {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var profileAvatar: some View {
        ProfileAvatarButton(
            avatarUrl: profileManager.avatarUrl,
            displayName: profileManager.displayName,
            size: 35
        ) {
            showingAccount.toggle()
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
        let listContext = viewModel.playHistory
        let rows = viewModel.playHistoryRows

        return List {
            if !rows.isEmpty {
                Section {
                    Text("Recents")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.primary)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)

                ForEach(rows) { row in
                    TrackRow(
                        row.item.track,
                        number: row.index + 1,
                        showCover: true,
                        soundCloudTrack: row.item.soundCloudTrack,
                        listContext: listContext,
                        indexInList: row.index
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(row.index == 0 ? .hidden : .visible, edges: .top)
                    .listRowSeparator(row.index == rows.count - 1 ? .hidden : .visible, edges: .bottom)
                }
            }
        }
        .listStyle(.plain)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            let shouldHide = newValue > 0
            if shouldHide != hideToolbarAvatar {
                withAnimation(.easeOut(duration: 0.15)) {
                    hideToolbarAvatar = shouldHide
                }
            }
        }
    }
}

#Preview("Light Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PlayerState.shared)
        .environmentObject(DownloadManager.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PlayerState.shared)
        .environmentObject(DownloadManager.shared)
        .preferredColorScheme(.dark)
}
