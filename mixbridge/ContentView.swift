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
        if #available(iOS 26, *) {
            NativeTabView_iOS26(selectedTab: $selectedTab)
                .tabBarMinimizeBehavior(.onScrollDown)
                .modifier(MiniPlayerModifier_iOS26(
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
        } else {
            NativeTabView_Legacy(selectedTab: $selectedTab)
                .modifier(MiniPlayerModifier_Legacy(
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
}

// MARK: - iOS 26 Mini Player Modifier
@available(iOS 26, *)
struct MiniPlayerModifier_iOS26: ViewModifier {
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
            HStack(spacing: 7) {
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
                PlayPauseIcon(isPlaying: playerState.isPlaying)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
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
    }
}

// MARK: - Legacy Mini Player Modifier (iOS 18)
struct MiniPlayerModifier_Legacy: ViewModifier {
    var playerState: PlayerState
    var namespace: Namespace.ID
    @Binding var expandMiniPlayer: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if playerState.hasActiveTrack {
            ZStack(alignment: .bottom) {
                content
                MiniPlayerView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 60) // Above tab bar
            }
            .transition(.opacity)
        } else {
            content
        }
    }

    @ViewBuilder
    func MiniPlayerView() -> some View {
        HStack(spacing: 15){
            HStack(spacing: 7) {
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
                PlayPauseIcon(isPlaying: playerState.isPlaying)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
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
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .buttonStyle(.plain)
    }
}

// MARK: - iOS 26 Tab View
@available(iOS 26, *)
struct NativeTabView_iOS26: View {
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
            Tab(value: 2, role: .search) {
                SearchView()
            } label: {
                Image("magnifying-glass")
            }
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            HapticManager.selection()
        }
    }
}

// MARK: - Legacy Tab View (iOS 18)
struct NativeTabView_Legacy: View {
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image("house")
                }
                .tag(0)

            LibraryView()
                .tabItem {
                    Image("list")
                }
                .tag(1)

            SearchView()
                .tabItem {
                    Image("magnifying-glass")
                }
                .tag(2)
        }
        .tint(.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
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
