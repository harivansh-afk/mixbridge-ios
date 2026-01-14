//
//  DJLabView.swift
//  mixbridge
//
//  Dev-only DJ Lab for testing BPM analysis and transitions.
//  Shows prep status, analysis results, and allows auditioning transitions.
//

import SwiftUI
import MixBridgeDJ

struct DJLabView: View {
    @StateObject private var controller = DJAuditionController()
    @ObservedObject private var prepService = DJPrepService.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    private let queueManager = QueueManager.shared

    var body: some View {
        List {
            djSettingsSection
            prepStatusSection
            auditionSection
            cacheStatsSection
        }
        .navigationTitle("DJ Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - DJ Settings Section

    private var djSettingsSection: some View {
        Section("DJ Settings") {
            Toggle("DJ Mode Enabled", isOn: Binding(
                get: { PlayerState.shared.djEnabled },
                set: { PlayerState.shared.djEnabled = $0 }
            ))

            Stepper(
                "Download Ahead: \(PlayerState.shared.djDownloadAheadCount)",
                value: Binding(
                    get: { PlayerState.shared.djDownloadAheadCount },
                    set: { PlayerState.shared.djDownloadAheadCount = $0 }
                ),
                in: 1...5
            )

            Toggle("Auto Download", isOn: Binding(
                get: { PlayerState.shared.djAutoDownloadAhead },
                set: { PlayerState.shared.djAutoDownloadAhead = $0 }
            ))

            Button("Trigger Prep Now") {
                prepService.prepNextTracks()
            }
            .disabled(!PlayerState.shared.djEnabled)
        }
    }

    // MARK: - Prep Status Section

    private var prepStatusSection: some View {
        Section("Queue Prep Status") {
            if queueManager.queue.isEmpty {
                Text("Queue is empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(queueManager.queue.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    prepStatusRow(for: item, index: index)
                }
            }
        }
    }

    private func prepStatusRow(for item: QueueItem, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            prepStatusBadge(for: item.trackId)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await prepService.prepTrack(item.track)
            }
        }
    }

    @ViewBuilder
    private func prepStatusBadge(for trackId: String) -> some View {
        switch prepService.prepStatuses[trackId] {
        case .none, .pending:
            Text("Pending")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("DL")
            }
            .font(.caption)
        case .analyzing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("BPM")
            }
            .font(.caption)
        case .ready(let result):
            Text("\(String(format: "%.0f", result.bpm)) BPM")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let error):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Audition Section

    private var auditionSection: some View {
        Section("Audition") {
            auditionStateRow

            if let trackA = controller.trackA {
                deckRow(label: "Deck A", track: trackA, analysis: controller.analysisA)
            }

            if let trackB = controller.trackB {
                deckRow(label: "Deck B", track: trackB, analysis: controller.analysisB)
            }

            if case .playing = controller.state {
                HStack {
                    Text("Time:")
                    Spacer()
                    Text(formatTime(controller.currentTimeA))
                        .monospacedDigit()
                }
            }

            auditionButtons
        }
    }

    private var auditionStateRow: some View {
        HStack {
            Text("State:")
            Spacer()
            Text(stateDescription(controller.state))
                .foregroundStyle(stateColor(controller.state))
        }
    }

    private func deckRow(label: String, track: Track, analysis: DJAnalysisResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let analysis {
                    Text("\(String(format: "%.1f", analysis.bpm)) BPM")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("(\(String(format: "%.0f%%", analysis.confidence * 100)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(track.title)
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var auditionButtons: some View {
        switch controller.state {
        case .idle:
            loadDeckAButton

        case .loadedDeckA:
            HStack {
                playButton
                loadDeckBButton
            }

        case .loadedBoth:
            HStack {
                playButton
                stopButton
            }

        case .playing:
            HStack {
                transitionButton
                stopButton
            }

        case .transitioning:
            HStack {
                Text("Transitioning...")
                    .foregroundStyle(.orange)
                Spacer()
                stopButton
            }

        case .error:
            stopButton
        }
    }

    private var loadDeckAButton: some View {
        Button("Load Deck A from Queue") {
            loadFirstPreparedTrack(deck: .a)
        }
        .disabled(queueManager.queue.isEmpty)
    }

    private var loadDeckBButton: some View {
        Button("Load Deck B") {
            loadFirstPreparedTrack(deck: .b, skipFirst: true)
        }
    }

    private var playButton: some View {
        Button("Play") {
            controller.play()
        }
    }

    private var stopButton: some View {
        Button("Stop", role: .destructive) {
            controller.stop()
        }
    }

    private var transitionButton: some View {
        Button("Transition") {
            if let plan = controller.createDefaultTransitionPlan() {
                controller.executeTransition(plan: plan)
            }
        }
        .disabled(controller.analysisB == nil)
    }

    // MARK: - Cache Stats Section

    private var cacheStatsSection: some View {
        Section("Cache Stats") {
            AsyncCacheStats()
        }
    }

    // MARK: - Helpers

    private func loadFirstPreparedTrack(deck: DJDeck, skipFirst: Bool = false) {
        let items = queueManager.queue.items
        let startIndex = skipFirst ? 1 : 0

        for item in items.dropFirst(startIndex) {
            if case .ready = prepService.prepStatuses[item.trackId] {
                Task {
                    if let fileURL = await downloadManager.getLocalFileURL(trackId: item.trackId) {
                        switch deck {
                        case .a:
                            await controller.loadDeckA(track: item.track, fileURL: fileURL)
                        case .b:
                            await controller.loadDeckB(track: item.track, fileURL: fileURL)
                        }
                    }
                }
                return
            }
        }
    }

    private func stateDescription(_ state: DJAuditionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .loadedDeckA: return "Deck A Loaded"
        case .loadedBoth: return "Both Decks Loaded"
        case .playing: return "Playing"
        case .transitioning: return "Transitioning"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private func stateColor(_ state: DJAuditionState) -> Color {
        switch state {
        case .idle: return .secondary
        case .loadedDeckA, .loadedBoth: return .blue
        case .playing: return .green
        case .transitioning: return .orange
        case .error: return .red
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, ms)
    }
}

// MARK: - Async Cache Stats View

private struct AsyncCacheStats: View {
    @State private var stats: (hits: Int, misses: Int, puts: Int)?

    var body: some View {
        Group {
            if let stats {
                HStack {
                    Text("Hits: \(stats.hits)")
                    Spacer()
                    Text("Misses: \(stats.misses)")
                    Spacer()
                    Text("Puts: \(stats.puts)")
                }
                .font(.caption)
                .monospacedDigit()
            } else {
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            stats = await DJAnalysisManager.shared.cacheStats()
        }
    }
}

#Preview {
    NavigationStack {
        DJLabView()
    }
}
