//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
    // Generate sample liked tracks
    let likedTracks: [Track] = (1...20).map { index in
        Track(
            title: "Liked Track \(index)",
            artist: "Artist \(index)",
            album: "Album \(index)",
            artwork: "music.note"
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Liked")
        }
    }

    @ViewBuilder
    private var content: some View {
        if likedTracks.isEmpty {
            emptyState
        } else {
            tracksList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }

    private var tracksList: some View {
        List {
            tracksSection
        }
        .listStyle(.plain)
    }

    private var tracksSection: some View {
        Section {
            ForEach(Array(likedTracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track, number: index + 1, showCover: true)
            }
        }
    }
}

#Preview {
    LikedView()
}
