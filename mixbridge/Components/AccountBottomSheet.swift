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
    @AppStorage("themeMode") private var themeMode: AppearanceMode = .system
    @State private var Notifications: Bool = false
    @State private var Personalization: Bool = true
    @State private var convexProfile: ConvexUserProfile?
    @State private var isLoadingProfile = false

    let userName: String
    let userEmail: String?
    let profileImage: String?

    // MARK: - Initialization
    init(
        isPresented: Binding<Bool>,
        userName: String = "User",
        userEmail: String? = nil,
        profileImage: String? = nil
    ) {
        self._isPresented = isPresented
        self.userName = userName
        self.userEmail = userEmail
        self.profileImage = profileImage
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            List {
                // Profile Section
                Section {
                    if isLoadingProfile {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    } else if let profile = convexProfile {
                        ZStack {
                            NavigationLink(destination: ProfileStatsView(profile: profile.profile)) {
                                EmptyView()
                            }
                            .opacity(0)

                            convexProfileHeader(profile: profile.profile)
                        }
                    } else {
                        ZStack {
                            NavigationLink(destination: ProfileStatsView(profile: nil)) {
                                EmptyView()
                            }
                            .opacity(0)

                            profileHeader
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Theme Picker Section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Appearance", selection: $themeMode) {
                            ForEach(AppearanceMode.allCases.filter { $0 != .system }) { mode in
                                Text(mode.rawValue)
                                    .font(.system(size: 16))
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .glassEffect(.regular)
                }

                // Settings Section
                Section {
                    Toggle(isOn: $Personalization) {
                        HStack(spacing: 8) {
                            Text("Personalization")
                                .font(.system(size: 18))
                        }
                    }
                    .tint(.blue)

                    Toggle(isOn: $Notifications) {
                        HStack(spacing: 8) {
                            Text("Notifications")
                                .font(.system(size: 18))
                        }
                    }
                    .tint(.blue)
                }

                // Logout Section
                Section {
                    Button(action: {
                        authManager.logout()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18))
                                .foregroundStyle(.red)
                            Text("Logout")
                                .font(.system(size: 18))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }

            }
            .listStyle(InsetGroupedListStyle())
            .listSectionSpacing(20)
            .contentMargins(.top, 5, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
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
                await loadProfile()
            }
        }
        .preferredColorScheme(themeMode.colorScheme)
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
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    // MARK: - Data Loading

    private func loadProfile() async {
        guard let userId = authManager.currentUserId else {
            return
        }

        isLoadingProfile = true

        do {
            let profile = try await BackgroundExecutor.run {
                try await ConvexService.shared.getUserProfile(userId: userId)
            }

            if let profile = profile {
                self.convexProfile = profile
            }
        } catch {
            // Silently handle errors
        }

        isLoadingProfile = false
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
        .background(Color(UIColor.secondarySystemGroupedBackground))
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

        var body: some View {
            Color.gray
                .ignoresSafeArea()
                .sheet(isPresented: $showSheet) {
                    AccountBottomSheet(
                        isPresented: $showSheet,
                        userName: "Harivansh Rathi",
                        userEmail: "hari@phia.com"
                    )
                }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    struct PreviewWrapper: View {
        @State private var showSheet = true

        var body: some View {
            Color.gray
                .ignoresSafeArea()
                .sheet(isPresented: $showSheet) {
                    AccountBottomSheet(
                        isPresented: $showSheet,
                        userName: "Harivansh Rathi",
                        userEmail: "hari@phia.com"
                    )
                }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
