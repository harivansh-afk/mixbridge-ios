//
//  ImageCacheManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import UIKit
import SwiftUI

actor ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        // Configure memory cache
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        // Setup disk cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    func getImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage
        }

        // Check disk cache
        if let diskImage = loadFromDisk(url: url) {
            // Store back in memory cache
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }

        // Download image
        return await downloadImage(from: url)
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
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
            let key = url.absoluteString as NSString
            memoryCache.setObject(image, forKey: key)
            saveToDisk(image: image, url: url)

            return image
        } catch {
            print("❌ [ImageCache] Failed to download image: \(error)")
            return nil
        }
    }

    private func loadFromDisk(url: URL) -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func saveToDisk(image: UIImage, url: URL) {
        let fileURL = cacheDirectory.appendingPathComponent(url.lastPathComponent)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        try? data.write(to: fileURL)
    }
}
