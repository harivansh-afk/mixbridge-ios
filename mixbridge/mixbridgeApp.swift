//
//  mixbridgeApp.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

@main
struct mixbridgeApp: App {
    @AppStorage("themeMode") private var themeMode: AppearanceMode = .system
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(themeMode.colorScheme)
            .environment(authManager)
        }
    }
}
