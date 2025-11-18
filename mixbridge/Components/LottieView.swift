import SwiftUI
import UIKit
import Lottie

struct LottieView: UIViewRepresentable {
    let animationName: String
    var loopMode: LottieLoopMode = .playOnce
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var animationSpeed: CGFloat = 1.0
    var onCompletion: (() -> Void)?

    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView()
        animationView.translatesAutoresizingMaskIntoConstraints = false
        configure(animationView, coordinator: context.coordinator)
        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        configure(uiView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(animationName: animationName, onCompletion: onCompletion)
    }

    private func configure(_ animationView: LottieAnimationView, coordinator: Coordinator) {
        animationView.contentMode = contentMode
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.backgroundBehavior = .pauseAndRestore

        if animationView.animation == nil || coordinator.animationName != animationName {
            coordinator.animationName = animationName
            animationView.animation = LottieAnimation.named(animationName)
            animationView.currentProgress = 0

            print("🎬 Loading animation: \(animationName)")
            if animationView.animation == nil {
                print("❌ Failed to load animation: \(animationName)")
            } else {
                print("✅ Animation loaded successfully")
            }
        }

        guard animationView.animation != nil else {
            print("⚠️ Animation is nil, cannot play")
            return
        }

        if !animationView.isAnimationPlaying {
            print("▶️ Starting animation playback")
            animationView.play { finished in
                print("🏁 Animation finished: \(finished)")
                guard finished else { return }
                coordinator.onCompletion?()
            }
        }
    }

    final class Coordinator {
        var animationName: String
        var onCompletion: (() -> Void)?

        init(animationName: String, onCompletion: (() -> Void)?) {
            self.animationName = animationName
            self.onCompletion = onCompletion
        }
    }
}
