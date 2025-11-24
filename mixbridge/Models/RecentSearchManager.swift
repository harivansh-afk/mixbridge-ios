//
//  RecentSearchManager.swift
//  mixbridge
//
//  Created by Claude on 11/23/25.
//

import SwiftUI

@Observable
@MainActor
final class RecentSearchManager {
    static let shared = RecentSearchManager()

    private(set) var recentSearches: [String] = []

    private let maxSearches = 10
    private let storageKey = "mixbridge.recentSearches"

    private init() {
        loadSearches()
    }

    // MARK: - Public Methods

    func addSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove if already exists (will re-add at top)
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }

        // Insert at beginning
        recentSearches.insert(trimmed, at: 0)

        // Limit to max
        if recentSearches.count > maxSearches {
            recentSearches = Array(recentSearches.prefix(maxSearches))
        }

        saveSearches()
    }

    func removeSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        saveSearches()
    }

    func clearAll() {
        recentSearches.removeAll()
        saveSearches()
    }

    // MARK: - Persistence

    private func loadSearches() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            recentSearches = saved
        }
    }

    private func saveSearches() {
        UserDefaults.standard.set(recentSearches, forKey: storageKey)
    }
}
