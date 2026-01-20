//
//  FeatureFlags.swift
//  mixbridge
//
//  Manages feature flags using Statsig for remote configuration.
//

import Foundation
import Statsig

@MainActor
@Observable
final class FeatureFlags {
    static let shared = FeatureFlags()
    
    // MARK: - Feature Gates
    
    var downloadsEnabled: Bool {
        Statsig.checkGate("downloads_enabled")
    }

    var spotifyLoginEnabled: Bool {
        Statsig.checkGate("spotify_login_enabled")
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initialize Statsig SDK. Call this early in app lifecycle.
    func initialize(userId: String? = nil) async {
        let user = StatsigUser(userID: userId ?? UUID().uuidString)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Statsig.start(
                sdkKey: "client-W01fpVvvMWAa7TGGwluaWYLjKT0RAhhpOkERHvrrb0C",
                user: user,
                options: StatsigOptions()
            ) { errorMessage in
                if let error = errorMessage {
                    logWarning(.app, "Statsig initialization warning: \(error)")
                } else {
                    logInfo(.app, "Statsig initialized successfully")
                }
                continuation.resume()
            }
        }
    }
    
    /// Update user identity after login
    func updateUser(userId: String) async {
        let user = StatsigUser(userID: userId)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Statsig.updateUser(user) { errorMessage in
                if let error = errorMessage {
                    logWarning(.app, "Statsig user update warning: \(error)")
                }
                continuation.resume()
            }
        }
    }
}
