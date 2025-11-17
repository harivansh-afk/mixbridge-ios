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
    @State private var profileManager = UserProfileManager.shared
    @State private var queueManager = QueueManager.shared
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authManager.isAuthenticated {
                    ContentView()
                } else if !showSplash{
                    OnboardingView()
                }
                if showSplash{
                    ZStack{
                        Color.black.ignoresSafeArea()
                        Text("Welcome")
                    }
                }
                
            }
            .animation(.easeOut, value: showSplash)
            .preferredColorScheme(themeMode.colorScheme)
            .environment(authManager)
            .environment(profileManager)
            .environment(queueManager)
            .onChange(of: authManager.isAuthenticated){
                showSplash = true
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    self.showSplash = false
                }
            }
        }
    }
}
