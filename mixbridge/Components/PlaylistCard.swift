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
                    .lineLimit(2)

                Text(playlist.creator)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: artworkSize)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if playlist.artwork.starts(with: "http") {
                AsyncImage(url: URL(string: playlist.artwork)) { phase in
                    switch phase {
                    case .empty:
                        artworkPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        artworkPlaceholder
                    @unknown default:
                        artworkPlaceholder
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: artworkSize, height: artworkSize)
                    .overlay {
                        Image(systemName: playlist.artwork)
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
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
    PlaylistCard(playlist: Playlist.samplePlaylists[0])
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Single Card - Dark") {
    PlaylistCard(playlist: Playlist.samplePlaylists[0])
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Multiple Cards - Light") {
    ScrollView(.horizontal) {
        HStack(spacing: 16) {
            ForEach(Playlist.samplePlaylists.prefix(3)) { playlist in
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
            ForEach(Playlist.samplePlaylists.prefix(3)) { playlist in
                PlaylistCard(playlist: playlist)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
