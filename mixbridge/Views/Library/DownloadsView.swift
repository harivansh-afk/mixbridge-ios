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

    @State private var showingDeleteAllAlert = false

    private var trackItems: [TrackItem] {
        downloadManager.downloadedTracks.compactMap { info in
            guard let scTrack = info.soundCloudTrack else { return nil }
            return TrackItem(soundCloudTrack: scTrack)
        }
    }

    var body: some View {
        Group {
            if downloadManager.isLoading && downloadManager.downloadedTracks.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if downloadManager.downloadedTracks.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download tracks to listen offline. Tap the download button on any track.")
                )
            } else {
                List {
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
                    }
                }
                .listStyle(.plain)
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
    }
}

#Preview {
    NavigationStack {
        DownloadsView()
            .environment(QueueManager.shared)
    }
}
