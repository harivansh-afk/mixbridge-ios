import SwiftUI

struct AllSongsView: View {
    @State private var viewModel = LikedViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(QueueManager.self) private var queueManager

    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private let revealThreshold: CGFloat = 90

    private var filteredTracks: [TrackItem] {
        guard !searchText.isEmpty else { return viewModel.likedTracks }
        return viewModel.likedTracks.filter {
            $0.track.title.localizedCaseInsensitiveContains(searchText) ||
            $0.track.artist.localizedCaseInsensitiveContains(searchText)
        }
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
            } else if viewModel.likedTracks.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Your songs will appear here")
                )
            } else {
                List {
                    if filteredTracks.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else {
                        let trackRows = filteredTracks.indexedRows()
                        ForEach(trackRows) { row in
                            TrackRow(
                                row.item.track,
                                number: row.index + 1,
                                showCover: true,
                                soundCloudTrack: row.item.soundCloudTrack,
                                listContext: filteredTracks,
                                indexInList: row.index
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(row.index == 0 ? .hidden : .visible, edges: .top)
                            .listRowSeparator(row.index == trackRows.count - 1 ? .hidden : .visible, edges: .bottom)
                        }
                    }
                }
                .listStyle(.plain)
                .onScrollPhaseChange { oldPhase, newPhase, context in
                    guard oldPhase == .interacting, newPhase != .interacting else { return }
                    let geometry = context.geometry
                    let offset = geometry.contentOffset.y + geometry.contentInsets.top

                    if offset < -revealThreshold && !isSearchPresented {
                        isSearchPresented = true
                        HapticManager.light()
                    }
                }
                .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Songs")
                .navigationAllowDismissalGestures(allowDismissalGesture)
            }
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
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

#Preview {
    NavigationStack {
        AllSongsView()
            .environment(AuthManager.shared)
            .environment(QueueManager.shared)
    }
}
