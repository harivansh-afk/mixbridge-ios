//
//  ProfileView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
        }
    }

    private var content: some View {
        List {
            connectedServicesSection
            settingsSection
        }
    }

    private var connectedServicesSection: some View {
        Section("Connected Services") {
            ServiceRow(
                name: "Apple Music",
                icon: "music.note",
                iconColor: .red,
                status: "Not Connected"
            )

            ServiceRow(
                name: "Spotify",
                icon: "music.note",
                iconColor: .green,
                status: "Not Connected"
            )
        }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink("Preferences") {
                PreferencesView()
            }
            NavigationLink("About") {
                AboutView()
            }
        }
    }
}

// MARK: - Service Row Component
struct ServiceRow: View {
    let name: String
    let icon: String
    let iconColor: Color
    let status: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)

            Text(name)

            Spacer()

            Text(status)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Placeholder Views
struct PreferencesView: View {
    var body: some View {
        Text("Preferences")
            .navigationTitle("Preferences")
    }
}

struct AboutView: View {
    var body: some View {
        Text("About Mixbridge")
            .navigationTitle("About")
    }
}

#Preview("Light Mode") {
    ProfileView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ProfileView()
        .preferredColorScheme(.dark)
}
