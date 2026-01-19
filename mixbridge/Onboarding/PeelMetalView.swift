import SwiftUI
import MetalKit

struct PeelMetalView: UIViewRepresentable {
    let bottomImageName: String
    let topImageName: String?
    let progress: Double
    let size: CGSize
    var amplitude: Float = 0.06
    var frequency: Float = 2.2

    static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logError(.rendering, "[PeelMetalView] Metal not available")
            return MTKView()
        }

        let mtkView = MTKView(frame: CGRect(origin: .zero, size: size), device: device)
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isOpaque = false
        mtkView.backgroundColor = .clear
        mtkView.layer.isOpaque = false
        mtkView.autoResizeDrawable = true

        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true

        if let renderer = PeelMetalRenderer(device: device) {
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
        }

        return mtkView
    }

    func updateUIView(_ mtkView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }

        renderer.updateTextures(bottomName: bottomImageName, topName: topImageName)
        renderer.progress = Float(progress)
        renderer.amplitude = amplitude
        renderer.frequency = frequency

        let shouldRender = progress > 0 || !renderer.hasPresentedTexturedFrame
        mtkView.isPaused = !shouldRender
        mtkView.setNeedsDisplay()

        let shouldShow = renderer.texturesReady
        mtkView.isHidden = !shouldShow
        mtkView.alpha = shouldShow ? 1.0 : 0.0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var renderer: PeelMetalRenderer?
    }
}
