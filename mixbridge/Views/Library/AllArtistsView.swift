import SwiftUI

struct AllArtistsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var artists: [ArtistInfo] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @Namespace private var namespace

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
                            ArtistDetailView(artist: artist)
                                .navigationTransition(.zoom(sourceID: "artist-\(artist.id)", in: namespace))
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
                                        .overlay(
                                            Image(systemName: "music.mic")
                                                .foregroundStyle(.gray)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.name)
                                        .font(.body)

                                    Text("\(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .matchedTransitionSource(id: "artist-\(artist.id)", in: namespace)
                        }
                        .haptic(.selection)
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

                for soundcloudTrack in cached.tracks {
                    let artistId = soundcloudTrack.user.id
                    let artworkUrl = soundcloudTrack.artwork_url ?? soundcloudTrack.user.avatar_url ?? ""
                    let highQualityArtwork = artworkUrl.upgradeArtworkQuality()
                    let trackId = String(soundcloudTrack.id)

                    let track = Track(
                        id: trackId,
                        title: soundcloudTrack.title,
                        artist: soundcloudTrack.user.username,
                        album: soundcloudTrack.genre ?? "",
                        artwork: highQualityArtwork,
                        duration: Double(soundcloudTrack.duration) / 1000.0
                    )

                    // Get raw data for queue operations
                    var rawData: [String: Any]? = nil
                    if let rawDict = try? JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(soundcloudTrack),
                        options: []
                    ) as? [String: Any] {
                        rawData = rawDict
                    }

                    if var existing = artistsDict[artistId] {
                        existing.trackCount += 1
                        existing.tracks.append(track)
                        if let rawData = rawData {
                            existing.tracksData[trackId] = rawData
                        }
                        artistsDict[artistId] = existing
                    } else {
                        let avatarUrl = soundcloudTrack.user.avatar_url?.upgradeArtworkQuality()
                        var newArtist = ArtistInfo(
                            id: String(artistId),
                            name: soundcloudTrack.user.username,
                            avatarUrl: avatarUrl,
                            trackCount: 1
                        )
                        newArtist.tracks = [track]
                        if let rawData = rawData {
                            newArtist.tracksData[trackId] = rawData
                        }
                        artistsDict[artistId] = newArtist
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
    var tracks: [Track] = []
    var tracksData: [String: [String: Any]] = [:]
}

#Preview {
    NavigationStack {
        AllArtistsView()
            .environment(AuthManager.shared)
    }
}
