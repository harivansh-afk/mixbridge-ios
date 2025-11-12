//
//  LikedView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LikedView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Liked")
        }
    }

    @ViewBuilder
    private var content: some View {
        // Placeholder for liked content
        ContentUnavailableView(
            "No Liked Songs",
            systemImage: "heart",
            description: Text("Your liked songs will appear here")
        )
    }
}

#Preview {
    LikedView()
}
