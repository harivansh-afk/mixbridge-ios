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
    @AppStorage("themeMode") private var themeMode: AppearanceMode = .system
    @Environment(\.scenePhase) private var scenePhase
    @State private var authManager = AuthManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var queueManager = QueueManager.shared
    @State private var playerState = PlayerState.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var systemNotification = SystemNotificationContext()

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
            .environment(playerState)
            .environment(deepLinkRouter)
            .environmentObject(DownloadManager.shared)
            .environmentObject(systemNotification)
            .systemNotification(systemNotification)
            .onOpenURL { url in
                deepLinkRouter.handle(url: url)
            }
            .sheet(isPresented: Bindable(deepLinkRouter).isShowingSharedContent) {
                sharedContentView
                    .environment(authManager)
                    .environment(queueManager)
                    .environment(playerState)
                    .environment(deepLinkRouter)
                    .environmentObject(DownloadManager.shared)
            }
            .onAppear {
                // No preloading needed - views load from local database
                // Short delay for splash timing only
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
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
