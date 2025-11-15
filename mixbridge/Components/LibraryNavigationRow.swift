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

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

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
            icon: "music.note.list",
            title: "Playlists",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "music.mic",
            title: "Artists",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "arrow.down.circle",
            title: "Downloaded",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "music.note",
            title: "Songs",
            iconColor: .red
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 0) {
        LibraryNavigationRow(
            icon: "music.note.list",
            title: "Playlists",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "music.mic",
            title: "Artists",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "arrow.down.circle",
            title: "Downloaded",
            iconColor: .red
        )

        LibraryNavigationRow(
            icon: "music.note",
            title: "Songs",
            iconColor: .red
        )
    }
    .preferredColorScheme(.dark)
}
