import SwiftUI

struct ArtistDetailView: View {
    let artist: ArtistInfo
    @Environment(\.dismiss) private var dismiss
    @Namespace private var namespace

    // Fetched content
    @State private var artistTracks: [Track] = []
    @State private var artistTracksData: [String: [String: Any]] = [:]
    @State private var artistPlaylists: [Playlist] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    private let avatarSize: CGFloat = 200

    var body: some View {
        List {
            // Header Section
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

            if isLoading {
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
                // Top Songs Section
                if !combinedTracks.isEmpty {
                    topSongsSection
                }

                // Releases Section
                if !artistPlaylists.isEmpty {
                    releasesSection
                }
            }
        }
        .listStyle(.plain)
        .navigationBarBackButtonHidden(true)
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
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple, .purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "music.mic")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: avatarSize, height: avatarSize)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
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
                let allTracks = combinedTracks
                if let firstTrack = allTracks.first {
                    let trackData = combinedTracksData[firstTrack.id]
                    PlayerState.shared.play(track: firstTrack, trackData: trackData)
                }
            },
            onShuffle: {
                let allTracks = combinedTracks
                if let randomTrack = allTracks.randomElement() {
                    let trackData = combinedTracksData[randomTrack.id]
                    PlayerState.shared.play(track: randomTrack, trackData: trackData)
                }
            }
        )
    }

    // MARK: - Top Songs Section

    private var topSongsSection: some View {
        Section {
            if combinedTracks.count > 5 {
                NavigationLink {
                    ArtistAllSongsView(
                        artistName: artist.name,
                        tracks: combinedTracks,
                        tracksData: combinedTracksData
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

            ForEach(Array(combinedTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track,
                    number: index + 1,
                    showCover: true,
                    trackData: combinedTracksData[track.id]
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
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.gray.opacity(0.3))
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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

    private var combinedTracks: [Track] {
        var seen = Set<String>()
        var result: [Track] = []

        for track in artistTracks {
            if !seen.contains(track.id) {
                seen.insert(track.id)
                result.append(track)
            }
        }

        for track in artist.tracks {
            if !seen.contains(track.id) {
                seen.insert(track.id)
                result.append(track)
            }
        }

        return result
    }

    private var combinedTracksData: [String: [String: Any]] {
        var result = artistTracksData
        for (key, value) in artist.tracksData {
            if result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Data Loading

    private func loadArtistContent() async {
        isLoading = true

        do {
            let searchResults = try await BackendAPI.shared.search(query: artist.name, limit: 50)

            let artistId = Int(artist.id) ?? 0
            let filteredTracks = searchResults.tracks.filter { $0.user.id == artistId }

            var tracks: [Track] = []
            var tracksData: [String: [String: Any]] = [:]

            for soundcloudTrack in filteredTracks {
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

                tracks.append(track)

                if let rawDict = try? JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(soundcloudTrack),
                    options: []
                ) as? [String: Any] {
                    tracksData[trackId] = rawDict
                }
            }

            let filteredPlaylists = searchResults.playlists.filter { $0.user.id == artistId }

            let playlists = filteredPlaylists.map { soundcloudPlaylist in
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

            self.artistTracks = tracks
            self.artistTracksData = tracksData
            self.artistPlaylists = playlists

        } catch {
            // Silently fail - we still have liked tracks
        }

        hasLoaded = true
        isLoading = false
    }
}

// MARK: - Artist All Songs View

struct ArtistAllSongsView: View {
    let artistName: String
    let tracks: [Track]
    let tracksData: [String: [String: Any]]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track,
                    number: index + 1,
                    showCover: true,
                    trackData: tracksData[track.id]
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
    .preferredColorScheme(.dark)
}
