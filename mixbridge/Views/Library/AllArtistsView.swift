import SwiftUI

struct AllArtistsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var artists: [ArtistInfo] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("")
            } else if artists.isEmpty {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "music.mic",
                    description: Text("Your artists will appear here")
                )
            } else {
                List {
                    ForEach(artists) { artist in
                        NavigationLink {
                            Text("Artist: \(artist.name)")
                        } label: {
                            HStack(spacing: 12) {
                                // Artist avatar
                                if let avatarUrl = artist.avatarUrl,
                                   let url = URL(string: avatarUrl) {
                                    CachedAsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(.gray.opacity(0.3))
                                    }
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(.gray.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.name)
                                        .font(.body)

                                    Text("\(artist.trackCount) track\(artist.trackCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Artists")
        .onAppear {
            if !hasLoaded {
                Task {
                    await loadArtists()
                }
            }
        }
    }

    private func loadArtists() async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true

        do {
            let cached = try await BackgroundExecutor.run {
                try await ConvexService.shared.getLikedTracks(userId: userId)
            }

            if let cached = cached {
                // Group tracks by artist
                var artistsDict: [Int: ArtistInfo] = [:]

                for track in cached.tracks {
                    let artistId = track.user.id
                    if var existing = artistsDict[artistId] {
                        existing.trackCount += 1
                        artistsDict[artistId] = existing
                    } else {
                        let avatarUrl = track.user.avatar_url?.upgradeArtworkQuality()
                        artistsDict[artistId] = ArtistInfo(
                            id: String(artistId),
                            name: track.user.username,
                            avatarUrl: avatarUrl,
                            trackCount: 1
                        )
                    }
                }

                self.artists = artistsDict.values.sorted { $0.trackCount > $1.trackCount }
            }
        } catch {
        }

        hasLoaded = true
        isLoading = false
    }
}

struct ArtistInfo: Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    var trackCount: Int
}

#Preview {
    NavigationStack {
        AllArtistsView()
            .environment(AuthManager.shared)
    }
}
