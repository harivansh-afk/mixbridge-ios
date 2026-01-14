//
//  LibraryNavigationRow.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct LibraryNavigationRow: View {
    let icon: String
    let title: String
    let iconColor: Color
    var isSystemImage: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if isSystemImage {
                    Image(systemName: icon)
                } else {
                    Image(icon)
                        .resizable()
                        .frame(width: 25, height:25)
                }
            }
            .font(.title3)
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview("Light Mode") {
    VStack(spacing: 0) {
        LibraryNavigationRow(
            icon: "heart",
            title: "Liked",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "playlist",
            title: "Playlists",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "microphone",
            title: "Artists",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "music-note-simple",
            title: "Songs",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "arrow-circle-down",
            title: "Downloaded",
            iconColor: .primary,
            isSystemImage: false
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 0) {
        LibraryNavigationRow(
            icon: "heart",
            title: "Liked",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "playlist",
            title: "Playlists",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "microphone",
            title: "Artists",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "music-note-simple",
            title: "Songs",
            iconColor: .primary,
            isSystemImage: false
        )

        LibraryNavigationRow(
            icon: "arrow-circle-down",
            title: "Downloaded",
            iconColor: .primary,
            isSystemImage: false
        )
    }
    .preferredColorScheme(.dark)
}
