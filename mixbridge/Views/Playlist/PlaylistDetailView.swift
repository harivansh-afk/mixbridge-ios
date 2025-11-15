//
//  PlaylistDetailView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss

    private let artworkSize: CGFloat = 300

    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    artwork
                        .padding(.top, 20)

                    playlistInfo

                    actionButtons
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            tracksSection
        }
        .listStyle(.plain)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        // Add friend action
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.body)
                    }

                    Button {
                        // Download action
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.body)
                    }

                    Button {
                        // More options
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                    }
                }
            }
        }
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
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
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
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: artworkSize, height: artworkSize)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .overlay {
                        Image(systemName: playlist.artwork)
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
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
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private var playlistInfo: some View {
        VStack(spacing: 8) {
            Text(playlist.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(playlist.creator)
                .font(.body)
                .foregroundStyle(.red)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                // Play action
            },
            onShuffle: {
                // Shuffle action
            }
        )
    }

    private var tracksSection: some View {
        Section {
            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track, number: index + 1, showCover: true)
            }
        }
        .listSectionSeparator(.visible, edges: .top)
    }
}

#Preview("Light Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist.samplePlaylists[0])
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        PlaylistDetailView(playlist: Playlist.samplePlaylists[0])
    }
    .preferredColorScheme(.dark)
}
