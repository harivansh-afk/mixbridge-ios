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
                .grayscale(1.0)
                .ignoresSafeArea()
                .blur(radius: 5, opaque: true)
             

            // Dark overlay
            

            // Content centered
            VStack(spacing: 7) {
                // Name
                if let profile = profile {
                    VStack(spacing: 8) {
                        Text("@\(profile.username)")
                            .font(.custom("InstrumentSerif-Italic", size: 20))
                            .foregroundColor(.white)

                        // Provider badge
                        if let provider = AuthManager.shared.currentProvider {
                            HStack(spacing: 4) {
                                Image(systemName: provider == .spotify ? "music.note" : "cloud.fill")
                                    .font(.caption2)
                                Text("Signed in with \(provider == .spotify ? "Spotify" : "SoundCloud")")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                // Stats
                HStack(spacing: 30) {
                    // Followers
                    VStack(spacing: 5) {
                        Text("\(profile?.followers_count ?? 0)")
                            .font(.custom("InstrumentSerif-Italic", size: 15))
                            .foregroundColor(.white)

                        Text("Followers")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 30)

                    // Playlists
                    VStack(spacing: 5) {
                        Text("\(profile?.playlist_count ?? 0)")
                            .font(.custom("InstrumentSerif-Italic", size: 15))
                            .foregroundColor(.white)

                        Text("Playlists")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
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
