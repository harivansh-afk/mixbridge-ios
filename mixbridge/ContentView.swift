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
                    .onTapGesture {
                        HapticManager.medium()
                        expandMiniPlayer.toggle()
                    }
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
                    AsyncImage(url: url) { phase in
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

            VStack(alignment: .leading, spacing: 3){
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
            PlayerInfo(playerState.currentTrack, size: .init(width: 30, height: 30))
            Spacer(minLength: 0)

            Button{
                HapticManager.medium()
                playerState.isPlaying.toggle()
            }   label: {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .contentShape(.rect)
            }
            .padding(.trailing, 10)
            .buttonStyle(.plain)


            Button{
                HapticManager.light()
            }   label: {
                Image(systemName: "forward.fill")
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, 15)
        .buttonStyle(.plain)
    }
}

struct NativeTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(0)
                .tabItem {
                    Image("house")
                }

            LibraryView()
                .tag(1)
                .tabItem {
                    Image("list")
                }

            LikedView()
                .tag(2)
                .tabItem {
                    Image("heart")
                }

            SearchView()
                .tag(3)
                .tabItem {
                    Image(systemName: "magnifyingglass")
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
