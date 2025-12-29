//
//  ImageCacheManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import UIKit
import SwiftUI
import CryptoKit

// Synchronous memory cache for instant access (no flicker)
class MemoryImageCache {
    nonisolated static let shared = MemoryImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func get(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

actor ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cacheDirectory: URL

    private init() {
        // Setup disk cache directory
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    func getImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString

        // Check memory cache first (synchronous)
        if let cachedImage = MemoryImageCache.shared.get(key) {
            return cachedImage
        }

        // Check disk cache
        if let diskImage = await loadFromDisk(url: url) {
            // Store back in memory cache
            MemoryImageCache.shared.set(diskImage, forKey: key)
            return diskImage
        }

        // Download image
        return await downloadImage(from: url)
    }

    func clearCache() async {
        MemoryImageCache.shared.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clearMemoryCache() async {
        MemoryImageCache.shared.removeAll()
    }

    // MARK: - Private Methods

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }

            // Cache the image
            let key = url.absoluteString
            MemoryImageCache.shared.set(image, forKey: key)
            await saveToDisk(data: data, url: url)

            return image
        } catch {
            return nil
        }
    }

    private func loadFromDisk(url: URL) async -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(diskFilename(for: url))

        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }.value
    }

    private func saveToDisk(data: Data, url: URL) async {
        let fileURL = cacheDirectory.appendingPathComponent(diskFilename(for: url))

        _ = await Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: [.atomic])
        }.value
    }

    nonisolated private func diskFilename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
