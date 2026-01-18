//
//  SpotifyConnectionView.swift
//  mixbridge
//
//  View for managing Spotify connection in Settings.
//

import SwiftUI

struct SpotifyConnectionView: View {
    @State private var spotifyAuthManager = SpotifyAuthManager.shared
    @State private var showDisconnectAlert = false
    @State private var showConnectSheet = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Connection Status Card
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Spotify Icon
                    ZStack {
                        Circle()
                            .fill(spotifyAuthManager.isConnected ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(spotifyAuthManager.isConnected ? .black : .gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spotify")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text(spotifyAuthManager.isConnected ? "Connected" : "Not connected")
                            .font(.subheadline)
                            .foregroundStyle(spotifyAuthManager.isConnected ? .green : .secondary)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    Circle()
                        .fill(spotifyAuthManager.isConnected ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                }
                
                Divider()
                
                // Action Button
                Button {
                    HapticManager.medium()
                    if spotifyAuthManager.isConnected {
                        showDisconnectAlert = true
                    } else {
                        showConnectSheet = true
                    }
                } label: {
                    HStack {
                        Image(systemName: spotifyAuthManager.isConnected ? "link.badge.minus" : "link.badge.plus")
                        Text(spotifyAuthManager.isConnected ? "Disconnect" : "Connect Spotify")
                    }
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(spotifyAuthManager.isConnected ? .red : .green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        spotifyAuthManager.isConnected 
                            ? Color.red.opacity(0.1) 
                            : Color.green.opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Info text
            if !spotifyAuthManager.isConnected {
                Text("Connect your Spotify account to access your playlists and liked songs alongside SoundCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .alert("Disconnect Spotify", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { @MainActor in
                    spotifyAuthManager.disconnect()
                    Analytics.shared.track("spotify_disconnected")
                }
            }
        } message: {
            Text("Your Spotify playlists will no longer be accessible in the app. You can reconnect anytime.")
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSpotifyScreen()
        }
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SpotifyConnectionView()
    }
    .preferredColorScheme(.dark)
}
