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

    // MARK: - Properties
    private let userName = "Harivansh Rathi"
    private let userEmail = "harivansh@example.com"
    private let profileImage: String? = nil

    // MARK: - Body
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileCircleView(
                            profileImage: "pfp",
                            userName: userName,
                            size: 32
                        )
                        .onTapGesture {
                            showingAccount.toggle()
                        }
                    }
                }
                .sheet(isPresented: $showingAccount) {
                    AccountBottomSheet(
                        isPresented: $showingAccount,
                        userName: userName,
                        userEmail: userEmail,
                        profileImage: profileImage
                    )
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
