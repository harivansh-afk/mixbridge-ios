//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    @State private var viewModel = LibraryViewModel()
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(AuthManager.self) private var authManager
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            Group {
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
                        VStack(alignment: .leading, spacing: 16) {
                            headerView
                            if !viewModel.playlists.isEmpty {
                                playlistGridSection
                            }
                            navigationSection
                            if viewModel.playlists.count > 6 {
                                recentlyAddedGridSection
                            }
                        }
                    }
                    .refreshable {
                        await loadPlaylists(forceRefresh: true)
                    }
                }
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

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await viewModel.refresh(userId: userId, forceRefresh: forceRefresh)
    }

    private var headerView: some View {
        Text("Library")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding(.horizontal)
            .padding(.top, 4)
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
                ForEach(viewModel.playlists.prefix(6)) { playlist in
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
                                await viewModel.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
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
                    icon: "music-note",
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
                ForEach(recentlyAddedPlaylists) { playlist in
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
