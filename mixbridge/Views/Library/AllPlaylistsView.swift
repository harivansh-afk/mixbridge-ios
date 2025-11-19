import SwiftUI

struct AllPlaylistsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("")
            } else if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            } else {
                List {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                // Playlist artwork
                                if playlist.artwork.starts(with: "http"),
                                   let url = URL(string: playlist.artwork) {
                                    CachedAsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.gray.opacity(0.3))
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 60, height: 60)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.body)
                                        .lineLimit(1)

                                    Text(playlist.creator)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .haptic(.selection)
                    }
                }
                .listStyle(.plain)
            }
        }
        .swipeBackGesture()
        .navigationTitle("Playlists")
        .onAppear {
            if !hasLoaded {
                Task {
                    await loadPlaylists()
                }
            }
        }
    }

    private func loadPlaylists() async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true

        do {
            let cached = try await BackgroundExecutor.run {
                try await ConvexService.shared.getPlaylists(userId: userId)
            }

            if let cached = cached {
                self.playlists = cached.playlists.map { soundcloudPlaylist in
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
        } catch {
        }

        hasLoaded = true
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AllPlaylistsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
