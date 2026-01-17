//
//  AccountBottomSheet.swift
//  mixbridge
//
//  Created for displaying account settings in a bottom sheet
//

import SwiftUI

struct AccountBottomSheet: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @State private var showDeleteConfirmation = false
    private var profileManager = UserProfileManager.shared
    @State private var showFinalDeleteConfirmation = false
    @State private var isDeleting = false
    @Binding var selectedDetent: PresentationDetent
    @State private var showProfileStats = false

    let userName: String
    let userEmail: String?
    let profileImage: String?

    // MARK: - Initialization
    init(
        isPresented: Binding<Bool>,
        selectedDetent: Binding<PresentationDetent>,
        userName: String = "User",
        userEmail: String? = nil,
        profileImage: String? = nil
    ) {
        self._isPresented = isPresented
        self._selectedDetent = selectedDetent
        self.userName = userName
        self.userEmail = userEmail
        self.profileImage = profileImage
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    if let profile = profileManager.profile {
                        Button {
                            showProfileStats = true
                        } label: {
                            convexProfileHeader(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    } else if profileManager.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                        .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    } else {
                        Button {
                            showProfileStats = true
                        } label: {
                            profileHeader
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                // Settings Section
                Section {
                    NavigationLink {
                        AutomixSettingsView()
                            .onAppear {
                                withAnimation {
                                    selectedDetent = .large
                                }
                            }
                    } label: {
                        HStack {
                            Image("wave-sine")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .shadow(color: .primary.opacity(0.5), radius: 6)
                                .shadow(color: .primary.opacity(0.2), radius: 12)
                            Text("Automix")
                                .font(.system(size: 18))
                            Spacer()
                        }
                    }
                }
                Section {
                // Logout Section
                    Button(action: {
                        authManager.logout()
                        isPresented = false
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18))
                                .frame(width: 25)
                                .foregroundStyle(.red)
                            Text("Logout")
                                .font(.system(size: 18))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }

                // Delete Account Section
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.system(size: 18))
                                .frame(width: 25)
                                .foregroundStyle(.red)
                            Text("Delete Account")
                                .font(.system(size: 18))
                                .foregroundStyle(.red)
                            Spacer()
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isDeleting)
                }
                
                // Dev Logs Section (Debug + TestFlight only, hidden in App Store)
                if BuildEnvironment.isDevMode {
                    Section {
                        NavigationLink {
                            DevLogsView()
                        } label: {
                            HStack {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                Text("Dev Logs")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("\(LogManager.shared.logs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            }
            .listStyle(InsetGroupedListStyle())
            .listSectionSpacing(23)
            .contentMargins(.top, 5, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showProfileStats) {
                ProfileStatsView(profile: profileManager.profile)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                // Only fetch if not already cached
                if profileManager.profile == nil, let userId = authManager.currentUserId {
                    await profileManager.loadProfile(userId: userId)
                }
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    showFinalDeleteConfirmation = true
                }
            }
            .alert("Are you sure?", isPresented: $showFinalDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Forever", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
            } message: {
                Text("This will permanently delete all your data including playlists, play history, and preferences. This action cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Convex Profile Header

    private func convexProfileHeader(profile: SoundCloudProfile) -> some View {
        HStack(spacing: 16) {
            // Avatar from Convex/SoundCloud
            if let avatarUrl = profile.avatar_url,
               let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                ProfileCircleView(
                    profileImage: nil,
                    userName: profile.username,
                    size: 50
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.full_name ?? profile.username)
                    .font(.title3)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text("Connected to SoundCloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func deleteAccount() async {
        guard let userId = authManager.currentUserId else {
            return
        }

        isDeleting = true

        do {
            try await BackgroundExecutor.run {
                try await ConvexService.shared.deleteAllUserData(userId: userId)
            }
        } catch {
            // Continue with logout even if deletion fails
        }

        // Always logout and dismiss after attempting deletion
        isDeleting = false
        authManager.logout()
        isPresented = false
    }

    // MARK: - Private Views
    private var profileHeader: some View {
        HStack(spacing: 16) {
            ProfileCircleView(
                profileImage: nil,
                userName: userName,
                size: 50
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.title3)
                    .foregroundColor(.primary)

                Text("View Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding()
    }

    private func accountRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)

            }
        }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    struct PreviewWrapper: View {
        @State private var showSheet = true
        @State private var selectedDetent: PresentationDetent = .medium

        var body: some View {
            Color.gray
                .ignoresSafeArea()
                .sheet(isPresented: $showSheet) {
                    AccountBottomSheet(
                        isPresented: $showSheet,
                        selectedDetent: $selectedDetent,
                        userName: "Harivansh Rathi",
                        userEmail: "hari@gmail.com"
                    )
                    .presentationDetents([.medium, .large], selection: $selectedDetent)
                }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    struct PreviewWrapper: View {
        @State private var showSheet = true
        @State private var selectedDetent: PresentationDetent = .medium

        var body: some View {
            Color.gray
                .ignoresSafeArea()
                .sheet(isPresented: $showSheet) {
                    AccountBottomSheet(
                        isPresented: $showSheet,
                        selectedDetent: $selectedDetent,
                        userName: "Harivansh Rathi",
                        userEmail: "hari@gmail.com"
                    )
                    .presentationDetents([.medium, .large], selection: $selectedDetent)
                }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
