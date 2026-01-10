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
                        Button(role: .destructive) {
                            showingDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
            storageHeader

            if filteredTracks.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, item in
                    DownloadedTrackRow(
                        item: item,
                        number: index + 1,
                        listContext: filteredTracks,
                        indexInList: index
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await downloadManager.deleteDownload(trackId: item.track.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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

    private var storageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(downloadManager.downloadedTracks.count) tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(formatStorageSize(totalSize))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var totalSize: Int64 {
        downloadManager.downloadedTracks.reduce(0) { $0 + $1.fileSize }
    }

    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Downloaded Track Row

struct DownloadedTrackRow: View {
    let item: DownloadedTrackInfo
    let number: Int
    let listContext: [DownloadedTrackInfo]
    let indexInList: Int

    @Environment(QueueManager.self) private var queueManager
    private let playerState = PlayerState.shared

    init(item: DownloadedTrackInfo, number: Int, listContext: [DownloadedTrackInfo], indexInList: Int) {
        self.item = item
        self.number = number
        self.listContext = listContext
        self.indexInList = indexInList
    }

    var body: some View {
        Button {
            playTrack()
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                artwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.track.title)
                        .font(.body)
                        .lineLimit(1)

                    Text(item.track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                downloadedIndicator
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if item.track.artwork.starts(with: "http"),
           let url = URL(string: item.track.artwork) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                artworkPlaceholder
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.secondary.opacity(0.2))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }

    private var downloadedIndicator: some View {
        Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(.green)
            .font(.title3)
    }

    private func playTrack() {
        guard let scTrack = item.soundCloudTrack else { return }

        HapticManager.selection()

        let trackItems = listContext.compactMap { info -> TrackItem? in
            guard let scTrack = info.soundCloudTrack else { return nil }
            return TrackItem(soundCloudTrack: scTrack)
        }

        playerState.playFromList(items: trackItems, startIndex: indexInList)
    }
}

#Preview {
    NavigationStack {
        DownloadsView()
            .environment(QueueManager.shared)
    }
}
