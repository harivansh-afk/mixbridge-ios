//
//  HomeViewModel.swift
//  mixbridge
//
//  ViewModel for HomeView with GRDB ValueObservation.
//  Observes play history from local database.
//

import Foundation
import MixBridgeDB

@Observable
@MainActor
final class HomeViewModel {
    // MARK: - Observable State

    private(set) var playHistory: [TrackItem] = []
    private(set) var playHistoryRows: [IndexedRow<TrackItem>] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    // MARK: - Dependencies

    private let db = MixBridgeDB.shared
    private let historySync = HistorySync.shared

    // MARK: - Initialization

    init() {}

    // MARK: - Database Observation

    /// Start observing play history from local database
    /// Call this from view's .task modifier
    func observeDatabase() async {
        let observation = ValueObservation.tracking { db in
            try PlayHistory
                .including(required: PlayHistory.track)
                .order(PlayHistory.Columns.updatedAt.desc)
                .limit(100)
                .asRequest(of: PlayHistoryWithTrack.self)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await historyRecords in observation {
                // Convert to TrackItems for UI
                let items = historyRecords.compactMap { record -> TrackItem? in
                    guard let scTrack = record.track.soundCloudTrack else { return nil }
                    return TrackItem(
                        soundCloudTrack: scTrack,
                        playCount: record.playHistory.playCount,
                        lastPlayedPosition: record.playHistory.lastPlayedPosition,
                        listenedPercentage: record.playHistory.listenedPercentage
                    )
                }

                if self.playHistory != items {
                    self.playHistory = items
                }
                let nextRows = items.indexedRows()
                if self.playHistoryRows != nextRows {
                    self.playHistoryRows = nextRows
                }
                self.error = nil
            }
        } catch is CancellationError {
            // Expected when the view disappears; don't surface as an error state.
        } catch {
            logError(.db, "Failed to observe history: \(error)")
            self.error = error
        }
    }

    // MARK: - Refresh from Network

    /// Refresh play history from Convex backend
    /// Call this on pull-to-refresh or first appear
    func refresh(userId: String) async {
        // Only show loading if truly empty (first install)
        isLoading = playHistory.isEmpty

        do {
            try await historySync.syncHistory(userId: userId)
            error = nil
        } catch {
            logError(.sync, "Failed to sync history: \(error)")
            self.error = error
        }

        isLoading = false
    }
}
