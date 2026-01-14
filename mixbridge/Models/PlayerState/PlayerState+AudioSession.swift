//
//  PlayerState+AudioSession.swift
//  mixbridge
//

import AVFoundation
import Foundation

extension PlayerState {
    // MARK: - Audio Session

    func configureAudioSession() {
        do {
            // Configure audio session for Now Playing integration
            // Note: Cannot use .mixWithOthers or it won't appear in Control Center/Lock Screen
            // Using .playback category makes us the primary audio app

            // Only configure if not already set to avoid OSStatus -50
            if audioSession.category != .playback || audioSession.mode != .default {
                try audioSession.setCategory(
                    .playback,
                    mode: .default,
                    options: [.allowBluetoothA2DP, .allowAirPlay]
                )
            }

            // Activate session
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }

            logInfo(.playback, "Audio session configured successfully")
        } catch let error as NSError {
            // OSStatus -50 means invalid parameter, but often non-fatal
            if error.code == -50 {
                logWarning(.playback, "Audio session configuration warning (non-fatal): \(error.localizedDescription)")
            } else {
                logError(.playback, "Failed to configure audio session: \(error.localizedDescription)")
            }
        }
    }

    func activateAudioSession() throws {
        // Only reconfigure if category is wrong
        if audioSession.category != .playback || audioSession.mode != .default {
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
        }

        // Try to activate, but don't throw if already active
        do {
            try audioSession.setActive(true)
        } catch let error as NSError {
            // Ignore if already active or if OSStatus -50
            if error.code != -50 {
                throw error
            }
        }
    }

    func setupNotifications() {
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

    // MARK: - Notifications

    @MainActor
    @objc func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            let wasSuspended = info[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false

            // Remember if we were playing before interruption
            let wasPlaying = isPlaying
            wasPlayingBeforeInterruption = wasPlaying

            logInfo(.playback, "Audio interruption began (wasSuspended: \(wasSuspended), wasPlaying: \(wasPlaying))")

            // For wasSuspended interruptions (like overlay windows), auto-resume immediately
            // The OS pauses the player but we want to keep playing
            if wasSuspended && wasPlaying {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                    do {
                        try self.activateAudioSession()
                    } catch {
                        logWarning(.playback, "Failed to reactivate after wasSuspended: \(error)")
                    }
                    self.resume()
                    logInfo(.playback, "Auto-resumed after wasSuspended interruption")
                }
                return
            }

            // For real interruptions (phone calls, Siri, etc.), pause properly
            if !wasSuspended {
                playbackCoordinator.pause()
                updateNowPlayingInfo(playbackRate: 0)
                scheduleSavePlaybackState(immediate: true)
            }

        case .ended:
            logInfo(.playback, "Audio interruption ended")

            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)

            // Try to resume if:
            // 1. iOS says we should resume, OR
            // 2. We were playing before and have an active track
            if options.contains(.shouldResume) || (wasPlayingBeforeInterruption && hasActiveTrack) {
                // Delay resume slightly to ensure audio session is fully restored
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay

                    // Re-activate audio session
                    do {
                        try self.activateAudioSession()
                    } catch {
                        logWarning(.playback, "Failed to reactivate audio session: \(error)")
                    }

                    // Resume playback
                    if self.wasPlayingBeforeInterruption {
                        self.resume()
                        logInfo(.playback, "Resumed playback after interruption")
                    }
                }
            }

            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    @MainActor
    @objc func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        logInfo(.playback, "Audio route changed: \(reason.rawValue)")

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged, Bluetooth disconnected, etc.
            pause()

        case .newDeviceAvailable:
            // New device connected - could auto-resume if we were interrupted
            // But generally safer to let user manually resume
            logInfo(.playback, "New audio device available")

        case .categoryChange:
            // Audio category changed by another app
            // Re-assert our audio session
            Task { @MainActor in
                try? self.activateAudioSession()
            }

        default:
            break
        }
    }
}

