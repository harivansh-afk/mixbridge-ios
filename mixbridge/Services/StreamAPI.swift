//
//  StreamAPI.swift
//  mixbridge
//
//  Single source of truth for the yt-dlp extraction service base URL
//  (ytdlp-api repo). Used by DownloadManager and SpotifyStreamService.
//

import Foundation

enum StreamAPI {
    /// Base URL of the yt-dlp extraction service (ytdlp-api on spark,
    /// exposed through the Cloudflare tunnel).
    static let baseURL = "https://mixbridge.harivan.sh"

    /// Parse a FastAPI error body ({"detail": "..."}) into a readable message.
    static func serverDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? String,
              !detail.isEmpty else {
            return nil
        }
        return detail
    }
}
