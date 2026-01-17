//
//  EditPlaylistSheet.swift
//  mixbridge
//
//  Full-featured playlist editor with track management.
//  Supports editing name, artwork, and adding/removing tracks.
//

import SwiftUI
import PhotosUI

struct EditPlaylistSheet: View {
    let playlist: Playlist
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var viewModel: EditPlaylistViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showAddTracks = false
    @State private var showRemoveAllWarning = false
    
    init(playlist: Playlist) {
        self.playlist = playlist
        self._viewModel = State(initialValue: EditPlaylistViewModel(playlist: playlist))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            headerSection
                            tracksSection
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Edit Playlist")
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
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button {
                            saveChanges()
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .disabled(!viewModel.hasChanges || !viewModel.canSave)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        if viewModel.selectedCount == viewModel.displayTracks.count {
                            showRemoveAllWarning = true
                        } else {
                            viewModel.removeSelectedTracks()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(viewModel.selectedCount > 0 ? .red : .secondary)
                    }
                    .disabled(viewModel.selectedCount == 0)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Text("\(viewModel.displayTracks.count) tracks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showAddTracks = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                if let userId = authManager.currentUserId {
                    await viewModel.loadPlaylist(userId: userId)
                }
            }
            .sheet(isPresented: $showAddTracks) {
                AddTracksToPlaylistView(viewModel: viewModel)
                    .environment(authManager)
            }
            .alert("Remove All Tracks?", isPresented: $showRemoveAllWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    viewModel.removeSelectedTracks()
                }
            } message: {
                Text("This will remove all tracks from the playlist.")
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            artworkPicker
            
            TextField("Playlist Name", text: $viewModel.playlistName)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.horizontal, 32)
        }
        .padding(.top, 24)
    }
    
    private var artworkPicker: some View {
        let customImage = viewModel.customArtworkImage
        let firstTrackArtwork = viewModel.displayTracks.first?.track.artwork

        return PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))

                if let customImage {
                    Image(uiImage: customImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let existingCustomData = playlist.customArtworkData,
                          let existingImage = UIImage(data: existingCustomData) {
                    Image(uiImage: existingImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let firstTrackArtwork, !firstTrackArtwork.isEmpty {
                    CachedAsyncImagePhase(url: URL(string: firstTrackArtwork)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            placeholderArtwork
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if !playlist.artwork.isEmpty {
                    CachedAsyncImagePhase(url: URL(string: playlist.artwork)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            placeholderArtwork
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    placeholderArtwork
                }
                
                // Camera overlay - always show for tap affordance
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    viewModel.customArtworkImage = uiImage
                }
            }
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Tracks Section
    
    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.displayTracks.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("Add tracks to your playlist")
                )
                .frame(height: 200)
            } else {
                ForEach(viewModel.displayTracks) { item in
                    EditableTrackRow(
                        track: item.track,
                        isSelected: viewModel.isTrackSelected(item.id),
                        onSelect: { viewModel.toggleTrackSelection(item.id) }
                    )
                    
                    if item.id != viewModel.displayTracks.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveChanges() {
        Task {
            if let userId = authManager.currentUserId {
                if await viewModel.saveChanges(userId: userId) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Editable Track Row

private struct EditableTrackRow: View {
    let track: Track
    let isSelected: Bool
    let onSelect: () -> Void
    
    private let coverSize: CGFloat = 44
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .buttonStyle(.plain)
            
            // Artwork - consistent with TrackRow (44x44, cornerRadius 6)
            CachedAsyncImagePhase(url: URL(string: track.artwork)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: coverSize, height: coverSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

#Preview {
    EditPlaylistSheet(playlist: Playlist(
        id: "test",
        name: "Test Playlist",
        creator: "You",
        artwork: "",
        tracks: [],
        lastUpdated: Date(),
        isUserCreated: true
    ))
    .environment(AuthManager.shared)
}
