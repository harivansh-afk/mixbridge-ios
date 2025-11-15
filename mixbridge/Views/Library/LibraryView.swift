//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    // Generate 50 sample tracks
    let tracks: [Track] = (1...50).map { index in
        Track(
            title: "Track \(index)",
            artist: "Artist \(index)",
            album: "Album \(index)",
            artwork: "music.note"
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
        }
    }

    private var content: some View {
        List {
            tracksSection
        }
        .listStyle(.plain)
    }

    private var tracksSection: some View {
        Section {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track, number: index + 1, showCover: true)
            }
        }
    }
}

#Preview("Light Mode") {
    LibraryView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LibraryView()
        .preferredColorScheme(.dark)
}
