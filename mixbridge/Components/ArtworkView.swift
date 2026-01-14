//
//  ArtworkView.swift
//  mixbridge
//

import SwiftUI

struct ArtworkView: View {
    let artwork: String
    let size: CGFloat?
    let cornerRadius: CGFloat
    var placeholderIcon: String = "music-note-simple"
    var placeholderIconSize: CGFloat? = nil
    var showsProgressWhileLoading: Bool = true
    var shadow: (color: Color, radius: CGFloat, y: CGFloat)? = nil

    init(
        artwork: String,
        size: CGFloat? = nil,
        cornerRadius: CGFloat = 12,
        placeholderIcon: String = "music-note-simple",
        placeholderIconSize: CGFloat? = nil,
        showsProgressWhileLoading: Bool = true,
        shadow: (color: Color, radius: CGFloat, y: CGFloat)? = nil
    ) {
        self.artwork = artwork
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholderIcon = placeholderIcon
        self.placeholderIconSize = placeholderIconSize
        self.showsProgressWhileLoading = showsProgressWhileLoading
        self.shadow = shadow
    }

    var body: some View {
        Group {
            if artwork.starts(with: "http"), let url = URL(string: artwork) {
                CachedAsyncImagePhase(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder(isLoading: true)
                    case .success(let image):
                        configured(image: image)
                    case .failure:
                        placeholder(isLoading: false)
                    @unknown default:
                        placeholder(isLoading: false)
                    }
                }
            } else {
                placeholder(isLoading: false)
            }
        }
    }

    private func configured(image: Image) -> some View {
        let base = image
            .resizable()
            .scaledToFill()
            .modifier(ArtworkFrameModifier(size: size))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        if let shadow {
            return AnyView(base.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y))
        }

        return AnyView(base)
    }

    private func placeholder(isLoading: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray6))
                .modifier(ArtworkFrameModifier(size: size))

            Image(placeholderIcon)
                .renderingMode(.template)
                .font(.system(size: effectivePlaceholderIconSize, weight: .regular))
                .foregroundStyle(.gray.opacity(0.7))

            if isLoading && showsProgressWhileLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }

    private var effectivePlaceholderIconSize: CGFloat {
        if let placeholderIconSize { return placeholderIconSize }
        if let size {
            return min(60, max(18, size * 0.45))
        }
        return 28
    }

    private struct ArtworkFrameModifier: ViewModifier {
        let size: CGFloat?

        func body(content: Content) -> some View {
            if let size {
                content
                    .frame(width: size, height: size)
            } else {
                content
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
