//
//  ProfileCircleView.swift
//  mixbridge
//
//  Created for displaying user profile avatar
//

import SwiftUI

struct ProfileCircleView: View {
    // MARK: - Properties
    let profileImage: String?
    let userName: String
    let size: CGFloat

    // MARK: - Initialization
    init(
        profileImage: String? = nil,
        userName: String = "User",
        size: CGFloat = 36
    ) {
        self.profileImage = profileImage
        self.userName = userName
        self.size = size
    }

    // MARK: - Body
    var body: some View {
        profileContent
            .frame(width: size, height: size)
    }

    // MARK: - Private Views
    @ViewBuilder
    private var profileContent: some View {
        if let profileImage = profileImage {
            // Custom image
            Image(profileImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            // User initials
            ZStack {
                Circle()
            }
        }
    }

    // MARK: - Private Properties
    private var userInitials: String {
        userName
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

// MARK: - Liquid Glass Profile Button
struct LiquidGlassProfileButton: View {
    let profileImage: String?
    let userName: String
    let size: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ProfileCircleView(
                profileImage: profileImage,
                userName: userName,
                size: size
            )
        }
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .overlay(
            Circle()
        )
        .shadow(
            color: colorScheme == .dark
                ? .black.opacity(0.3)
                : .black.opacity(0.1),
            radius: 2,
            x: 0,
            y: 1
        )

    }
}



// MARK: - Preview
#Preview("Light Mode") {
    NavigationStack {
        VStack(spacing: 30) {
            ProfileCircleView(
                userName: "Harivansh Rathi",
                size: 80
            )

            ProfileCircleView(
                userName: "Alex Morgan",
                size: 60
            )

            LiquidGlassProfileButton(
                profileImage: nil,
                userName: "Harivansh Rathi",
                size: 35,
                action: {}
            )
        }
        .navigationTitle("Profiles")
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        VStack(spacing: 30) {
            ProfileCircleView(
                userName: "Harivansh Rathi",
                size: 80
            )

            ProfileCircleView(
                userName: "Alex Morgan",
                size: 60
            )

            LiquidGlassProfileButton(
                profileImage: nil,
                userName: "Harivansh Rathi",
                size: 44,
                action: {}
            )
        }
        .navigationTitle("Profiles")
    }
    .preferredColorScheme(.dark)
}
