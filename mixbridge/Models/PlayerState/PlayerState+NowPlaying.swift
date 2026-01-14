//
//  PlayerState+NowPlaying.swift
//  mixbridge
//

import Foundation
import MediaPlayer
import UIKit

extension PlayerState {
    // MARK: - Now Playing

    func updateNowPlayingInfo(playbackRate: Float? = nil) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentTrack.title
        info[MPMediaItemPropertyArtist] = currentTrack.artist
        info[MPMediaItemPropertyAlbumTitle] = currentTrack.album

        let trackDuration = duration > 0 ? duration : max(currentTrack.duration, 0)
        info[MPMediaItemPropertyPlaybackDuration] = trackDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate ?? (isPlaying ? 1 : 0)

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if DEBUG
        // Only log meaningful updates, not elapsed time changes
        // Uncomment below for verbose logging:
        // print("🎨 Now Playing updated: \(currentTrack.title)")
        #endif
    }

    func refreshArtwork(for track: Track) {
        artworkTask?.cancel()

        // Set placeholder artwork immediately
        nowPlayingArtwork = nil
        updateNowPlayingInfo()

        if track.artwork.starts(with: "http"), let url = URL(string: track.artwork) {
            artworkTask = Task { [weak self] in
                guard let self else { return }

                if let image = await ImageCacheManager.shared.getImage(for: url) {
                    // Create artwork with proper handler that returns resized images
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
                        // Resize image to requested size for optimal display
                        let renderer = UIGraphicsImageRenderer(size: requestedSize)
                        return renderer.image { _ in
                            image.draw(in: CGRect(origin: .zero, size: requestedSize))
                        }
                    }

                    await MainActor.run {
                        self.nowPlayingArtwork = artwork
                        self.updateNowPlayingInfo()
                        logDebug(.playback, "Artwork loaded: \(track.title)")
                    }
                } else {
                    logWarning(.playback, "Artwork load failed: \(track.title)")
                }
            }
        } else if let image = UIImage(named: track.artwork) {
            // Local asset
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
                let renderer = UIGraphicsImageRenderer(size: requestedSize)
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: requestedSize))
                }
            }
            nowPlayingArtwork = artwork
            updateNowPlayingInfo()
        } else {
            nowPlayingArtwork = nil
            updateNowPlayingInfo()
        }
    }

    func handlePlaybackFailure(_ error: Error) {
        errorMessage = error.localizedDescription
        playbackStatus = .failed(error.localizedDescription)
        isPlaying = false
        updateNowPlayingInfo(playbackRate: 0)
        HapticManager.error()
    }
}

