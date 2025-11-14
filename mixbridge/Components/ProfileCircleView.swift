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
        size: CGFloat = 44
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
                    .fill(.blue.gradient)

                Text(userInitials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
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
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.3),
                            .white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
      
    }
}



// MARK: - Preview
#Preview {
    NavigationStack {
        VStack {
            Text("Content")
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                LiquidGlassProfileButton(
                    profileImage: nil,
                    userName: "Harivansh Rathi",
                    size: 36,
                    action: {}
                )
            }
        }
    }
}
