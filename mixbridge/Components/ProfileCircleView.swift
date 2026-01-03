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
        }
        .navigationTitle("Profiles")
    }
    .preferredColorScheme(.dark)
}
