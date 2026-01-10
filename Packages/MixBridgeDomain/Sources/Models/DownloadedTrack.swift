//
//  DownloadedTrack.swift
//  MixBridgeDomain
//
//  Model for downloaded/offline tracks.
//

import Foundation

public struct DownloadedTrack: Codable, Equatable, Hashable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case trackId, localPath, fileSize, downloadedAt, expiresAt
    }

    public var trackId: String
    public var localPath: String
    public var fileSize: Int64
    public var downloadedAt: Date
    public var expiresAt: Date?

    public init(
        trackId: String,
        localPath: String,
        fileSize: Int64,
        downloadedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.trackId = trackId
        self.localPath = localPath
        self.fileSize = fileSize
        self.downloadedAt = downloadedAt
        self.expiresAt = expiresAt
    }
}
