import SwiftUI

struct AllPlaylistsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var error: Error?
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedPlaylist: Playlist?
    @Namespace private var namespace

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                ProgressView()
            } else if let error {
                errorView(error)
            } else if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            } else {
                List {
                    ForEach(playlists) { playlist in
                        HStack(spacing: 12) {
                            if playlist.artwork.starts(with: "http"),
                               let url = URL(string: playlist.artwork) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.clear
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Color.clear
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

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .matchedTransitionSource(id: "all-\(playlist.id)", in: namespace)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.selection()
                            selectedPlaylist = playlist
                        }
                    }
                }
                .listStyle(.plain)
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Playlists")
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .navigationTransition(.zoom(sourceID: "all-\(playlist.id)", in: namespace))
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
        .onAppear {
            if !hasLoaded {
                Task { await loadPlaylists() }
            }
        }
        .refreshable {
            await loadPlaylists(forceRefresh: true)
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadPlaylists() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let scPlaylists = try await BackgroundExecutor.run {
                try await ConvexService.shared.getPlaylists(userId: userId, forceRefresh: forceRefresh)
            }

            self.playlists = scPlaylists.map { scPlaylist in
                return Playlist(
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

#Preview {
    NavigationStack {
        AllPlaylistsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
