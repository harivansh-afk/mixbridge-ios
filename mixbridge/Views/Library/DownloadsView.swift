//
//  DownloadsView.swift
//  mixbridge
//
//  View for displaying downloaded tracks and playlists available for offline playback.
//

import SwiftUI

// MARK: - Downloads Tab

enum DownloadsTab: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case playlists = "Playlists"

    var id: String { rawValue }
}

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(QueueManager.self) private var queueManager

    @State private var selectedTab: DownloadsTab = .tracks
    @State private var selectedPlaylist: Playlist?
    @State private var showingDeleteAllAlert = false
    @Namespace private var namespace

    private var trackItems: [TrackItem] {
        downloadManager.downloadedTracks.compactMap { info in
            guard let scTrack = info.soundCloudTrack else { return nil }
            return TrackItem(soundCloudTrack: scTrack)
        }
    }

    var body: some View {
        content
            .navigationTitle("Downloaded")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !downloadManager.downloadedTracks.isEmpty || !downloadManager.downloadedPlaylists.isEmpty {
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
            .navigationDestination(item: $selectedPlaylist) { playlist in
                PlaylistDetailView(playlist: playlist)
                    .navigationTransition(.zoom(sourceID: "downloaded-\(playlist.id)", in: namespace))
            }
    }

    @ViewBuilder
    private var content: some View {
        if downloadManager.isLoading && downloadManager.downloadedTracks.isEmpty {
            ProgressView()
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if downloadManager.downloadedTracks.isEmpty && downloadManager.downloadedPlaylists.isEmpty {
            ContentUnavailableView(
                "No Downloads",
                systemImage: "arrow.down.circle"
            )
        } else {
            downloadsList
        }
    }

    private var downloadsList: some View {
        List {
            // Tab Picker Section
            Section {
                Picker("Downloaded Items", selection: $selectedTab) {
                    ForEach(DownloadsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .glassEffect(.regular)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            // Content based on selected tab
            switch selectedTab {
            case .tracks:
                tracksContent

            case .playlists:
                playlistsContent
            }
        }
        .listStyle(.plain)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Tracks Content

    @ViewBuilder
    private var tracksContent: some View {
        if downloadManager.downloadedTracks.isEmpty {
            ContentUnavailableView("No downloaded tracks", systemImage: "music.note")
                .listRowSeparator(.hidden)
        } else {
            ForEach(Array(downloadManager.downloadedTracks.enumerated()), id: \.element.id) { index, item in
                TrackRow(
                    item.track,
                    number: index + 1,
                    showCover: true,
                    soundCloudTrack: item.soundCloudTrack,
                    listContext: trackItems,
                    indexInList: index
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(index == downloadManager.downloadedTracks.count - 1 ? .hidden : .visible, edges: .bottom)
            }
        }
    }

    // MARK: - Playlists Content

    @ViewBuilder
    private var playlistsContent: some View {
        if downloadManager.downloadedPlaylists.isEmpty {
            ContentUnavailableView("No downloaded playlists", systemImage: "music.note.list")
                .listRowSeparator(.hidden)
        } else {
            ForEach(Array(downloadManager.downloadedPlaylists.enumerated()), id: \.element.id) { index, item in
                playlistRow(item: item, index: index, total: downloadManager.downloadedPlaylists.count)
            }
        }
    }

    // MARK: - Playlist Row

    private func playlistRow(item: DownloadedPlaylistInfo, index: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            if item.playlist.artwork.starts(with: "http"),
               let url = URL(string: item.playlist.artwork) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.playlist.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.playlist.creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("\(item.trackCount) tracks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .matchedTransitionSource(id: "downloaded-\(item.playlist.id)", in: namespace)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.selection()
            selectedPlaylist = item.playlist
        }
        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
        .listRowSeparator(index == total - 1 ? .hidden : .visible, edges: .bottom)
    }
}

#Preview("Light Mode") {
    NavigationStack {
        DownloadsView()
            .environment(QueueManager.shared)
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        DownloadsView()
            .environment(QueueManager.shared)
    }
    .preferredColorScheme(.dark)
}
