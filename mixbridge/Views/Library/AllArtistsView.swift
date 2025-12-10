import SwiftUI

struct AllArtistsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var artists: [ArtistInfo] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedArtist: ArtistInfo?
    @Namespace private var namespace

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView()
            } else if let error {
                errorView(error)
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
                Task { await loadArtists() }
            }
        }
        .refreshable {
            await loadArtists()
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadArtists() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadArtists() async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let tracks = try await BackgroundExecutor.run {
                try await ConvexService.shared.getLikedTracks(userId: userId)
            }

            // Group tracks by artist
            var artistsDict: [Int: ArtistInfo] = [:]

            for scTrack in tracks {
                let artistId = scTrack.user.id

                if var existing = artistsDict[artistId] {
                    existing.trackCount += 1
                    existing.trackItems.append(TrackItem(soundCloudTrack: scTrack))
                    artistsDict[artistId] = existing
                } else {
                    let avatarUrl = scTrack.user.avatar_url?.upgradeArtworkQuality()
                    var newArtist = ArtistInfo(
                        id: String(artistId),
                        name: scTrack.user.username,
                        avatarUrl: avatarUrl,
                        trackCount: 1
                    )
                    newArtist.trackItems = [TrackItem(soundCloudTrack: scTrack)]
                    artistsDict[artistId] = newArtist
                }
            }

            self.artists = artistsDict.values.sorted { $0.trackCount > $1.trackCount }
        } catch {
            self.error = error
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
    var trackItems: [TrackItem] = []

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
