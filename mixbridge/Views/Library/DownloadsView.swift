//
//  DownloadsView.swift
//  mixbridge
//
//  View for displaying downloaded tracks available for offline playback.
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(QueueManager.self) private var queueManager

    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var showingDeleteAllAlert = false
    @State private var allowDismissalGesture: AllowedNavigationDismissalGestures = .none

    private let revealThreshold: CGFloat = 90

    private var filteredTracks: [DownloadedTrackInfo] {
        guard !searchText.isEmpty else { return downloadManager.downloadedTracks }
        return downloadManager.downloadedTracks.filter {
            $0.track.title.localizedCaseInsensitiveContains(searchText) ||
            $0.track.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var trackItems: [TrackItem] {
        filteredTracks.compactMap { info in
            guard let scTrack = info.soundCloudTrack else { return nil }
            return TrackItem(soundCloudTrack: scTrack)
        }
    }

    var body: some View {
        Group {
            if downloadManager.downloadedTracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .navigationTitle("Downloaded")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !downloadManager.downloadedTracks.isEmpty {
                    Menu {
                        Button {
                            showingDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("Delete All Downloads?", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task {
                    await downloadManager.deleteAllDownloads()
                }
            }
        } message: {
            Text("This will remove all downloaded tracks from your device. You can download them again anytime.")
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            allowDismissalGesture = .all
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Downloads",
            systemImage: "arrow.down.circle",
            description: Text("Download tracks to listen offline. Tap the download button on any track.")
        )
    }

    private var trackList: some View {
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
                        listContext: trackItems,
                        indexInList: index
                    )
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
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search Downloads")
        .navigationAllowDismissalGestures(allowDismissalGesture)
    }

}

#Preview {
    NavigationStack {
        DownloadsView()
            .environment(QueueManager.shared)
    }
}
