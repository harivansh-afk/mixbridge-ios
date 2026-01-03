//
//  LiquidMorphRenderer.swift
//  mixbridge
//
//  Metal rendering coordinator for liquid morph artwork transitions.
//

import MetalKit
import UIKit

// MARK: - Uniforms (must match shader struct)

struct LiquidMorphUniforms {
    var progress: Float
    var time: Float
    var amplitude: Float
    var frequency: Float
}

// MARK: - Renderer

final class LiquidMorphRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader

    // MARK: - State

    var progress: Float = 0
    private var startTime: CFTimeInterval = CACurrentMediaTime()

    // Shader parameters
    var amplitude: Float = 0.08
    var frequency: Float = 3.0

    // Texture cache to avoid recreating textures every frame
    private var textureCache: [String: MTLTexture] = [:]
    private var fromTexture: MTLTexture?
    private var toTexture: MTLTexture?
    private var lastFromURL: String?
    private var lastToURL: String?

    /// Whether both textures are loaded and ready to render
    var texturesReady: Bool {
        fromTexture != nil && toTexture != nil
    }

    /// Whether we have successfully presented at least one frame with both textures.
    /// Use this to avoid showing a recycled/uninitialized CAMetalLayer frame (often red/magenta).
    private(set) var hasPresentedTexturedFrame: Bool = false

    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            logError(.rendering, "[LiquidMorph] Failed to create command queue")
            return nil
        }
        self.commandQueue = queue

        self.textureLoader = MTKTextureLoader(device: device)

        // Load shader library
        guard let library = device.makeDefaultLibrary() else {
            logError(.rendering, "[LiquidMorph] Failed to load default Metal library")
            return nil
        }

        guard let vertexFunction = library.makeFunction(name: "liquidMorphVertex"),
              let fragmentFunction = library.makeFunction(name: "liquidMorphFragment") else {
            logError(.rendering, "[LiquidMorph] Failed to load shader functions")
            return nil
        }

        // Create render pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logError(.rendering, "[LiquidMorph] Failed to create pipeline state: \(error)")
            return nil
        }

        super.init()
    }

    // MARK: - Public API

    /// Update textures from artwork URLs
    /// Uses memory cache for instant access to already-loaded images
    func updateTextures(fromURL: String, toURL: String) {
        // Only recreate textures if URLs changed
        // If textures aren't ready yet, keep attempting (images may land in cache a moment later).
        if fromURL == lastFromURL && toURL == lastToURL && texturesReady {
            return
        }

        lastFromURL = fromURL
        lastToURL = toURL
        hasPresentedTexturedFrame = false

        // Get or create textures
        fromTexture = getOrCreateTexture(for: fromURL)
        toTexture = getOrCreateTexture(for: toURL)

        // Clear old cache entries if cache is too large
        if textureCache.count > 6 {
            // Keep current textures, clear the rest
            let keysToKeep = Set([fromURL, toURL])
            textureCache = textureCache.filter { keysToKeep.contains($0.key) }
        }
    }

    // MARK: - Private Helpers

    private func getOrCreateTexture(for artworkURL: String) -> MTLTexture? {
        // Check cache first
        if let cached = textureCache[artworkURL] {
            return cached
        }

        // Get UIImage from memory cache
        guard let image = getImageFromCache(artworkURL) else {
            logWarning(.rendering, "[LiquidMorph] Image not in cache: \(artworkURL)")
            return nil
        }

        // Convert to texture
        guard let cgImage = image.cgImage else {
            logWarning(.rendering, "[LiquidMorph] Failed to get CGImage")
            return nil
        }

        // Convert to sRGB color space to prevent color distortion on P3/wide-gamut images
        let srgbImage = convertToSRGB(cgImage) ?? cgImage

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: false,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]

        do {
            let texture = try textureLoader.newTexture(cgImage: srgbImage, options: options)
            textureCache[artworkURL] = texture
            return texture
        } catch {
            logError(.rendering, "[LiquidMorph] Failed to create texture: \(error)")
            return nil
        }
    }

    /// Convert CGImage to sRGB color space to prevent color distortion
    /// Images in Display P3 or other wide-gamut spaces can appear with red tint when sampled as raw bytes
    private func convertToSRGB(_ cgImage: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // If already sRGB, return as-is
        if let imageColorSpace = cgImage.colorSpace,
           imageColorSpace.name == CGColorSpace.sRGB {
            return cgImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = 8
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func getImageFromCache(_ artworkURL: String) -> UIImage? {
        // Try memory cache first (synchronous)
        if let image = MemoryImageCache.shared.get(artworkURL) {
            return image
        }

        // If not in memory cache, try to construct URL and check async cache
        // This is a fallback - images should already be in memory from CachedAsyncImagePhase
        guard artworkURL.starts(with: "http"),
              let url = URL(string: artworkURL) else {
            return nil
        }

        return MemoryImageCache.shared.get(url.absoluteString)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No special handling needed
    }

    func draw(in view: MTKView) {
        logDebug(.rendering, "[LiquidMorph] draw called, texturesReady: \(texturesReady), hasPresentedTexturedFrame: \(hasPresentedTexturedFrame)")

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            logDebug(.rendering, "[LiquidMorph] No drawable or render pass descriptor")
            return
        }

        // CRITICAL: Always set clear action and color BEFORE creating command buffer
        // This prevents uninitialized GPU memory (red/magenta flash) from appearing
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // If textures aren't ready, just clear to transparent and return
        guard let fromTexture = fromTexture,
              let toTexture = toTexture else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Calculate time for animation
        let currentTime = Float(CACurrentMediaTime() - startTime)

        // Create uniforms
        var uniforms = LiquidMorphUniforms(
            progress: progress,
            time: currentTime,
            amplitude: amplitude,
            frequency: frequency
        )

        // Configure render encoder
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(fromTexture, index: 0)
        renderEncoder.setFragmentTexture(toTexture, index: 1)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidMorphUniforms>.stride, index: 0)

        // Draw fullscreen triangle
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        hasPresentedTexturedFrame = true
        commandBuffer.commit()
    }
}
