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
    @State private var playerState = PlayerState.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NativeTabView()
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MiniPlayerView()
                    .matchedTransitionSource(id: "MINIPLAYER", in: animation)
                    .ignoresSafeArea(.keyboard, edges: .all)
            }
            .fullScreenCover(isPresented: $expandMiniPlayer) {
                ExpandedMusicPlayer(
                    isPresented: $expandMiniPlayer,
                    namespace: animation
                )
            }
    }

    @ViewBuilder
    func PlayerInfo(_ track: Track, size: CGSize) -> some View {
        HStack(spacing: 7) {
            Group {
                if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
                    CachedAsyncImagePhase(url: url) { phase in
                        switch phase {
                        case .empty:
                            miniArtworkPlaceholder(size: size)
                        case .success(let image):
                            image
                                .resizable()
                                    .aspectRatio(contentMode: .fill)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        case .failure:
                            miniArtworkPlaceholder(size: size)
                        @unknown default:
                            miniArtworkPlaceholder(size: size)
                        }
                    }
                } else {
                    miniArtworkPlaceholder(size: size)
                }
            }

            VStack(alignment: .leading, spacing: 0){
                Text(track.title)
                    .font(.footnote.bold())
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    func miniArtworkPlaceholder(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
    }
    
    @ViewBuilder
    func MiniPlayerView() -> some View{
        HStack(spacing: 15){
            // Make track info clickable to expand player
            HStack(spacing: 7) {
                PlayerInfo(playerState.currentTrack, size: .init(width: 30, height: 30))
                    .id(playerState.currentTrack.id)
                    .contentTransition(.interpolate)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.medium()
                expandMiniPlayer.toggle()
            }

            Button{
                HapticManager.medium()
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
    @State private var selectedTab = 0

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
            Tab(value: 2) {
                LikedView()
            } label: {
                Image("heart")
            }
            Tab(value: 3, role:.search) {
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
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .environment(AuthManager.shared)
        .environment(UserProfileManager.shared)
        .environment(QueueManager.shared)
        .preferredColorScheme(.dark)
}
