//
//  PlaylistCarousel.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistCarousel: View {
    let title: String
    let playlists: [Playlist]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview("Light Mode") {
    NavigationStack {
        PlaylistCarousel(
            title: "Recently Added",
            playlists: Playlist.samplePlaylists
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        PlaylistCarousel(
            title: "Your Playlists",
            playlists: Playlist.samplePlaylists
        )
    }
    .preferredColorScheme(.dark)
}
