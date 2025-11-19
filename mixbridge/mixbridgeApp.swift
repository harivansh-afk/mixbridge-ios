//
//  mixbridgeApp.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI
import Foundation
import Lottie

@main
struct mixbridgeApp: App {
    @AppStorage("themeMode") private var themeMode: AppearanceMode = .system
    @State private var authManager = AuthManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var queueManager = QueueManager.shared

    // Splash state management
    @State private var finishedSplash: Bool = false
    @State private var isAppInitialized: Bool = false
    @State private var isSplashActive: Bool = true

    // Splash is visible until both animation and app initialization are complete
    private var isShowingSplash: Bool {
        !(isAppInitialized && finishedSplash)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authManager.isAuthenticated {
                    ContentView()
                } else if !isSplashActive {
                    OnboardingView()
                }

                if isSplashActive {
                    splashView
                }
            }
            .preferredColorScheme(themeMode.colorScheme)
            
            .environment(authManager)
            .environment(profileManager)
            .environment(queueManager)
            .onAppear {
                // Simulate app initialization (adjust timing as needed)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    isAppInitialized = true
                }
            }
        }
    }

    private var splashView: some View {
        SplashView {
            Task { @MainActor in
                // Optional: add slight delay after animation completes
                try? await Task.sleep(for: .milliseconds(250))
                finishedSplash = true
                tryDismissSplashIfReady()
            }
        }
        .opacity(isShowingSplash ? 1 : 0)
        .onChange(of: finishedSplash) {
            tryDismissSplashIfReady()
        }
        .onChange(of: isAppInitialized) {
            tryDismissSplashIfReady()
        }
        .animation(.easeInOut(duration: 0.2), value: isShowingSplash)
    }

    private func tryDismissSplashIfReady() {
        if finishedSplash && isAppInitialized {
            // Smoothly fade out splash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSplashActive = false
            }
        }
    }
}

private struct SplashView: View {
    var onFinished: () -> Void
    @State private var didFinish = false
    private let splashAspectRatio: CGFloat = 900.0 / 1200.0

    var body: some View {
        GeometryReader { proxy in
            content(for: proxy.size)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        // custom padding for position
        let availableWidth = max(size.width - 250, 120)
        let width = min(availableWidth, 320)
        let height = width * splashAspectRatio

        ZStack {
            Color.black.ignoresSafeArea()

            LottieView(
                file: .logo,
                loopMode: .playOnce,
                onComplete: {
                    onFinished()
                }
            )
            .frame(width: width, height: height)
            .compositingGroup()
            .colorInvert()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
