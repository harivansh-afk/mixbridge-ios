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
    @State private var accountSheetDetent: PresentationDetent = .medium
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(QueueManager.self) private var queueManager

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileAvatar
                    }
                }
            .sheet(isPresented: $showingAccount, onDismiss: {
                accountSheetDetent = .medium
            }) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    selectedDetent: $accountSheetDetent,
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
                .presentationDetents([.medium, .large], selection: $accountSheetDetent)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
            }
            // Start database observation
            .task {
                await viewModel.observeDatabase()
            }
            // Fetch fresh data
            .task {
                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                    await viewModel.refresh(userId: userId)
                }
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
        let listContext = Array(viewModel.playHistory.prefix(100))

        return List {
            if !listContext.isEmpty {
                Text("Recents")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.primary)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                ForEach(Array(listContext.enumerated()), id: \.element.id) { index, item in
                    TrackRow(
                        item.track,
                        number: index + 1,
                        showCover: true,
                        soundCloudTrack: item.soundCloudTrack,
                        listContext: listContext,
                        indexInList: index
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
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
