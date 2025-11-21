//
//  ImageCacheManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import UIKit
import SwiftUI

// Synchronous memory cache for instant access (no flicker)
class MemoryImageCache {
    static let shared = MemoryImageCache()
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

    private nonisolated let fileManager = FileManager.default
    private nonisolated let cacheDirectory: URL

    private init() {
        // Setup disk cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    func getImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString

        // Check memory cache first (synchronous)
        if let cachedImage = MemoryImageCache.shared.get(key) {
            return cachedImage
        }

        // Check disk cache
        if let diskImage = loadFromDisk(url: url) {
            // Store back in memory cache
            MemoryImageCache.shared.set(diskImage, forKey: key)
            return diskImage
        }

        // Download image
        return await downloadImage(from: url)
    }

    func clearCache() async {
        await MainActor.run {
            MemoryImageCache.shared.removeAll()
        }
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clearMemoryCache() async {
        await MainActor.run {
            MemoryImageCache.shared.removeAll()
        }
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
            saveToDisk(image: image, url: url)

            return image
        } catch {
            return nil
        }
    }

    nonisolated private func loadFromDisk(url: URL) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    nonisolated private func saveToDisk(image: UIImage, url: URL) {
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        try? data.write(to: fileURL)
    }
}
