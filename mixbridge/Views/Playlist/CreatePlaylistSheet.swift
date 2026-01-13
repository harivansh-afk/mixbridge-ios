//
//  CreatePlaylistSheet.swift
//  mixbridge
//
//  Apple Music-style two-step playlist creation flow.
//  Step 1: Enter name
//  Step 2: Select tracks (required - no empty playlists)
//

import SwiftUI

struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var viewModel = CreatePlaylistViewModel()
    
    var onCreated: ((String) -> Void)?
    
    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .nameEntry:
                nameEntryView
            case .trackSelection:
                PlaylistTrackPickerView(viewModel: viewModel)
                    .environment(authManager)
            }
        }
        .onChange(of: viewModel.isCreating) { _, isCreating in
            if !isCreating && viewModel.error == nil && viewModel.selectedTracks.isEmpty == false {
                // Playlist was created successfully
            }
        }
    }
    
    // MARK: - Name Entry View
    
    private var nameEntryView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Artwork Preview
                    artworkPreview
                    
                    // Name Field
                    TextField("Playlist Title", text: $viewModel.playlistName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal)

                    Spacer(minLength: 100)
                }
                .padding(.top, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.proceedToTrackSelection()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(viewModel.canProceedToTrackSelection ? Color.accentColor : .secondary)
                    }
                    .disabled(!viewModel.canProceedToTrackSelection)
                }
            }
        }
    }
    
    // MARK: - Artwork Preview
    
    private var artworkPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
            
            if viewModel.selectedTracks.isEmpty {
                // Placeholder when no tracks selected
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)
                }
            } else if let firstArtwork = viewModel.selectedTracks.first?.track.artwork,
                      !firstArtwork.isEmpty {
                // Show first track's artwork
                CachedAsyncImagePhase(url: URL(string: firstArtwork)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholderArtwork
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    CreatePlaylistSheet()
        .environment(AuthManager.shared)
}
