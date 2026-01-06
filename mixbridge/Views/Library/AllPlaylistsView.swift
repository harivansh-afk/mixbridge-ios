import SwiftUI

struct AllPlaylistsView: View {
    @State private var viewModel = LibraryViewModel()
    @Environment(AuthManager.self) private var authManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var namespace

    private let revealThreshold: CGFloat = 90

    private var filteredPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return viewModel.playlists }
        return viewModel.playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

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
                ScrollView {
                    if filteredPlaylists.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(minHeight: 300)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ],
                            spacing: 20
                        ) {
                            ForEach(filteredPlaylists) { playlist in
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
                }
                .onScrollGeometryChangeIfAvailable(for: CGFloat.self, of: { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                }, action: { _, newValue in
                    scrollOffset = newValue
                })
                .onScrollPhaseChangeIfAvailable { oldPhase, newPhase, context in
                    guard oldPhase == .interacting, newPhase != .interacting else { return }
                    let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top

                    // Show search when pulled past threshold
                    if offset < -revealThreshold && !isSearchPresented {
                        isSearchPresented = true
                        HapticManager.light()
                    }
                }
                .refreshable {
                    if let userId = authManager.currentUserId {
                        await viewModel.refresh(userId: userId, forceRefresh: true)
                    }
                }
                .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Playlists")
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Playlists")
        // Start database observation
        .task {
            if let userId = authManager.currentUserId {
                await viewModel.observeDatabase(userId: userId)
            }
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
