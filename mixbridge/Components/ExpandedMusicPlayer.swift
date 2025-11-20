//
//  ExpandedMusicPlayer.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/10/25.
//

import SwiftUI

// MARK: - Smart Container
/// The "Smart" container that connects the PlayerState (Data) to the ExpandedPlayerView (UI).
/// It handles all the logic, bindings, and state management.
struct ExpandedMusicPlayer: View {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID
    
    @State private var playerState = PlayerState.shared
    @State private var isDraggingProgress = false
    @State private var isDraggingVolume = false

    
    // Compute duration safely
    private var duration: Double {
        if playerState.duration > 0 {
            return playerState.duration
        }
        return playerState.currentTrack.duration == 0 ? 210 : playerState.currentTrack.duration
    }
    
    var body: some View {
        ExpandedPlayerView(
            track: playerState.currentTrack,
            isPlaying: playerState.isPlaying,
            namespace: namespace,
            playbackPosition: Binding(
                get: { playerState.playbackPosition },
                set: { newValue in playerState.playbackPosition = newValue }
            ),
            duration: duration,
            volume: $playerState.volume,
            isDraggingProgress: $isDraggingProgress,
            isDraggingVolume: $isDraggingVolume,
            onPlayPause: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    playerState.togglePlayback()
                }
            },
            onNext: { playerState.playNextFromQueue() },
            onPrevious: { playerState.playPreviousFromQueue() },
            onSeek: { editing in
                if !editing {
                    // Seek only when drag ends
                    playerState.seek(to: playerState.playbackPosition)
                }
            },
            onDismiss: {
                withAnimation {
                    isPresented = false
                }
            }
        )
    }
}

// MARK: - Dumb UI
/// A pure UI component that knows nothing about the PlayerState singleton.
/// It receives all data via arguments, making it reusable and testable.
struct ExpandedPlayerView: View {
    // Data
    let track: Track
    let isPlaying: Bool
    let namespace: Namespace.ID
    
    // Bindings
    @Binding var playbackPosition: Double
    let duration: Double
    @Binding var volume: Double
    @Binding var isDraggingProgress: Bool
    @Binding var isDraggingVolume: Bool
        
    // Actions
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (Bool) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        //Main stack below body
        ZStack(alignment: .top) {
            
            
            
            // the blurry bg shit
            PlayerBackgroundView(artwork: track.artwork)
            
            VStack(spacing: 0) {
                // 2. Artwork (Full Width, Top)
                PlayerArtworkView(
                    artwork: track.artwork,
                    namespace: namespace,
                    id: track.id,
                    cornerRadius: 50,
                    shadowRadius: 0
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 400)
                .ignoresSafeArea(.container, edges: .top)
                
                // 3. Content (Info, Progress, Controls)
                VStack(spacing: 32) {
                    VStack(spacing: 0) {
                        PlayerInfoView(title: track.title, artist: track.artist)
                            .id(track.id) // Transition ID
                            .contentTransition(.interpolate)
                            .animation(.easeInOut(duration: 0.25), value: track.id)
                            .padding(.top, -10)
                        PlayerProgressView(
                            value: $playbackPosition,
                            duration: duration,
                            isDragging: $isDraggingProgress,
                            onEditingChanged: onSeek
                        )
                        .frame(width: .infinity, height: .infinity)
                        
                        .padding(.top, 30)
                    }
                    .padding(.top, 0)
                    .padding(.horizontal, 200)
                    // No spacing from Artwork, flush
                    // Removed horizontal padding to let progress bar be full width
                    
                    PlayerControlsView(
                        isPlaying: isPlaying,
                        onPlayPause: onPlayPause,
                        onNext: onNext,
                        onPrevious: onPrevious
                    )
                    .padding(.horizontal, 24)
                    
                }
                
            }
            
        }
        
        
        
        // Setup the hero transition
        .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
    }
    
    
}


// MARK: - Preview
#Preview("Expanded Player") {
    @Previewable @Namespace var namespace
    @Previewable @State var position: Double = 45
    @Previewable @State var volume: Double = 1
    
    ExpandedPlayerView(
        track: Track.sampleTracks[0],
        isPlaying: true,
        namespace: namespace,
        playbackPosition: $position,
        duration: 210,
        volume: $volume,
        isDraggingProgress: .constant(false),
        isDraggingVolume: .constant(false),
        onPlayPause: {},
        onNext: {},
        onPrevious: {},
        onSeek: { _ in },
        onDismiss: {}
    )
    .preferredColorScheme(.dark) // Music players often look best in dark
}
