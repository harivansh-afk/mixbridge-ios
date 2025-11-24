import SwiftUI

struct ArtistDetailView: View {
    let artist: ArtistInfo
    @Environment(\.dismiss) private var dismiss

    private let avatarSize: CGFloat = 180

    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    avatarView
                        .padding(.top, 20)

                    artistInfo

                    actionButtons
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }

            tracksSection
        }
        .listStyle(.plain)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let avatarUrl = artist.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        avatarPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    case .failure:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple, .purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "music.mic")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: avatarSize, height: avatarSize)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private var artistInfo: some View {
        VStack(spacing: 8) {
            Text(artist.name)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("\(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        PlaylistActionButtons(
            onPlay: {
                // Play all tracks
                if let firstTrack = artist.tracks.first {
                    PlayerState.shared.play(
                        track: firstTrack,
                        trackData: artist.tracksData[firstTrack.id]
                    )
                }
            },
            onShuffle: {
                // Shuffle play
                if let randomTrack = artist.tracks.randomElement() {
                    PlayerState.shared.play(
                        track: randomTrack,
                        trackData: artist.tracksData[randomTrack.id]
                    )
                }
            }
        )
    }

    private var tracksSection: some View {
        Section {
            if artist.tracks.isEmpty {
                Text("No tracks from this artist")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(Array(artist.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track,
                        number: index + 1,
                        showCover: true,
                        trackData: artist.tracksData[track.id]
                    )
                }
            }
        }
        .listSectionSeparator(.visible, edges: .top)
    }
}

#Preview("Light Mode") {
    NavigationStack {
        ArtistDetailView(artist: ArtistInfo(
            id: "1",
            name: "Sample Artist",
            avatarUrl: nil,
            trackCount: 5
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    NavigationStack {
        ArtistDetailView(artist: ArtistInfo(
            id: "1",
            name: "Sample Artist",
            avatarUrl: nil,
            trackCount: 5
        ))
    }
    .preferredColorScheme(.dark)
}
