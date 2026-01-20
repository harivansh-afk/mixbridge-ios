//
//  mixbridgeApp.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI
import Foundation
import Lottie
import MixBridgeDB
import SystemNotification

@main
struct mixbridgeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var queueManager = QueueManager.shared
    @State private var playerState = PlayerState.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @State private var featureFlags = FeatureFlags.shared
    @StateObject private var systemNotification = SystemNotificationContext()

    // Splash state management
    @State private var finishedSplash: Bool = false
    @State private var isAppInitialized: Bool = false

    // Splash is visible until both animation and app initialization are complete
    private var isShowingSplash: Bool {
        !(isAppInitialized && finishedSplash)
    }

    init() {
        Analytics.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Only render main content after app is initialized (feature flags loaded)
                if isAppInitialized {
                    if authManager.isAuthenticated {
                        ContentView()
                    } else {
                        OnboardingView()
                    }
                }

                splashView
            }
            .preferredColorScheme(.dark)
            .environment(authManager)
            .environment(profileManager)
            .environment(queueManager)
            .environment(playerState)
            .environment(deepLinkRouter)
            .environment(featureFlags)
            .environmentObject(DownloadManager.shared)
            .environmentObject(systemNotification)
            .systemNotification(systemNotification)
            .onOpenURL { url in
                if isAppInitialized {
                    deepLinkRouter.handle(url: url)
                } else {
                    Task { @MainActor in
                        while !isAppInitialized {
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        deepLinkRouter.handle(url: url)
                    }
                }
            }
            .sheet(isPresented: Bindable(deepLinkRouter).isShowingSharedContent) {
                sharedContentView
                    .environment(authManager)
                    .environment(queueManager)
                    .environment(playerState)
                    .environment(deepLinkRouter)
                    .environment(featureFlags)
                    .environmentObject(DownloadManager.shared)
                    .environmentObject(systemNotification)
            }
            .onAppear {
                // Initialize app: wait for both minimum splash time AND feature flags
                Task { @MainActor in
                    await withTaskGroup(of: Void.self) { group in
                        // Minimum splash display time
                        group.addTask {
                            try? await Task.sleep(for: .milliseconds(400))
                        }
                        // Feature flags must be ready before showing UI
                        group.addTask {
                            await featureFlags.initialize(userId: authManager.currentUserId)
                        }
                        // Wait for both to complete
                        await group.waitForAll()
                    }
                    isAppInitialized = true
                }

                // Bootstrap local-first queue immediately if already authenticated.
                if authManager.isAuthenticated, let userId = authManager.currentUserId {
                    Task {
                        await queueManager.start(userId: userId)
                    }
                }
            }
            .onChange(of: authManager.isAuthenticated) { wasAuthenticated, isAuthenticated in
                if !isAuthenticated {
                    // User logged out - clear local database
                    Task {
                        try? await MixBridgeDB.shared.deleteAll()
                    }
                } else if let userId = authManager.currentUserId {
                    Task {
                        await queueManager.start(userId: userId)
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { authManager.checkAuthStatus() }
            }
        }
    }

    @ViewBuilder
    private var sharedContentView: some View {
        switch deepLinkRouter.pendingDeepLink {
        case .sharedPlaylist(let shareId):
            SharedPlaylistView(shareId: shareId)
        case .sharedSoundCloudPlaylist(let shareId):
            SharedPlaylistView(shareId: shareId, isSoundCloudPlaylist: true)
        case .sharedTrack(let shareId):
            SharedTrackView(shareId: shareId)
        case .none:
            EmptyView()
        }
    }

    private var splashView: some View {
        SplashView {
            Task { @MainActor in
                // Optional: add slight delay after animation completes
                try? await Task.sleep(for: .milliseconds(200))
                finishedSplash = true
                // Completion triggers splash fade-out via isShowingSplash
            }
        }
        .opacity(isShowingSplash ? 1 : 0)
        .allowsHitTesting(isShowingSplash)
        .animation(.easeInOut(duration: 0.2), value: isShowingSplash)
    }
}

private struct SplashView: View {
    var onFinished: () -> Void
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
                speed: 1.5,
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
