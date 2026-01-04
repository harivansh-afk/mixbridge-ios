//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
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
        content
            .navigationTitle("Liked")
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
            .refreshable {
                if let userId = authManager.currentUserId {
                    await viewModel.refresh(userId: userId, forceRefresh: true)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
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
            emptyState
        } else {
            likedList
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
                        await viewModel.refresh(userId: userId)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }

    private var likedList: some View {
        List {
            if filteredTracks.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, item in
                    TrackRow(
                        item.track,
                        number: index + 1,
                        showCover: true,
                        soundCloudTrack: item.soundCloudTrack,
                        listContext: filteredTracks,
                        indexInList: index
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
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
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Liked")
        .navigationAllowDismissalGestures(allowDismissalGesture)
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        LikedView()
    }
    .environment(AuthManager.shared)
    .environment(QueueManager.shared)
    .preferredColorScheme(.dark)
}
