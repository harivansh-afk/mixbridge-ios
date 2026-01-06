import SwiftUI

struct AllArtistsView: View {
    @State private var viewModel = LikedViewModel()
    @Environment(AuthManager.self) private var authManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedArtist: ArtistInfo?
    @State private var artists: [ArtistInfo] = []
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @Namespace private var namespace

    private let revealThreshold: CGFloat = 90

    private var filteredArtists: [ArtistInfo] {
        guard !searchText.isEmpty else { return artists }
        return artists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Build artists list from liked tracks
    private func buildArtists(from tracks: [TrackItem]) -> [ArtistInfo] {
        var artistsDict: [String: ArtistInfo] = [:]

        for item in tracks {
            let artistName = item.track.artist
            let artistId = String(item.soundCloudTrack.user.id)
            let avatarUrl = item.soundCloudTrack.user.avatar_url?.upgradeArtworkQuality()

            if var existing = artistsDict[artistName] {
                existing.trackCount += 1
                existing.trackItems.append(item)
                artistsDict[artistName] = existing
            } else {
                var artistInfo = ArtistInfo(
                    id: artistId,
                    name: artistName,
                    avatarUrl: avatarUrl,
                    trackCount: 1
                )
                artistInfo.trackItems = [item]
                artistsDict[artistName] = artistInfo
            }
        }

        return artistsDict.values.sorted { $0.trackCount > $1.trackCount }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.likedTracks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.likedTracks.isEmpty {
                errorView(error)
            } else if artists.isEmpty {
                ContentUnavailableView(
                    "No Artists",
                    systemImage: "music.mic",
                    description: Text("Your artists will appear here")
                )
            } else {
                List {
                    if filteredArtists.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(Array(filteredArtists.enumerated()), id: \.element.id) { index, artist in
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
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            Image(systemName: "music.mic")
                                                .foregroundStyle(.secondary)
                                        }
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
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                            .matchedTransitionSourceIfAvailable(id: "artist-\(artist.id)", in: namespace)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.selection()
                                selectedArtist = artist
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .onScrollPhaseChangeIfAvailable { oldPhase, newPhase, context in
                    guard oldPhase == .interacting, newPhase != .interacting else { return }
                    let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top

                    if offset < -revealThreshold && !isSearchPresented {
                        isSearchPresented = true
                        HapticManager.light()
                    }
                }
                .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Artists")
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Artists")
        .navigationDestination(item: $selectedArtist) { artist in
            ArtistDetailView(artist: artist)
                .navigationTransitionIfAvailable(sourceID: "artist-\(artist.id)", in: namespace)
        }
        // Start database observation and fetch fresh data
        .task {
            async let observe: () = viewModel.observeDatabase()
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId)
            }
            await observe
        }
        // Update artists when likedTracks changes
        .onChange(of: viewModel.likedTracks) { _, newTracks in
            artists = buildArtists(from: newTracks)
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .refreshable {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId, forceRefresh: true)
            }
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId, forceRefresh: true)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
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
