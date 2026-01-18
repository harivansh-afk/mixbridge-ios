//
//  ConnectSpotifyScreen.swift
//  mixbridge
//
//  SwiftUI view for connecting Spotify account.
//

import SwiftUI
import AuthenticationServices

struct ConnectSpotifyScreen: View {
    @State private var spotifyAuthManager = SpotifyAuthManager.shared
    @State private var contextProvider = SpotifyPresentationContextProvider()
    @Environment(\.dismiss) private var dismiss
    
    var onConnected: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Spotify Logo/Icon
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    // Title
                    Text("Connect Spotify")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    // Description
                    Text("Link your Spotify account to access your playlists and liked songs.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Error message
                        if let error = spotifyAuthManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        // Connect Button
                        Button {
                            HapticManager.heavy()
                            Analytics.shared.track("spotify_connect_tapped")
                            spotifyAuthManager.startOAuthFlow()
                        } label: {
                            HStack(spacing: 12) {
                                if spotifyAuthManager.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "music.note")
                                    Text("Connect with Spotify")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(spotifyAuthManager.isLoading)
                        
                        // Skip button
                        Button {
                            dismiss()
                        } label: {
                            Text("Skip for now")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 20)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: spotifyAuthManager.isConnected) { _, isConnected in
            if isConnected {
                Analytics.shared.track("spotify_connect_success")
                onConnected?()
                dismiss()
            }
        }
        .onAppear {
            Analytics.shared.track("spotify_connect_screen_viewed")
        }
    }
}

// MARK: - Presentation Context Provider

private class SpotifyPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first {
            return window
        }
        
        return UIWindow()
    }
}

#Preview {
    ConnectSpotifyScreen()
}
