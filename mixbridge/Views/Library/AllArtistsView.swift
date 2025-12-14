import SwiftUI

struct AllArtistsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(PreloadedDataStore.self) private var dataStore

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedArtist: ArtistInfo?
    @Namespace private var namespace

    // Computed artists from dataStore
    private var artists: [ArtistInfo] {
        // Convert dataStore.artists (which is [String: [TrackItem]]) to [ArtistInfo]
        var artistsDict: [String: ArtistInfo] = [:]

        for (artistName, items) in dataStore.artists {
            guard let firstItem = items.first else { continue }
            let avatarUrl = firstItem.soundCloudTrack.user.avatar_url?.upgradeArtworkQuality()
            var artistInfo = ArtistInfo(
                id: String(firstItem.soundCloudTrack.user.id),
                name: artistName,
                avatarUrl: avatarUrl,
                trackCount: items.count
            )
            artistInfo.trackItems = items
            artistsDict[artistName] = artistInfo
        }

        return artistsDict.values.sorted { $0.trackCount > $1.trackCount }
    }

    var body: some View {
        Group {
            if dataStore.likedTracksState == .loading && dataStore.likedTracks.isEmpty {
                ProgressView()
            } else if case .failed(let error) = dataStore.likedTracksState, dataStore.likedTracks.isEmpty {
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
        .refreshable {
            await loadArtists(forceRefresh: true)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadArtists(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadArtists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .likedTracks)
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
            .environment(PreloadedDataStore.shared)
    }
}
