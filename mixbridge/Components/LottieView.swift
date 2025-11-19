import Lottie
import SwiftUI

public struct LottieView: UIViewRepresentable {
    let file: File
    var loopMode: LottieLoopMode
    var speed: CGFloat
    let preserveLastFrame: Bool
    var onComplete: (() -> Void)?

    public init(file: File, loopMode: LottieLoopMode = .playOnce, speed: CGFloat = 1.0, preserveLastFrame: Bool = true, onComplete: (() -> Void)? = nil) {
        self.file = file
        self.loopMode = loopMode
        self.speed = speed
        self.preserveLastFrame = preserveLastFrame
        self.onComplete = onComplete
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    public func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        let animationView = LottieAnimationView()

        context.coordinator.containerView = containerView
        context.coordinator.animationView = animationView

        // Try to load from module bundle first, then main bundle as fallback
        if let animation = LottieAnimation.named(file.rawValue, bundle: .main) {
            animationView.animation = animation
        }
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = loopMode
        animationView.animationSpeed = speed
        animationView.play { [weak coordinator = context.coordinator] _ in
            coordinator?.onComplete?()
            if !preserveLastFrame {
                coordinator?.cleanupAnimation()
            }
        }

        containerView.addSubview(animationView)

        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.heightAnchor.constraint(equalTo: containerView.heightAnchor).isActive = true
        animationView.widthAnchor.constraint(equalTo: containerView.widthAnchor).isActive = true

        return containerView
    }

    public func updateUIView(_: UIViewType, context _: Context) { /* --- */ }

    public static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.animationView?.stop()
        coordinator.animationView?.removeFromSuperview()

        coordinator.animationView = nil
        coordinator.containerView = nil
    }

    public class Coordinator {
        var containerView: UIView?
        var animationView: LottieAnimationView?
        var onComplete: (() -> Void)?

        init(onComplete: (() -> Void)?) {
            self.onComplete = onComplete
        }

        func cleanupAnimation() {
            animationView?.removeFromSuperview()
            animationView = nil
        }
    }
}

public extension LottieView {
    enum File: String {
        case logo
        case loadingSearchProducts = "loading-products-circle"
        case loadingSearchLogos = "logos-loop"

        case onboardingTutorialBookmarks
        case onboardingTutorialCompare
        case onboardingTutorialComplete
        case onboardingTutorialExtension
    }
}
