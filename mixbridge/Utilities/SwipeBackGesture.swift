import SwiftUI

struct SwipeBackGesture: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragOffset: CGFloat = 0
    @State private var backgroundOpacity: Double = 1.0

    private let threshold: CGFloat = 100

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: dragOffset)
                .opacity(backgroundOpacity)
                .gesture(
                    createDragGesture(maxDrag: geometry.size.width)
                )
                .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: dragOffset)
                .animation(.easeOut(duration: 0.2), value: backgroundOpacity)
        }
    }

    private func createDragGesture(maxDrag: CGFloat) -> some Gesture {
        return
                DragGesture(minimumDistance: 10)
                    .updating($dragOffset) { value, state, _ in
                        // Only allow dragging from left edge (first 50 points)
                        guard value.startLocation.x < 50 else { return }

                        // Only allow right-direction drag
                        if value.translation.width > 0 {
                            state = value.translation.width
                        }
                    }
                    .onChanged { value in
                        guard value.startLocation.x < 50 && value.translation.width > 0 else { return }

                        // Update background opacity based on drag distance
                        let progress = min(value.translation.width / maxDrag, 1.0)
                        backgroundOpacity = 1.0 - (progress * 0.3)

                        // Haptic feedback at threshold
                        if value.translation.width > threshold && value.translation.width - 10 < threshold {
                            HapticManager.light()
                        }
                    }
                    .onEnded { value in
                        guard value.startLocation.x < 50 && value.translation.width > 0 else {
                            resetView()
                            return
                        }

                        if value.translation.width > threshold {
                            // Successful dismiss
                            HapticManager.medium()
                            dismiss()
                        } else {
                            // Reset view
                            resetView()
                        }
                    }
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.2)) {
            backgroundOpacity = 1.0
        }
    }
}

extension View {
    func swipeBackGesture() -> some View {
        self.modifier(SwipeBackGesture())
    }
}
