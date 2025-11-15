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
    private let currentTrack = Track.sampleTracks.first ?? Track(
        title: "Some Music Title",
        artist: "Unknown Artist",
        album: "Unknown Album"
    )

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
                    track: currentTrack,
                    namespace: animation
                )
            }
    }

    @ViewBuilder
    func PlayerInfo(_ track: Track, size: CGSize) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: size.height/4)
                .fill(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 4){
                Text(track.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
    
    @ViewBuilder
    func MiniPlayerView() -> some View{
        HStack(spacing: 15){
            PlayerInfo(currentTrack, size: .init(width: 30, height: 30))
            Spacer(minLength: 0)
            
            Button{
                
            }   label: {
                Image(systemName: "play.fill")
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
