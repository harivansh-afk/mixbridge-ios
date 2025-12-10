import SwiftUI

struct ArtistDetailView: View {
    let artist: ArtistInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Namespace private var namespace

    @State private var fetchedTrackItems: [TrackItem] = []
    @State private var artistPlaylists: [Playlist] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    private let avatarSize: CGFloat = 200

    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    avatarView
                        .padding(.top, 20)

                    artistInfo

                    actionButtons
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            if isLoading && !hasLoaded {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                }
            } else {
                if !combinedTrackItems.isEmpty {
                    topSongsSection
                }

                if !artistPlaylists.isEmpty {
                    releasesSection
                }
            }
        }
        .listStyle(.plain)
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                }
            }
        }
        .task {
            if !hasLoaded {
                await loadArtistContent()
            }
        }
        .refreshable {
            await loadArtistContent(forceRefresh: true)
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let avatarUrl = artist.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        avatarPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    case .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Color.clear
            .frame(width: avatarSize, height: avatarSize)
    }

    private var artistInfo: some View {
        VStack(spacing: 8) {
            Text(artist.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                if let firstItem = combinedTrackItems.first {
                    PlayerState.shared.play(
                        track: firstItem.track,
                        soundCloudTrack: firstItem.soundCloudTrack
                    )
                }
            },
            onShuffle: {
                if let randomItem = combinedTrackItems.randomElement() {
                    PlayerState.shared.play(
                        track: randomItem.track,
                        soundCloudTrack: randomItem.soundCloudTrack
                    )
                }
            }
        )
    }

    // MARK: - Top Songs Section

    private var topSongsSection: some View {
        Section {
            if combinedTrackItems.count > 5 {
                NavigationLink {
                    ArtistAllSongsView(
                        artistName: artist.name,
                        trackItems: combinedTrackItems
                    )
                } label: {
                    Text("Top Songs")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .listRowSeparator(.hidden)
            } else {
                Text("Top Songs")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .listRowSeparator(.hidden)
            }

            ForEach(Array(combinedTrackItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                TrackRow(
                    item.track,
                    number: index + 1,
                    showCover: true,
                    soundCloudTrack: item.soundCloudTrack
                )
            }
        }
        .listSectionSeparator(.hidden)
    }

    // MARK: - Releases Section

    private var releasesSection: some View {
        Section {
            Text("Releases")
                .font(.title3)
                .fontWeight(.semibold)
                .listRowSeparator(.hidden)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artistPlaylists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                                .navigationTransition(.zoom(sourceID: "artist-release-\(playlist.id)", in: namespace))
                        } label: {
                            releaseCard(playlist)
                                .matchedTransitionSource(id: "artist-release-\(playlist.id)", in: namespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }

    private func releaseCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if playlist.artwork.starts(with: "http"),
                   let url = URL(string: playlist.artwork) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Color.clear
                        .frame(width: 160, height: 160)
                }
            }

            Text(playlist.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            Text("Playlist")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Combined Tracks

    private var combinedTrackItems: [TrackItem] {
        var seen = Set<String>()
        var result: [TrackItem] = []

        // Fetched tracks first
        for item in fetchedTrackItems {
            if !seen.contains(item.track.id) {
                seen.insert(item.track.id)
                result.append(item)
            }
        }

        // Then artist's pre-loaded tracks
        for item in artist.trackItems {
            if !seen.contains(item.track.id) {
                seen.insert(item.track.id)
                result.append(item)
            }
        }

        return result
    }

    // MARK: - Data Loading

    private func loadArtistContent(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        isLoading = true
        error = nil

        do {
            let searchResults = try await BackgroundExecutor.run {
                try await ConvexService.shared.search(userId: userId, query: artist.name, limit: 50, forceRefresh: forceRefresh)
            }

            let artistId = Int(artist.id) ?? 0

            // Filter tracks by this artist
            let filteredTracks = searchResults.tracks.filter { $0.user.id == artistId }
            self.fetchedTrackItems = filteredTracks.toTrackItems()

            // Filter playlists by this artist
            let filteredPlaylists = searchResults.playlists.filter { $0.user.id == artistId }
            self.artistPlaylists = filteredPlaylists.map { scPlaylist in
                Playlist(
                    id: String(scPlaylist.id),
                    name: scPlaylist.title,
                    creator: scPlaylist.user.username,
                    artwork: scPlaylist.primaryArtworkUrl,
                    tracks: [],
                    lastUpdated: Date()
                )
            }
        } catch {
            self.error = error
        }

        hasLoaded = true
        isLoading = false
    }
}

// MARK: - Artist All Songs View

struct ArtistAllSongsView: View {
    let artistName: String
    let trackItems: [TrackItem]
    @Environment(\.dismiss) private var dismiss
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    var body: some View {
        List {
            ForEach(Array(trackItems.enumerated()), id: \.element.id) { index, item in
                TrackRow(
                    item.track,
                    number: index + 1,
                    showCover: true,
                    soundCloudTrack: item.soundCloudTrack
                )
            }
        }
        .listStyle(.plain)
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        ArtistDetailView(artist: ArtistInfo(
            id: "1",
            name: "Sample Artist",
            avatarUrl: nil,
            trackCount: 5
        ))
    }
    .environment(AuthManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        ArtistDetailView(artist: ArtistInfo(
            id: "1",
            name: "Sample Artist",
            avatarUrl: nil,
            trackCount: 5
        ))
    }
    .environment(AuthManager.shared)
    .preferredColorScheme(.dark)
}
