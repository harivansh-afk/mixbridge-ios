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

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 24) {
                        playlistGridSection
                        navigationSection
                        recentlyAddedGridSection
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Library")
            .task {
                await loadPlaylists()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            }
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
            }
        }
    }

    private func loadPlaylists() async {
        guard let userId = authManager.currentUserId else {
            print("❌ [LibraryView] No userId")
            isLoading = false
            return
        }

        isLoading = true

        // Try Convex cache first (instant)
        print("📡 [LibraryView] Fetching playlists from Convex for userId: \(userId)")
        do {
            let cached = try await ConvexService.shared.getPlaylists(userId: userId)

            if let cached = cached {
                self.playlists = convertToPlaylists(cached.playlists)
                print("✅ [LibraryView] Loaded \(playlists.count) playlists from Convex cache!")
                isLoading = false
                return
            }
        } catch ConvexError.noData {
            print("⚠️ [LibraryView] No cache, showing empty for now")
        } catch {
            print("❌ [LibraryView] Convex error: \(error)")
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
                ForEach(playlists.isEmpty ? Array(Playlist.samplePlaylists.prefix(6)) : Array(playlists.prefix(6))) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    AsyncImage(url: URL(string: playlist.artwork)) { phase in
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
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var navigationSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                Text("All Playlists")
            } label: {
                LibraryNavigationRow(
                    icon: "music.note.list",
                    title: "Playlists",
                    iconColor: .secondary
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                Text("Artists")
            } label: {
                LibraryNavigationRow(
                    icon: "music.mic",
                    title: "Artists",
                    iconColor: .secondary
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                Text("Songs")
            } label: {
                LibraryNavigationRow(
                    icon: "music.note",
                    title: "Songs",
                    iconColor: .secondary
                )
            }
            .buttonStyle(.plain)

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
                ForEach(playlists.isEmpty ? Array(Playlist.samplePlaylists.prefix(4)) : Array(playlists.dropFirst(6).prefix(4))) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    AsyncImage(url: URL(string: playlist.artwork)) { phase in
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
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
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
