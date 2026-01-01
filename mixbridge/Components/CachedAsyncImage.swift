//
//  CachedAsyncImage.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .task(id: url) {
                        // Reset on URL change so we never show a stale image.
                        image = nil
                        isLoading = false
                        await loadImage(for: url)
                    }
            }
        }
    }

    private func loadImage(for requestURL: URL?) async {
        guard let requestURL, !isLoading else { return }

        isLoading = true

        if let cachedImage = await ImageCacheManager.shared.getImage(for: requestURL) {
            if requestURL == url {
                self.image = cachedImage
            }
        }

        isLoading = false
    }
}

// Convenience initializer for phase-based API similar to AsyncImage
struct CachedAsyncImagePhase<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error: Error?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content

        // Check memory cache synchronously to prevent flicker
        if let url = url {
            _image = State(initialValue: MemoryImageCache.shared.get(url.absoluteString))
        }
    }

    var body: some View {
        Group {
            if let image = image {
                content(.success(Image(uiImage: image)))
            } else if let _ = error {
                content(.failure(NSError(domain: "ImageCache", code: -1)))
            } else if isLoading {
                content(.empty)
            } else {
                content(.empty)
            }
        }
        .task(id: url) {
            // Reset on URL change so we never show a stale image.
            // Also check memory cache synchronously to avoid placeholder flicker.
            if let url {
                image = MemoryImageCache.shared.get(url.absoluteString)
            } else {
                image = nil
            }
            error = nil
            isLoading = false
            await loadImage(for: url)
        }
    }

    private func loadImage(for requestURL: URL?) async {
        guard let requestURL else {
            return
        }

        isLoading = true

        if let cachedImage = await ImageCacheManager.shared.getImage(for: requestURL) {
            if requestURL == url {
                self.image = cachedImage
                self.error = nil
            }
        } else {
            if requestURL == url {
                self.error = NSError(domain: "ImageCache", code: -1)
            }
        }

        isLoading = false
    }
}
