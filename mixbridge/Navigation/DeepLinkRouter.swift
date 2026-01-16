//
//  DeepLinkRouter.swift
//  mixbridge
//
//  Handles Universal Links and deep linking for playlist sharing
//

import SwiftUI
import Foundation

@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingDeepLink: DeepLink?
    var isShowingSharedPlaylist: Bool = false

    enum DeepLink: Equatable {
        case sharedPlaylist(shareId: String)
    }

    private init() {}

    /// Handle incoming URL from Universal Links or custom scheme
    func handle(url: URL) {
        // Parse URL components
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            logWarning(.app, "Failed to parse deep link URL: \(url)")
            return
        }

        // Handle Universal Links (mixbridge.app)
        if let host = components.host, host == "mixbridge.app" {
            handleUniversalLink(components: components)
            return
        }

        // Handle custom scheme (mixbridge://)
        if url.scheme == "mixbridge" {
            handleCustomScheme(url: url)
            return
        }

        logWarning(.app, "Unhandled deep link: \(url)")
    }

    private func handleUniversalLink(components: URLComponents) {
        let pathComponents = components.path.split(separator: "/").map(String.init)

        // Handle /p/{shareId} - shared playlist
        if pathComponents.count >= 2, pathComponents[0] == "p" {
            let shareId = pathComponents[1]
            logInfo(.app, "Deep link: shared playlist \(shareId)")
            pendingDeepLink = .sharedPlaylist(shareId: shareId)
            isShowingSharedPlaylist = true
            return
        }

        logWarning(.app, "Unhandled Universal Link path: \(components.path)")
    }

    private func handleCustomScheme(url: URL) {
        // Currently only used for OAuth callbacks
        // Auth callbacks are handled by AuthManager
        logInfo(.app, "Custom scheme URL: \(url)")
    }

    /// Clear pending deep link after handling
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }

    /// Dismiss shared playlist sheet
    func dismissSharedPlaylist() {
        isShowingSharedPlaylist = false
        pendingDeepLink = nil
    }
}
