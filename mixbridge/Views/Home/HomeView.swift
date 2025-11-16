//
//  HomeView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct HomeView: View {
    // MARK: - State
    @State private var showingAccount = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UserProfileManager.self) private var profileManager

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with title and profile icon
                    HStack {
                        Text("Home")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Spacer()

                        // Profile icon
                        if let avatarUrl = profileManager.avatarUrl,
                           let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(.gray.opacity(0.3))
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .onTapGesture {
                                showingAccount.toggle()
                            }
                        } else {
                            ProfileCircleView(
                                profileImage: nil,
                                userName: profileManager.displayName,
                                size: 32
                            )
                            .onTapGesture {
                                showingAccount.toggle()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Content
                    content
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    userName: profileManager.displayName,
                    userEmail: nil,
                    profileImage: nil
                )
            }
            .task {
                // Load profile when view appears
                if let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                }
            }
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

#Preview("Light Mode") {
    HomeView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    HomeView()
        .preferredColorScheme(.dark)
}
