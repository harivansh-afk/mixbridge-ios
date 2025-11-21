//
//  PlaybackCoordinator.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/17/25.
//

import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
protocol PlaybackCoordinatorDelegate: AnyObject {
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didUpdate snapshot: PlaybackSnapshot)
    func playbackCoordinator(_ coordinator: PlaybackCoordinator, didEncounter error: Error)
}

struct PlaybackSnapshot {
    let track: Track?
    let queueIndex: Int?
    let status: PlayerState.PlaybackStatus
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
}

private struct PlaybackContext: Equatable {
    let track: Track
    let trackData: [String: Any]?
    let queueIndex: Int?

    static func == (lhs: PlaybackContext, rhs: PlaybackContext) -> Bool {
        lhs.track.id == rhs.track.id && lhs.queueIndex == rhs.queueIndex
    }
}

@MainActor
final class PlaybackCoordinator: NSObject {
    static let shared = PlaybackCoordinator()

    weak var delegate: PlaybackCoordinatorDelegate?

    var autoplayEnabled: Bool = true

    private let queueManager = QueueManager.shared
    private let backendAPI = BackendAPI.shared
    private let keychain = KeychainManager.shared

    private let player = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var currentContext: PlaybackContext?
    private var nextPreloadedContext: PlaybackContext?
    private var nextPreloadedItem: AVPlayerItem?
    private var itemContextMap: [AVPlayerItem: PlaybackContext] = [:]

    /// Tracks whether the next track has been preloaded for the current track
    private var hasPreloadedForCurrentTrack = false

    /// Progress threshold (0.0 - 1.0) at which to trigger preloading of the next track
    private let preloadTriggerProgress: Double = 0.75

    private var status: PlayerState.PlaybackStatus = .idle {
        didSet {
            Task { @MainActor in
                publishSnapshot()
            }
        }
    }

