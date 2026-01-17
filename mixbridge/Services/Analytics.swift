//
//  Analytics.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 1/17/25.
//

import Foundation
import Observation
import PostHog

@MainActor
@Observable
final class Analytics {
    static let shared = Analytics()

    private init() {}

    private let apiKey = "phc_KvGty3yn7NC19s6jGHQ57DsBU2s83fH5VSX41VKi9SE"
    private let host = "https://us.i.posthog.com"

    func configure() {
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.sessionReplay = true
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)
    }

    func track(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func screen(_ name: String) {
        PostHogSDK.shared.screen(name)
    }

    func identify(userId: String, properties: [String: Any]) {
        PostHogSDK.shared.identify(userId, properties: properties)
    }

    func reset() {
        PostHogSDK.shared.reset()
    }
}
