//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    var tracks = (1...50).map { "Track \($0)" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
        }
    }

    private var content: some View {
        List {
            Tracks
        }
    }

    private var Tracks: some View {
        Section() {
            ForEach(tracks, id: \.self) { track in
                Text(track)
            }
        }
    }
}
