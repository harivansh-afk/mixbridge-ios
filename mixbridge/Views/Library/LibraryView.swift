//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    @State private var showingAccount = false
    @Environment(UserProfileManager.self) private var profileManager
    @Environment(AuthManager.self) private var authManager
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        VStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        if !playlists.isEmpty {
                            playlistGridSection
                        }
                        navigationSection
                        if !playlists.isEmpty && playlists.count > 6 {
                            recentlyAddedGridSection
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
                await loadPlaylists()
            }
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    private func loadPlaylists() async {
        guard let userId = authManager.currentUserId else {
            isLoading = false
            return
        }

        isLoading = true

        // Try Convex cache first (instant)
        do {
            let cached = try await ConvexService.shared.getPlaylists(userId: userId)

            if let cached = cached {
                self.playlists = convertToPlaylists(cached.playlists)
                isLoading = false
                return
            }
        } catch ConvexError.noData {
        } catch {
        }

        isLoading = false
    }

    private func convertToPlaylists(_ soundcloudPlaylists: [SoundCloudPlaylist]) -> [Playlist] {
        return soundcloudPlaylists.map { soundcloudPlaylist in
            let artworkUrl = soundcloudPlaylist.artwork_url ?? soundcloudPlaylist.user.avatar_url ?? ""
            let highQualityArtwork = artworkUrl.upgradeArtworkQuality()

            return Playlist(
                id: String(soundcloudPlaylist.id),
                name: soundcloudPlaylist.title,
                creator: soundcloudPlaylist.user.username,
                artwork: highQualityArtwork,
                tracks: [],
                lastUpdated: Date()
            )
        }
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
                ForEach(Array(playlists.prefix(6).enumerated()), id: \.element.id) { index, playlist in
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
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
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
                ForEach(Array(playlists.dropFirst(6).enumerated()), id: \.element.id) { index, playlist in
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
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
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
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview("Light Mode") {
    LibraryView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LibraryView()
        .preferredColorScheme(.dark)
}
