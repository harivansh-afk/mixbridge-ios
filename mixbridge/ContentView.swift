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

    var body: some View {
        NativeTabView()
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MiniPlayerView()
                    .matchedTransitionSource(id: "MINIPLAYER", in: animation)
                    .onTapGesture {
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
        HStack(spacing: 12) {
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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

            VStack(alignment: .leading, spacing: 4){
                Text(track.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    func miniArtworkPlaceholder(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8)
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
                playerState.isPlaying.toggle()
            }   label: {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .contentShape(.rect)
            }
            .padding(.trailing, 10)
            .buttonStyle(.plain)


            Button{

            }   label: {
                Image(systemName: "forward.fill")
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, 15)
        .buttonStyle(.plain)
    }
}

struct NativeTabView: View {
    var body: some View {
        TabView {
            Tab("", image: "house") {
                HomeView()
            }

            Tab("", image: "list") {
                LibraryView()
            }

            Tab("", image: "heart") {
                LikedView()
            }

            Tab("", image: "magnifying-glass", role: .search) {
                SearchView()
            }
        }
        .tint(.primary)
    }
}

#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}
