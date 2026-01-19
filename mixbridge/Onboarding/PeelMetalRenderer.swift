import MetalKit
import UIKit

final class PeelMetalRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader

    // MARK: - State

    var progress: Float = 0
    var amplitude: Float = 0.06
    var frequency: Float = 2.2
    private var startTime: CFTimeInterval = CACurrentMediaTime()

    private var textureCache: [String: MTLTexture] = [:]
    private var topTexture: MTLTexture?
    private var bottomTexture: MTLTexture?
    private var lastTopName: String?
    private var blackTexture: MTLTexture?
    private var lastBottomName: String?

    var texturesReady: Bool {
        topTexture != nil && bottomTexture != nil
    }

    private(set) var hasPresentedTexturedFrame: Bool = false

    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            logError(.rendering, "[PeelMetal] Failed to create command queue")
            return nil
        }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "liquidMorphVertex"),
              let fragmentFunction = library.makeFunction(name: "liquidMorphFragment") else {
            logError(.rendering, "[PeelMetal] Failed to load shader functions")
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            logError(.rendering, "[PeelMetal] Failed to create pipeline state: \(error)")
            return nil
        }

        super.init()
    }

    // MARK: - Public API

    func updateTextures(bottomName: String, topName: String?) {
        if bottomName == lastBottomName, topName == lastTopName, texturesReady {
            return
        }

        lastBottomName = bottomName
        lastTopName = topName
        hasPresentedTexturedFrame = false

        bottomTexture = getOrCreateTexture(named: bottomName)
        if let topName = topName {
            topTexture = getOrCreateTexture(named: topName) ?? bottomTexture
        } else {
            topTexture = getOrCreateBlackTexture() ?? bottomTexture
        }

        if textureCache.count > 6 {
            let keysToKeep = Set([bottomName, topName].compactMap { $0 })
            textureCache = textureCache.filter { keysToKeep.contains($0.key) }
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        guard let topTexture = topTexture,
              let bottomTexture = bottomTexture else {
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

        let currentTime = Float(CACurrentMediaTime() - startTime)
        var uniforms = LiquidMorphUniforms(
            progress: progress,
            time: currentTime,
            amplitude: amplitude,
            frequency: frequency
        )

        renderEncoder.setRenderPipelineState(pipelineState)
        // Match LiquidMorphView: "from" (index 0) -> "to" (index 1).
        // For auth peel: from = black, to = background, so it flows top -> bottom.
        renderEncoder.setFragmentTexture(topTexture, index: 0)
        renderEncoder.setFragmentTexture(bottomTexture, index: 1)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidMorphUniforms>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        hasPresentedTexturedFrame = true
        commandBuffer.commit()
    }

    // MARK: - Texture Loading

    private func getOrCreateTexture(named name: String) -> MTLTexture? {
        if let cached = textureCache[name] {
            return cached
        }

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: false,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]

        do {
            let texture = try textureLoader.newTexture(
                name: name,
                scaleFactor: UIScreen.main.scale,
                bundle: .main,
                options: options
            )
            textureCache[name] = texture
            return texture
        } catch {
            logWarning(.rendering, "[PeelMetal] Failed to load texture: \(name) - \(error)")
            return nil
        }
    }

    private func getOrCreateBlackTexture() -> MTLTexture? {
        if let blackTexture = blackTexture {
            return blackTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        var pixel: [UInt8] = [0, 0, 0, 255]
        pixel.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }

        blackTexture = texture
        return texture
    }
}
