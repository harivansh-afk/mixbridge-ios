//
//  ProfileStatsView.swift
//  mixbridge
//
//  Profile stats page with background image
//

import SwiftUI

struct ProfileStatsView: View {
    let profile: SoundCloudProfile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background Image
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
             

            // Dark overlay
            

            // Content centered
            VStack(spacing: 32) {
                // Avatar
                if let profile = profile,
                   let avatarUrl = profile.avatar_url,
                   let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(.gray.opacity(0.3))
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    )
                } else {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.5))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                        )
                }

                // Name
                if let profile = profile {
                    VStack(spacing: 8) {
                        Text("@\(profile.username)")
                            .font(.custom("InstrumentSerif-Italic", size: 30))
                            .foregroundColor(.white)
                    }
                }

                // Stats
                HStack(spacing: 30) {
                    // Followers
                    VStack(spacing: 5) {
                        Text("\(profile?.followers_count ?? 0)")
                            .font(.custom("InstrumentSerif-Italic", size: 25))
                            .foregroundColor(.white)

                        Text("Followers")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 55)

                    // Playlists
                    VStack(spacing: 5) {
                        Text("\(profile?.playlist_count ?? 0)")
                            .font(.custom("InstrumentSerif-Italic", size: 25))
                            .foregroundColor(.white)

                        Text("Playlists")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 40)
            }
        }
        .swipeBackGesture()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileStatsView(profile: nil)
    }
}
