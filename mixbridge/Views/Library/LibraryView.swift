//
//  LibraryView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct LibraryView: View {
    @State private var showingAccount = false

    private let userName = "Harivansh Rathi"
    private let userEmail = "harivansh@example.com"
    private let profileImage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    playlistGridSection
                    navigationSection
                    recentlyAddedGridSection
                }
                .padding(.top)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileCircleView(
                        profileImage: "pfp",
                        userName: userName,
                        size: 32
                    )
                    .onTapGesture {
                        showingAccount.toggle()
                    }
                }
            }
            .sheet(isPresented: $showingAccount) {
                AccountBottomSheet(
                    isPresented: $showingAccount,
                    userName: userName,
                    userEmail: userEmail,
                    profileImage: profileImage
                )
            }
        }
    }

    private var playlistGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 20
            ) {
                ForEach(Playlist.samplePlaylists.prefix(6)) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    AsyncImage(url: URL(string: playlist.artwork)) { phase in
                                        switch phase {
                                        case .empty:
                                            artworkPlaceholder
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        case .failure:
                                            artworkPlaceholder
                                        @unknown default:
                                            artworkPlaceholder
                                        }
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }

                            // Name only
                            Text(playlist.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ProgressView()
                .progressViewStyle(.circular)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var navigationSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                Text("All Playlists")
            } label: {
                LibraryNavigationRow(
                    icon: "music.note.list",
                    title: "Playlists",
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                Text("Artists")
            } label: {
                LibraryNavigationRow(
                    icon: "music.mic",
                    title: "Artists",
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)

            NavigationLink {
                Text("Songs")
            } label: {
                LibraryNavigationRow(
                    icon: "music.note",
                    title: "Songs",
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 60)
        }
    }

    private var recentlyAddedGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recently Added")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 20
            ) {
                ForEach(Playlist.samplePlaylists.prefix(4)) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        VStack(alignment: .center, spacing: 6) {
                            // Artwork
                            Group {
                                if playlist.artwork.starts(with: "http") {
                                    AsyncImage(url: URL(string: playlist.artwork)) { phase in
                                        switch phase {
                                        case .empty:
                                            artworkPlaceholder
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        case .failure:
                                            artworkPlaceholder
                                        @unknown default:
                                            artworkPlaceholder
                                        }
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }

                            // Name only
                            Text(playlist.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview("Light Mode") {
    LibraryView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    LibraryView()
        .preferredColorScheme(.dark)
}
