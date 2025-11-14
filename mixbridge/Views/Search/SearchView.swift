//
//  SearchView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(text: $searchText, prompt: "Search...")
        }
    }

    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            emptyState
        } else {
            searchResults
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Search Playlists",
            systemImage: "magnifyingglass",
            description: Text("Search for playlists across your music services")
        )
    }

    private var searchResults: some View {
        List {
            Text("Search results for: \(searchText)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Light Mode") {
    SearchView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    SearchView()
        .preferredColorScheme(.dark)
}
