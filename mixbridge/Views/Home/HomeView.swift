//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 16) {
            // Placeholder for home content
            ContentUnavailableView(
                "Mixbridge",
                systemImage: "music.note",
                description: Text("welcome to better music")
            )
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