    private override init() {
        super.init()
        player.actionAtItemEnd = .advance
        addTimeObserver()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    // MARK: - Public Controls

    func play(track: Track, trackData: [String: Any]?, queueIndex: Int?) {
        let context = PlaybackContext(track: track, trackData: trackData, queueIndex: queueIndex)
        Task {
            await startPlayback(with: context)
        }
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        player.pause()
        status = .paused
        Task { @MainActor in
            publishSnapshot()
        }
    }

    func resume() {
        guard player.items().isEmpty == false else { return }
        player.play()
        status = .playing
        Task { @MainActor in
            publishSnapshot()
        }
    }

    func seek(to time: Double) {
        let target = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.publishSnapshot()
            }
        }
    }

    func setVolume(_ value: Double) {
        player.volume = Float(value)
    }

    func playNext(manual: Bool = false) {
        guard let currentContext else {
            if let first = queueManager.queueTracks.first {
                play(track: first, trackData: queueManager.trackData(for: first.id), queueIndex: 0)
            }
            return
        }

        if player.items().count > 1 {
            player.advanceToNextItem()
            adoptCurrentItemContext()
        } else if let next = queueManager.nextTrack(after: currentContext.queueIndex ?? queueManager.indexOfTrack(withId: currentContext.track.id) ?? -1) {
            play(track: next.track, trackData: queueManager.trackData(for: next.track.id), queueIndex: next.index)
        }

        if manual {
            HapticManager.selection()
        }
    }

    func playPrevious() {
        guard let currentContext else {
            playNext(manual: true)
            return
        }

        if let previous = queueManager.previousTrack(before: currentContext.queueIndex ?? queueManager.indexOfTrack(withId: currentContext.track.id) ?? 0) {
            play(track: previous.track, trackData: queueManager.trackData(for: previous.track.id), queueIndex: previous.index)
        } else {
            seek(to: 0)
        }
    }

    // MARK: - Playback Pipeline

    private func startPlayback(with context: PlaybackContext) async {
        status = .loading

        do {
            let playerItem = try await prepareItem(for: context)

            player.removeAllItems()
            itemContextMap.removeAll()
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            hasPreloadedForCurrentTrack = false // Reset preload flag for new track

            player.insert(playerItem, after: nil)
            itemContextMap[playerItem] = context
            currentContext = context
            player.play()
            status = .playing
            Task { @MainActor in
                publishSnapshot()
            }

            // Preloading now happens at 75% progress (see addTimeObserver)
            // This optimizes bandwidth usage and reduces unnecessary preloads for skipped tracks
        } catch {
            delegate?.playbackCoordinator(self, didEncounter: error)
            status = .failed(error.localizedDescription)
        }
    }

    private func prepareItem(for context: PlaybackContext) async throws -> AVPlayerItem {
        let stream = try await backendAPI.getStreamURL(trackId: context.track.id)

        guard let url = URL(string: stream.stream_url) else {
            throw PlayerState.PlaybackError.invalidStreamURL
        }

        var options: [String: Any] = [:]
        if let token = keychain.getAccessToken() {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": "Bearer \(token)"]
        }

        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        return item
    }

    private func preloadNextItem(from context: PlaybackContext) async {
        guard let next = nextContext(after: context) else {
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            return
        }

        do {
            if let existingItem = nextPreloadedItem {
                player.remove(existingItem)
                itemContextMap.removeValue(forKey: existingItem)
            }

            let item = try await prepareItem(for: next)
            nextPreloadedContext = next
            nextPreloadedItem = item
            player.insert(item, after: player.items().last)
            itemContextMap[item] = next
        } catch {
            // Preload failures shouldn't break current playback
        }
    }

    private func nextContext(after context: PlaybackContext) -> PlaybackContext? {
        let index = context.queueIndex ?? queueManager.indexOfTrack(withId: context.track.id)
        guard let index else { return nil }

        guard let next = queueManager.nextTrack(after: index) else { return nil }

        return PlaybackContext(
            track: next.track,
            trackData: queueManager.trackData(for: next.track.id),
            queueIndex: next.index
        )
    }

    // MARK: - Observers

    private func addTimeObserver() {
        guard timeObserverToken == nil else { return }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                // Calculate playback progress
                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                let duration = CMTimeGetSeconds(self.player.currentItem?.duration ?? .invalid)

                // Trigger progress-based preloading
                if !self.hasPreloadedForCurrentTrack,
                   currentTime.isFinite,
                   duration.isFinite,
                   duration > 0 {
                    let progress = currentTime / duration

                    // Preload next track when reaching 75% progress
                    if progress >= self.preloadTriggerProgress,
                       let current = self.currentContext {
                        self.hasPreloadedForCurrentTrack = true
                        await self.preloadNextItem(from: current)
                    }
                }

                // Publish snapshot for UI updates
                Task { @MainActor in
                    self.publishSnapshot()
                }
            }
        }
    }

    @objc private func handleItemDidFinish(_ notification: Notification) {
        guard
            let finishedItem = notification.object as? AVPlayerItem,
            let finishedContext = itemContextMap[finishedItem]
        else { return }

        itemContextMap.removeValue(forKey: finishedItem)

        if autoplayEnabled,
           let preloadedContext = nextPreloadedContext,
           preloadedContext == nextContext(after: finishedContext) {
            currentContext = preloadedContext
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            Task { @MainActor in
                publishSnapshot()
            }
            Task { [weak self] in
                guard let self, let current = self.currentContext else { return }
                await self.preloadNextItem(from: current)
            }
            return
        }

        adoptCurrentItemContext()
    }

    private func adoptCurrentItemContext() {
        if let currentItem = player.currentItem,
           let context = itemContextMap[currentItem] {
            currentContext = context
            hasPreloadedForCurrentTrack = false // Reset flag for new track
            nextPreloadedContext = nil
            nextPreloadedItem = nil
            Task { @MainActor in
                publishSnapshot()
            }
            // Preloading will happen at 75% progress (see addTimeObserver)
        } else {
            currentContext = nil
            status = .ready
            Task { @MainActor in
                publishSnapshot()
            }
        }
    }

    private func publishSnapshot() {
        let currentTime = CMTimeGetSeconds(player.currentTime()).isFinite ? CMTimeGetSeconds(player.currentTime()) : 0
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)

        let effectiveStatus: PlayerState.PlaybackStatus = {
            if case .failed = status {
                return status
            }

            switch player.timeControlStatus {
            case .waitingToPlayAtSpecifiedRate:
                return .loading
            case .playing:
                return .playing
            case .paused:
                return .paused
            @unknown default:
                return status
            }
        }()

        let snapshot = PlaybackSnapshot(
            track: currentContext?.track,
            queueIndex: currentContext?.queueIndex,
            status: effectiveStatus,
            isPlaying: player.timeControlStatus == .playing,
            currentTime: currentTime,
            duration: duration.isFinite ? duration : (currentContext?.track.duration ?? 0)
        )

        delegate?.playbackCoordinator(self, didUpdate: snapshot)
    }
}
