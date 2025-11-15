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
    @State private var isDarkMode: Bool = false
    @State private var Notifications: Bool = false

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
                    profileHeader
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Settings
                Section {
                    Toggle(isOn: $Notifications) {
                        Text("Notifications")
                    }
                    .tint(.green)
                    
                    Toggle(isOn: $isDarkMode) {
                        Text("Theme")
                    }
                    .tint(.green)

                }
                
                Section {
                    Button(action: {}) {
                        HStack {
                            Image("sign-out")
                                .renderingMode(.template)
                                .foregroundStyle(.red)
                                .font(.system(size: 14))
                            Text("Logout")
                                .foregroundStyle(.red)
                        }
                    }
                }

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
        }
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
