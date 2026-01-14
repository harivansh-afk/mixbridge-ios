//
//  ProfileAvatarButton.swift
//  mixbridge
//

import SwiftUI

struct ProfileAvatarButton: View {
    let avatarUrl: String?
    let displayName: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            avatar
        }
        .buttonStyle(.plain)
    }

    private var avatar: some View {
        Group {
            if let avatarUrl,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(userInitials)
                            .font(.system(size: max(12, size * 0.4), weight: .medium))
                            .foregroundStyle(.primary)
                    }
            }
        }
    }

    private var userInitials: String {
        displayName
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

