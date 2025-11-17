//
//  PlayerState.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/15/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer

@Observable
@MainActor
final class PlayerState: NSObject {
    static let shared = PlayerState()

    enum PlaybackStatus: Equatable {
        case idle
        case loading
        case ready
        case playing
        case paused
        case failed(String)
    }

    enum PlaybackError: LocalizedError {
        case invalidStreamURL

        var errorDescription: String? {
            switch self {
            case .invalidStreamURL:
                return "Invalid stream URL"
            }
        }
    }

    var currentTrack: Track
    var isPlaying: Bool = false
    var playbackPosition: Double = 0
    var duration: Double = 0
    var playbackStatus: PlaybackStatus = .idle
    var autoplayEnabled = true
    var volume: Double = 0.7 {
        didSet {
            player?.volume = Float(volume)
        }
    }
    var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var currentQueueIndex: Int = -1
    private var currentTrackData: [String: Any]?

    private let backendAPI = BackendAPI.shared
    private let queueManager = QueueManager.shared
    private let keychain = KeychainManager.shared
    private let audioSession = AVAudioSession.sharedInstance()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private override init() {
        currentTrack = Track.sampleTracks.first ?? Track(
            title: "Some Music Title",
            artist: "Unknown Artist",
            album: "Unknown Album"
        )
        super.init()
        configureAudioSession()
        setupNotifications()
        setupRemoteCommands()
    }

    // MARK: - Public API

    func play(track: Track, trackData: [String: Any]? = nil, queueIndex: Int? = nil, startTime: Double = 0) async {
        playbackStatus = .loading
        let metadata = trackData ?? queueManager.trackData(for: track.id)
        currentTrackData = metadata

        do {
            let stream = try await backendAPI.getStreamURL(trackId: track.id)
            guard let streamURL = URL(string: stream.stream_url) else {
                throw PlaybackError.invalidStreamURL
            }

            try activateAudioSession()
            preparePlayer(with: streamURL, startTime: startTime)

            currentTrack = track
            currentQueueIndex = queueIndex ?? queueManager.indexOfTrack(withId: track.id) ?? -1

            player?.play()
            player?.volume = Float(volume)

            isPlaying = true
            playbackStatus = .playing
            errorMessage = nil
            updateNowPlayingInfo()
        } catch {
            handlePlaybackFailure(error)
        }
    }

    func playFromQueue(index: Int) {
        guard queueManager.queueTracks.indices.contains(index) else { return }
        let track = queueManager.queueTracks[index]
        Task {
            await play(track: track, trackData: queueManager.trackData(for: track.id), queueIndex: index)
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        playbackStatus = .paused
        updateNowPlayingInfo(playbackRate: 0)
    }

    func resume() {
        guard player != nil else { return }
        try? activateAudioSession()
        player?.play()
        isPlaying = true
        playbackStatus = .playing
        updateNowPlayingInfo(playbackRate: 1)
    }

    func seek(to time: Double) {
        guard let player else { return }
        let target = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playbackPosition = time
                self.updateNowPlayingInfo()
            }
        }
    }

    func playNextFromQueue() {
        guard currentQueueIndex >= 0,
              let next = queueManager.nextTrack(after: currentQueueIndex) else {
            return
        }

        Task {
            await play(track: next.track, trackData: queueManager.trackData(for: next.track.id), queueIndex: next.index)
        }
    }

    func playPreviousFromQueue() {
        guard currentQueueIndex > 0,
              let previous = queueManager.previousTrack(before: currentQueueIndex) else {
            seek(to: 0)
            return
        }

        Task {
            await play(track: previous.track, trackData: queueManager.trackData(for: previous.track.id), queueIndex: previous.index)
        }
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setActive(true)
        } catch {
            print("❌ [PlayerState] Failed to configure audio session: \(error)")
        }
    }

    private func activateAudioSession() throws {
        if audioSession.category != .playback {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetoothA2DP, .allowAirPlay])
        }
        try audioSession.setActive(true)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }

    private func setupRemoteCommands() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextFromQueue()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousFromQueue()
            return .success
        }
    }

    // MARK: - Player Wiring

    private func preparePlayer(with url: URL, startTime: Double) {
        cleanupPlayer()

        let item = makePlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.volume = Float(volume)

        addTimeObserver()

        if startTime > 0 {
            let cmTime = CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime)
        } else {
            playbackPosition = 0
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        playbackStatus = .ready
    }

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        guard let token = keychain.getAccessToken() else {
            return AVPlayerItem(url: url)
        }

        let headers = [
            "Authorization": "Bearer \(token)"
        ]

        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )

        return AVPlayerItem(asset: asset)
    }

    private func addTimeObserver() {
        guard let player else { return }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }

            let elapsed = CMTimeGetSeconds(time)

            Task { @MainActor in
                if elapsed.isFinite {
                    self.playbackPosition = elapsed
                }

                let durationTime = self.player?.currentItem?.duration ?? .invalid
                let durationSeconds = CMTimeGetSeconds(durationTime)
                if durationSeconds.isFinite, durationSeconds > 0 {
                    self.duration = durationSeconds
                } else if self.currentTrack.duration > 0 {
                    self.duration = self.currentTrack.duration
                }

                self.updateNowPlayingInfo()
            }
        }
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let currentItem = player?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
        }

        player?.pause()
        player = nil
    }

    // MARK: - Notifications

    @MainActor
    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    @MainActor
    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    @MainActor
    @objc private func handleItemDidFinish(_ notification: Notification) {
        playbackPosition = 0
        isPlaying = false
        playbackStatus = .ready
        updateNowPlayingInfo(playbackRate: 0)

        guard autoplayEnabled else { return }
        playNextFromQueue()
    }

    // MARK: - Helpers

    private func updateNowPlayingInfo(playbackRate: Float? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack.title
        info[MPMediaItemPropertyArtist] = currentTrack.artist

        let trackDuration = duration > 0 ? duration : max(currentTrack.duration, 0)
        info[MPMediaItemPropertyPlaybackDuration] = trackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate ?? (isPlaying ? 1 : 0)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func handlePlaybackFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        playbackStatus = .failed(error.localizedDescription)
        isPlaying = false
        updateNowPlayingInfo(playbackRate: 0)
        HapticManager.error()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
