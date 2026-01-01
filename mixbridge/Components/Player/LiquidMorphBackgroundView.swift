//
//  LiquidMorphBackgroundView.swift
//  mixbridge
//
//  Background variant of liquid morph view for full-screen transitions.
//  Uses the same Metal shader but optimized for background usage.
//

import SwiftUI
import MetalKit

// MARK: - Liquid Morph Background View

/// A background variant of the liquid morph effect.
/// Designed to fill the screen and be used with additional blur overlay.
struct LiquidMorphBackgroundView: UIViewRepresentable {
    let fromArtworkURL: String
    let toArtworkURL: String
    let progress: Double

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            logError("[LiquidMorphBackgroundView] Metal not available")
            return mtkView
        }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Background can render at lower resolution for performance
        mtkView.contentScaleFactor = UIScreen.main.scale * 0.5

        // Driven by progress changes
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true

        // Create renderer with lower quality settings for background
        if let renderer = LiquidMorphRenderer(device: device) {
            // Background can use less aggressive morphing since blur will smooth it
            renderer.amplitude = 0.06
            renderer.frequency = 2.5
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

        // Trigger redraw
        if progress > 0 && progress < 1.0 {
            mtkView.isPaused = false
            mtkView.setNeedsDisplay()
        } else {
            mtkView.isPaused = true
        }
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

#Preview("Liquid Morph Background") {
    ZStack {
        LiquidMorphBackgroundView(
            fromArtworkURL: "https://example.com/art1.jpg",
            toArtworkURL: "https://example.com/art2.jpg",
            progress: 0.5
        )
        .blur(radius: 60)
        .ignoresSafeArea()

        Text("Content Overlay")
            .foregroundStyle(.white)
            .font(.largeTitle)
    }
}
