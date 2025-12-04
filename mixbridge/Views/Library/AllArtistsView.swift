import SwiftUI

struct AllArtistsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var artists: [ArtistInfo] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedArtist: ArtistInfo?
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
                        HStack(spacing: 12) {
                            // Artist avatar
                            if let avatarUrl = artist.avatarUrl,
                               let url = URL(string: avatarUrl) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.clear
                                }
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                            } else {
                                Color.clear
                                    .frame(width: 50, height: 50)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(artist.name)
                                    .font(.body)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .matchedTransitionSource(id: "artist-\(artist.id)", in: namespace)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.selection()
                            selectedArtist = artist
                        }
                    }
                }
                .listStyle(.plain)
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Artists")
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistDetailView(artist: artist)
                .navigationTransition(.zoom(sourceID: "artist-\(artist.id)", in: namespace))
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
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

struct ArtistInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let avatarUrl: String?
    var trackCount: Int
    var tracks: [Track] = []
    var tracksData: [String: [String: Any]] = [:]

    static func == (lhs: ArtistInfo, rhs: ArtistInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    NavigationStack {
        AllArtistsView()
            .environment(AuthManager.shared)
    }
}
