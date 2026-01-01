//
//  LiquidMorphView.swift
//  mixbridge
//
//  SwiftUI wrapper for Metal-based liquid morph artwork transitions.
//

import SwiftUI
import MetalKit

// MARK: - Liquid Morph View

/// A Metal-based view that morphs between two artwork images with a liquid flow effect.
/// Used during crossfade transitions in mix mode.
struct LiquidMorphView: UIViewRepresentable {
    let fromArtworkURL: String
    let toArtworkURL: String
    let progress: Double
    let size: CGSize

    // MARK: - Metal Availability Check

    static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logError("[LiquidMorphView] Metal not available")
            return MTKView()
        }

        let mtkView = MTKView(frame: CGRect(origin: .zero, size: size), device: device)
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false  // Allow reading for transparency
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isOpaque = false  // Enable transparency
        mtkView.backgroundColor = .clear
        mtkView.layer.isOpaque = false
        mtkView.autoResizeDrawable = true

        // Start hidden until textures are ready (prevents red/garbage flash)
        mtkView.alpha = 0

        // Driven by progress changes, not continuous rendering
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true

        // Create renderer
        if let renderer = LiquidMorphRenderer(device: device) {
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
        }

        return mtkView
    }

    func updateUIView(_ mtkView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }

        // Update textures if URLs changed
        renderer.updateTextures(fromURL: fromArtworkURL, toURL: toArtworkURL)

        // Update progress
        renderer.progress = Float(progress)

        // Keep driving frames while progress is active so we can:
        // 1) clear/present even during setup, and
        // 2) wait until we have actually presented a textured frame before showing (fixes red flash).
        let shouldDriveFrames = progress > 0
        if shouldDriveFrames {
            mtkView.isPaused = false
            mtkView.setNeedsDisplay()
        } else {
            mtkView.isPaused = true
        }

        // Only show once we've presented at least one textured frame for this pair.
        // Until then, the regular SwiftUI artwork is visible behind this view.
        let shouldShow = renderer.texturesReady && renderer.hasPresentedTexturedFrame && progress > 0
        mtkView.alpha = shouldShow ? 1.0 : 0.0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator {
        var renderer: LiquidMorphRenderer?
    }
}

// MARK: - Preview

#Preview("Liquid Morph View") {
    ZStack {
        Color.black

        // Note: This preview won't work without actual images in cache
        // It's meant for visual testing in the app context
        LiquidMorphView(
            fromArtworkURL: "https://example.com/art1.jpg",
            toArtworkURL: "https://example.com/art2.jpg",
            progress: 0.5,
            size: CGSize(width: 300, height: 300)
        )
        .frame(width: 300, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
