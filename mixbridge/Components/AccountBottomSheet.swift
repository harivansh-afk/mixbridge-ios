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
                        convexProfileHeader(profile: profile.profile)
                    } else {
                        profileHeader
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Settings
                Section {
                    Toggle(isOn: $Personalization) {
                        HStack(spacing: 8) {
                            Image("brain")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Personalization")
                        }
                    }
                    .tint(.blue)
                    Toggle(isOn: $Notifications) {
                        HStack(spacing: 8) {
                            Image("bell")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Notifications")
                        }
                    }
                    .tint(.blue)
                }
                .listRowSeparator(.hidden)

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Appearance", selection: $themeMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                }
                .listRowSeparator(.hidden)
                
                Section {
                    Button(action: {
                        authManager.logout()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                            Text("Logout")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listRowSeparator(.hidden)

            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Account")
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
    }

    // MARK: - Convex Profile Header

    private func convexProfileHeader(profile: SoundCloudProfile) -> some View {
        HStack(spacing: 16) {
            // Avatar from Convex/SoundCloud
            if let avatarUrl = profile.avatar_url,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                        }
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

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Connected to SoundCloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            print("❌ [AccountBottomSheet] No userId available")
            return
        }

        isLoadingProfile = true

        do {
            print("📡 [AccountBottomSheet] Fetching profile from Convex for userId: \(userId)")
            let profile = try await ConvexService.shared.getUserProfile(userId: userId)

            if let profile = profile {
                self.convexProfile = profile
                print("✅ [AccountBottomSheet] Profile loaded from Convex!")
                print("   Username: \(profile.profile.username)")
                print("   Full name: \(profile.profile.full_name ?? "N/A")")
                print("   Followers: \(profile.profile.followers_count ?? 0)")
                print("   Playlists: \(profile.profile.playlist_count ?? 0)")
                print("   Avatar: \(profile.profile.avatar_url ?? "N/A")")
            } else {
                print("⚠️ [AccountBottomSheet] No profile found in Convex cache")
            }
        } catch {
            print("❌ [AccountBottomSheet] Failed to fetch profile: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }

        isLoadingProfile = false
    }

    // MARK: - Private Views
    private var profileHeader: some View {
        HStack(spacing: 16) {
            ProfileCircleView(
                profileImage: "pfp",
                userName: userName,
                size: 50
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(userName)
                    .font(.title3)

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
