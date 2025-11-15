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

    private let coverSize: CGFloat = 44

    init(_ track: Track, number: Int, showCover: Bool = false) {
        self.track = track
        self.number = number
        self.showCover = showCover
    }

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
                // Delete action
            } label: {
                Label("", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
            } label: {
                Label("", systemImage: "heart.fill")
            }
            .tint(.pink)

            Button {
                // Add to playlist
            } label: {
                Label("", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.blue)
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
