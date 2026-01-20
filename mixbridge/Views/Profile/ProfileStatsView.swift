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

    private let staticPeelProgress: Double = 0.33

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - same as ConnectSoundCloudScreen
                backgroundLayer(size: geometry.size)
                    .grayscale(1.0)
                    .blur(radius: 5, opaque: true)

                // Content centered
                VStack(spacing: 7) {
                    // Name
                    if let profile = profile {
                        VStack(spacing: 8) {
                            Text("@\(profile.username)")
                                .font(.custom("InstrumentSerif-Italic", size: 20))
                                .foregroundColor(.white)
                        }
                    }

                    // Stats - only show for SoundCloud (Spotify doesn't have this data)
                    if AuthManager.shared.currentProvider != .spotify {
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
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        if PeelMetalView.isMetalAvailable {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                PeelMetalView(
                    bottomImageName: "background",
                    topImageName: nil,
                    progress: staticPeelProgress,
                    size: size,
                    amplitude: 0.06,
                    frequency: 2.2
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
            }
        } else {
            Image("background")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileStatsView(profile: nil)
    }
}
