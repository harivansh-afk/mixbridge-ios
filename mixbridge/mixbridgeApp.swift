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
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authManager.isAuthenticated {
                    ContentView()
                } else if !showSplash {
                    OnboardingView()
                }
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                }
                
            }
            .preferredColorScheme(themeMode.colorScheme)
            .environment(authManager)
            .environment(profileManager)
            .environment(queueManager)
            .onChange(of: authManager.isAuthenticated){
                showSplash = true
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
        let availableWidth = max(size.width - 48, 120)
        let width = min(availableWidth, 420)
        let height = width * splashAspectRatio

        ZStack {
            Color.black.ignoresSafeArea()

            LottieView(
                animationName: "splash",
                loopMode: .playOnce,
                contentMode: .scaleAspectFit,
                onCompletion: finishIfNeeded
            )
            .frame(width: width, height: height)
            .compositingGroup()
            .colorInvert()
            .offset(x: 54)
            .offset(y: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finishIfNeeded() {
        if Thread.isMainThread {
            completeIfNeeded()
        } else {
            DispatchQueue.main.async {
                completeIfNeeded()
            }
        }
    }

    private func completeIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}
