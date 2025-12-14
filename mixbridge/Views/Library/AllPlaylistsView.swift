import SwiftUI

struct AllPlaylistsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(PreloadedDataStore.self) private var dataStore

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var selectedPlaylist: Playlist?
    @Namespace private var namespace

    var body: some View {
        Group {
            if dataStore.playlistsState == .loading && dataStore.playlists.isEmpty {
                ProgressView()
            } else if case .failed(let error) = dataStore.playlistsState, dataStore.playlists.isEmpty {
                errorView(error)
            } else if dataStore.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            } else {
                List {
                    ForEach(dataStore.playlists) { playlist in
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
                        .onAppear {
                            // Preload when row becomes visible
                            if let userId = authManager.currentUserId {
                                Task(priority: .background) {
                                    await AppDataPreloader.shared.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
                                }
                            }
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
                Task { await loadPlaylists(forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadPlaylists(forceRefresh: Bool = false) async {
        guard let userId = authManager.currentUserId else { return }
        await AppDataPreloader.shared.refreshIfStale(userId: userId, dataType: .playlists)
    }
}

#Preview {
    NavigationStack {
        AllPlaylistsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
            .environment(PreloadedDataStore.shared)
    }
}
