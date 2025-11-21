//
//  PlaylistCard.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistCard: View {
    let playlist: Playlist
    private let artworkSize: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(playlist.creator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: artworkSize)
    }

    @ViewBuilder
    private var artwork: some View {
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
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: artworkSize, height: artworkSize)
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .frame(width: artworkSize, height: artworkSize)
    }
}

#Preview("Single Card - Light") {
    PlaylistCard(playlist: Playlist(
        name: "Sample Playlist",
        creator: "Artist",
        artwork: ""
    ))
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Single Card - Dark") {
    PlaylistCard(playlist: Playlist(
        name: "Sample Playlist",
        creator: "Artist",
        artwork: ""
    ))
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Multiple Cards - Light") {
    ScrollView(.horizontal) {
        HStack(spacing: 16) {
            ForEach([
                Playlist(name: "Playlist 1", creator: "Artist 1", artwork: ""),
                Playlist(name: "Playlist 2", creator: "Artist 2", artwork: ""),
                Playlist(name: "Playlist 3", creator: "Artist 3", artwork: "")
            ]) { playlist in
                PlaylistCard(playlist: playlist)
            }
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Multiple Cards - Dark") {
    ScrollView(.horizontal) {
        HStack(spacing: 16) {
            ForEach([
                Playlist(name: "Playlist 1", creator: "Artist 1", artwork: ""),
                Playlist(name: "Playlist 2", creator: "Artist 2", artwork: ""),
                Playlist(name: "Playlist 3", creator: "Artist 3", artwork: "")
            ]) { playlist in
                PlaylistCard(playlist: playlist)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
