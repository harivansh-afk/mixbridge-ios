//
//  TrackRow.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//  Inspired by Cider-Remote LibraryTrackRow
//

import SwiftUI

struct TrackRow: View {
    let track: Track
    let number: Int
    let showCover: Bool
    var onAddToQueue: (() -> Void)?
    var onLike: (() -> Void)?
    var onDelete: (() -> Void)?
    var onTrackAddedToQueue: ((Track, String) -> Void)? // Callback with track + queue track ID
    var trackData: [String: Any]?

    private let coverSize: CGFloat = 44

    init(
        _ track: Track,
        number: Int,
        showCover: Bool = false,
        onAddToQueue: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTrackAddedToQueue: ((Track, String) -> Void)? = nil,
        trackData: [String: Any]? = nil
    ) {
        self.track = track
        self.number = number
        self.showCover = showCover
        self.onAddToQueue = onAddToQueue
        self.onLike = onLike
        self.onDelete = onDelete
        self.onTrackAddedToQueue = onTrackAddedToQueue
        self.trackData = trackData
    }

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        HStack(spacing: 12) {
            // Left side: Track number or album artwork
            leadingContent

            // Middle: Track info
            trackInfo

            Spacer()

            // Right side: Actions
            trailingActions
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                handleDelete()
            } label: {
                Label("", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                handleLike()
            } label: {
                Label("", systemImage: "heart.fill")
            }
            .tint(.pink)

            Button {
                handleAddToQueue()
            } label: {
                Label("", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.blue)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if showCover {
            albumArtwork
        } else {
            trackNumber
        }
    }

    private var trackNumber: some View {
        Text(number, format: .number)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 30)
    }

    private var albumArtwork: some View {
        Group {
            if track.artwork.starts(with: "http") {
                // Real URL - use AsyncImage
                AsyncImage(url: URL(string: track.artwork)) { phase in
                    switch phase {
                    case .empty:
                        artworkPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverSize, height: coverSize)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                // Gradient placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: coverSize, height: coverSize)
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .frame(width: coverSize, height: coverSize)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 16) {
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action Handlers

    private func handleAddToQueue() {
        print("🎵 [TrackRow] handleAddToQueue called for track: \(track.title)")

        // Use custom callback if provided (for backward compatibility)
        if let onAddToQueue = onAddToQueue {
            print("🎵 [TrackRow] Using custom callback")
            onAddToQueue()
            return
        }

        // Standard behavior: use QueueManager
        guard let trackData = trackData else {
            print("❌ [TrackRow] No trackData provided - cannot add to queue")
            errorMessage = "Unable to add track to queue"
            showError = true
            return
        }

        Task {
            isLoading = true
            do {
                try await QueueManager.shared.addTrack(track, rawData: trackData)
                print("✅ [TrackRow] Track added to queue via QueueManager")

                // Notify parent if callback provided
                if let onTrackAddedToQueue = onTrackAddedToQueue,
                   let queueTrackId = QueueManager.shared.queueTracks.first(where: { $0.id == track.id })?.id {
                    onTrackAddedToQueue(track, queueTrackId)
                }
            } catch ConvexError.alreadyInQueue {
                print("ℹ️ [TrackRow] Track already in queue - silently ignoring")
                // Don't show error for duplicates - this is expected
            } catch {
                print("❌ [TrackRow] Failed to add track: \(error)")
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    private func handleLike() {
        print("❤️ [TrackRow] handleLike called for track: \(track.title)")
        print("❤️ [TrackRow] Track ID: \(track.id)")
        print("❤️ [TrackRow] Has custom callback: \(onLike != nil)")

        if let onLike = onLike {
            print("❤️ [TrackRow] Using custom callback")
            HapticManager.medium()
            onLike()
        } else {
            // Default behavior: call API directly
            Task {
                print("📤 [TrackRow] Calling ConvexService.likeTrack")
                isLoading = true
                do {
                    try await ConvexService.shared.likeTrack(trackId: track.id)
                    HapticManager.success()
                    print("✅ [TrackRow] Track liked successfully")
                } catch {
                    HapticManager.error()
                    print("❌ [TrackRow] Failed to like track: \(error)")
                    errorMessage = "Failed to like track: \(error.localizedDescription)"
                    showError = true
                }
                isLoading = false
            }
        }
    }

    private func handleDelete() {
        print("🗑️ [TrackRow] handleDelete called for track: \(track.title)")
        print("🗑️ [TrackRow] Has custom callback: \(onDelete != nil)")

        if let onDelete = onDelete {
            print("🗑️ [TrackRow] Using custom callback")
            HapticManager.warning()
            onDelete()
        } else {
            print("❌ [TrackRow] Delete action not configured")
            HapticManager.error()
            errorMessage = "Delete action not configured"
            showError = true
        }
    }
}

#Preview("Light Mode") {
    List {
        TrackRow(Track.sampleTracks[0], number: 1, showCover: false)
        TrackRow(Track.sampleTracks[1], number: 2, showCover: true)
        TrackRow(Track.sampleTracks[2], number: 3, showCover: true)
    }
    .listStyle(.plain)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    List {
        TrackRow(Track.sampleTracks[0], number: 1, showCover: false)
        TrackRow(Track.sampleTracks[1], number: 2, showCover: true)
        TrackRow(Track.sampleTracks[2], number: 3, showCover: true)
    }
    .listStyle(.plain)
    .preferredColorScheme(.dark)
}
