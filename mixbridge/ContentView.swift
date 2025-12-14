//
//  ContentView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct ContentView: View {

    @State private var expandMiniPlayer: Bool = false
    @Namespace private var animation
    private var playerState = PlayerState.shared
    @State private var selectedTab = 1
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        NativeTabView(selectedTab: $selectedTab)
            .tabBarMinimizeBehavior(.onScrollDown)
            .modifier(MiniPlayerModifier(
                playerState: playerState,
                namespace: animation,
                expandMiniPlayer: $expandMiniPlayer
            ))
            .fullScreenCover(isPresented: $expandMiniPlayer) {
                ExpandedMusicPlayer(
                    isPresented: $expandMiniPlayer,
                    namespace: animation
                )
            }
    }
}

struct MiniPlayerModifier: ViewModifier {
    var playerState: PlayerState
    var namespace: Namespace.ID
    @Binding var expandMiniPlayer: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if playerState.hasActiveTrack {
            content
                .tabViewBottomAccessory {
                    MiniPlayerView()
                        .matchedTransitionSource(id: "MINIPLAYER", in: namespace)
                        .ignoresSafeArea(.keyboard, edges: .all)
                }
                .transition(.opacity)
        } else {
            content
        }
    }
    
    @ViewBuilder
    func MiniPlayerView() -> some View {
        HStack(spacing: 15){
            // Make track info clickable to expand player
            HStack(spacing: 7) {
                // MiniPlayer artwork - no matchedGeometryEffect needed, using matchedTransitionSource on container
                PlayerArtworkView(
                    artwork: playerState.currentTrack.artwork,
                    size: 30,
                    cornerRadius: 6,
                    shadowRadius: 2
                )

                VStack(alignment: .leading, spacing: 0){
                    Text(playerState.currentTrack.title)
                        .font(.footnote.bold())
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    Text(playerState.currentTrack.artist)
                        .font(.caption)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.medium()
                expandMiniPlayer.toggle()
            }

            Button{
                HapticManager.light()
                playerState.togglePlayback()
            }   label: {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .contentShape(.rect)
            }
            .padding(.trailing, 10)
            .buttonStyle(.plain)


            Button{
                HapticManager.light()
                playerState.playNextFromQueue()
            }   label: {
                Image(systemName: "forward.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, 15)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: playerState.isPlaying)
    }
}

struct NativeTabView: View {
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                HomeView()
            } label: {
                Image("house")
            }
            Tab(value: 1) {
                LibraryView()
            } label: {
                Image("list")
            }
            Tab(value: 2, role:.search) {
                SearchView()
            } label: {
                Image("magnifying-glass")
            }
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            // Haptic feedback on tab change
            HapticManager.selection()
        }
    }
}

#Preview("Light Mode") {
    ContentView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .environment(PreloadedDataStore.shared)
        .preferredColorScheme(.dark)
}
