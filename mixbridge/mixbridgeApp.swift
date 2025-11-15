//
//  mixbridgeApp.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/9/25.
//

import SwiftUI

@main
struct mixbridgeApp: App {
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeMode.colorScheme)
        }
    }
}
