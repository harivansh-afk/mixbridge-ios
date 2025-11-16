//
//  PlaylistActionButtons.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI

struct PlaylistActionButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                HapticManager.medium()
                onPlay()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .imageScale(.small)
                    Text("Play")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button(action: {
                HapticManager.medium()
                onShuffle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .imageScale(.small)
                    Text("Shuffle")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Light Mode") {
    PlaylistActionButtons(
        onPlay: { print("Play tapped") },
        onShuffle: { print("Shuffle tapped") }
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    PlaylistActionButtons(
        onPlay: { print("Play tapped") },
        onShuffle: { print("Shuffle tapped") }
    )
    .padding()
    .preferredColorScheme(.dark)
}
