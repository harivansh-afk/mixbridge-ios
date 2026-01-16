//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var showingAccount = false
    @State private var hideToolbarAvatar = false
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(AuthManager.self) private var authManager
    @Environment(FeatureFlags.self) private var featureFlags
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .contentMargins(.top, 0, for: .scrollContent)
                .refreshable {
                    await loadPlaylists(forceRefresh: true)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Library")
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
                    let userId = authManager.currentUserId
                    async let observe: Void = {
                        guard let userId else { return }
                        await viewModel.observeDatabase(userId: userId)
                    }()

                    if let userId {
                        await profileManager.loadProfile(userId: userId)
                        await viewModel.refresh(userId: userId)
                    }

                    _ = await observe
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.playlists.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !viewModel.playlists.isEmpty {
                        playlistGridSection
                    }
                    navigationSection
                    if viewModel.playlists.count > 6 {
                        recentlyAddedGridSection
                    }
                }
            }
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

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await viewModel.refresh(userId: userId, forceRefresh: forceRefresh)
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

    private var recentlyAddedPlaylists: [Playlist] {
        let remaining = Array(viewModel.playlists.dropFirst(6))
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
                ForEach(Array(viewModel.playlists.prefix(6).enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                            .navigationTransition(.zoom(sourceID: "top-\(playlist.id)", in: namespace))
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            ArtworkView(
                                artwork: playlist.artwork,
                                cornerRadius: 12,
                                placeholderIcon: "music-note",
                                showsProgressWhileLoading: true
                            )

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
                                await viewModel.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var navigationSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LikedView()
            } label: {
                LibraryNavigationRow(
                    icon: "heart",
                    title: "Liked",
                    iconColor: .primary,
                    isSystemImage: false
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
                    icon: "playlist",
                    title: "Playlists",
                    iconColor: .primary,
                    isSystemImage: false
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
                    icon: "microphone",
                    title: "Artists",
                    iconColor: .primary,
                    isSystemImage: false
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
                    icon: "music-note-simple",
                    title: "Songs",
                    iconColor: .primary,
                    isSystemImage: false
                )
            }
            .buttonStyle(.plain)
            .haptic(.selection)

            if featureFlags.downloadsEnabled {
                Divider()
                    .padding(.leading, 60)

                NavigationLink {
                    DownloadsView()
                } label: {
                    LibraryNavigationRow(
                        icon: "arrow-circle-down",
                        title: "Downloads",
                        iconColor: .primary,
                        isSystemImage: false
                    )
                }
                .buttonStyle(.plain)
                .haptic(.selection)
            }
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
                            ArtworkView(
                                artwork: playlist.artwork,
                                cornerRadius: 12,
                                placeholderIcon: "music-note",
                                showsProgressWhileLoading: true
                            )

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
                                await viewModel.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
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
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LibraryView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .preferredColorScheme(.dark)
}
