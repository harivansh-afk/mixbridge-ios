//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    @State private var showingAccount = false
    @State private var accountSheetDetent: PresentationDetent = .medium
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(AuthManager.self) private var authManager
    @Environment(PreloadedDataStore.self) private var dataStore
    @State private var isRefreshing = false
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            Group {
                if dataStore.playlistsState == .loading && dataStore.playlists.isEmpty && !isRefreshing {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RefreshableScrollView(isRefreshing: $isRefreshing) {
                        await loadPlaylists(forceRefresh: true)
                    } content: {
                        VStack(alignment: .leading, spacing: 24) {
                            if !dataStore.playlists.isEmpty {
                                playlistGridSection
                            }
                            navigationSection
                            if dataStore.playlists.count > 6 {
                                recentlyAddedGridSection
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileAvatar
                }
            }
            .task {
                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                }
                // Data already loaded by AppDataPreloader
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
        }
    }

    private var profileAvatar: some View {
        HStack {
            if let avatarUrl = profileManager.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
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
                    userName: profileManager.displayName,
                )
                .onTapGesture {
                    HapticManager.light()
                    showingAccount.toggle()
                }
            }
        }
    }

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }

        if forceRefresh {
            isRefreshing = true
        }

        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .playlists)

        isRefreshing = false
    }

    private var recentlyAddedPlaylists: [Playlist] {
        let remaining = Array(dataStore.playlists.dropFirst(6))
        let evenCount = remaining.count - (remaining.count % 2)
        return Array(remaining.prefix(evenCount))
    }

    private var playlistGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 20
            ) {
                ForEach(Array(dataStore.playlists.prefix(6).enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                            .navigationTransition(.zoom(sourceID: "top-\(playlist.id)", in: namespace))
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                                        switch phase {
                                        case .empty:
                                            artworkPlaceholder
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        case .failure:
                                            artworkPlaceholder
                                        @unknown default:
                                            artworkPlaceholder
                                        }
                                    }
                                } else {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }

                            // Name only
                            Text(playlist.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity)
                        }
                        .matchedTransitionSource(id: "top-\(playlist.id)", in: namespace)
                    }
                    .buttonStyle(.plain)
                    .haptic(.selection)
                    .onAppear {
                        // Preload when card becomes visible
                        if let userId = authManager.currentUserId {
                            Task(priority: .background) {
                                await AppDataPreloader.shared.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary)

            ProgressView()
                .progressViewStyle(.circular)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var navigationSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LikedView()
            } label: {
                LibraryNavigationRow(
                    icon: "heart.fill",
                    title: "Liked",
                    iconColor: .primary
                )
            }
            .buttonStyle(.plain)
            .haptic(.selection)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                AllPlaylistsView()
            } label: {
                LibraryNavigationRow(
                    icon: "music.note.list",
                    title: "Playlists",
                    iconColor: .primary
                )
            }
            .buttonStyle(.plain)
            .haptic(.selection)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                AllArtistsView()
            } label: {
                LibraryNavigationRow(
                    icon: "music.mic",
                    title: "Artists",
                    iconColor: .primary
                )
            }
            .buttonStyle(.plain)
            .haptic(.selection)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                AllSongsView()
            } label: {
                LibraryNavigationRow(
                    icon: "music.note",
                    title: "Songs",
                    iconColor: .primary
                )
            }
            .buttonStyle(.plain)
            .haptic(.selection)

            Divider()
                .padding(.leading, 60)
        }
    }

    private var recentlyAddedGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recently Added")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 20
            ) {
                ForEach(Array(recentlyAddedPlaylists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                            .navigationTransition(.zoom(sourceID: "recent-\(playlist.id)", in: namespace))
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                                        switch phase {
                                        case .empty:
                                            artworkPlaceholder
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        case .failure:
                                            artworkPlaceholder
                                        @unknown default:
                                            artworkPlaceholder
                                        }
                                    }
                                } else {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }

                            // Name only
                            Text(playlist.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity)
                        }
                        .matchedTransitionSource(id: "recent-\(playlist.id)", in: namespace)
                    }
                    .buttonStyle(.plain)
                    .haptic(.selection)
                    .onAppear {
                        // Preload when card becomes visible
                        if let userId = authManager.currentUserId {
                            Task(priority: .background) {
                                await AppDataPreloader.shared.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview("Light Mode") {
    LibraryView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LibraryView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.dark)
}
