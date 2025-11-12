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
            
            .fullScreenCover(isPresented: $expandMiniPlayer){
                ScrollView{
                    
                }
                .safeAreaInset(edge: .top, spacing: 0){
                    VStack(spacing: 10){
                        Capsule()
                            .fill(.primary)
                            .frame(width:35, height: 3)
                        HStack(spacing : 15){
                            PlayerInfo(.init(width: 80, height: 80))
                            
                            Spacer(minLength: 0)
                            
                            //Expanded Actions
                            
                            Group{
                                Button("", systemImage: "star.circle.fill"){
                                    
                                }
                                Button("", systemImage: "ellipsis.circle.fill"){
                                    
                                }
                            }
                            .font(.title)
                            .foregroundStyle(Color.primary, Color.primary.opacity(0.1))
                        }
                        .padding(.horizontal, 15)
                    }
                    .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: animation))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
            
    }
    
    @ViewBuilder
    func PlayerInfo(_ size: CGSize) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: size.height/4)
                .fill(.blue.gradient)
                .frame(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 4){
                Text("Some Music Title")
                    .font(.callout)
                Text("Some Artist Name")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .lineLimit(1)
        }
    }
    
    @ViewBuilder
    func MiniPlayerView() -> some View{
        HStack(spacing: 15){
            PlayerInfo(.init(width: 30, height: 30))
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
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }

            Tab("Library", systemImage: "square.grid.2x2") {
                LibraryView()
            }

            Tab("Liked", systemImage: "heart.fill") {
                LikedView()
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
    }
}

#Preview {
    ContentView()
}
