import SwiftUI

struct AllPlaylistsView: View {
    @State private var viewModel = LibraryViewModel()
    @Environment(AuthManager.self) private var authManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var isRefreshing = false
    @Namespace private var namespace

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.playlists.isEmpty && !isRefreshing {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.playlists.isEmpty {
                errorView(error)
            } else if viewModel.playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Your playlists will appear here")
                )
            } else {
                RefreshableScrollView(isRefreshing: $isRefreshing) {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId, forceRefresh: true)
                    }
                } content: {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)
                        ],
                        spacing: 20
                    ) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                                    .navigationTransition(.zoom(sourceID: "all-\(playlist.id)", in: namespace))
                            } label: {
                                VStack(alignment: .center, spacing: 6) {
                                    Group {
                                        if playlist.artwork.starts(with: "http") {
                                            CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                                                switch phase {
                                                case .empty:
                                                    artworkPlaceholder
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(maxWidth: .infinity)
                                                        .aspectRatio(1, contentMode: .fit)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                case .failure:
                                                    artworkPlaceholder
                                                @unknown default:
                                                    artworkPlaceholder
                                                }
                                            }
                                        } else {
                                            Color.clear
                                                .aspectRatio(1, contentMode: .fit)
                                        }
                                    }

                                    Text(playlist.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity)
                                }
                                .matchedTransitionSource(id: "all-\(playlist.id)", in: namespace)
                            }
                            .buttonStyle(.plain)
                            .haptic(.selection)
                            .onAppear {
                                if let userId = authManager.currentUserId {
                                    Task(priority: .background) {
                                        await viewModel.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Playlists")
        // Start database observation
        .task {
            await viewModel.observeDatabase()
        }
        // Fetch fresh data
        .task {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary)

            ProgressView()
                .progressViewStyle(.circular)
        }
        .aspectRatio(1, contentMode: .fit)
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

#Preview {
    NavigationStack {
        AllPlaylistsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
