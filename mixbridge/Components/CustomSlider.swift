import SwiftUI

/// A custom slider component optimized for music player controls with visual and haptic feedback
///
/// Features:
/// - Smooth drag interaction with immediate visual feedback
/// - Haptic feedback during scrubbing
/// - Enlarged appearance when actively dragging
/// - Callback only triggers when drag ends (prevents excessive operations)
/// - Fully customizable appearance
///
/// Example:
/// ```swift
/// CustomSlider(
///     value: $playerState.playbackPosition,
///     bounds: 0...playerState.duration,
///     isDragging: $isDragging,
///     onEditingChanged: { editing in
///         if !editing {
///             // Perform expensive operation only when drag ends
///             playerState.seek(to: playerState.playbackPosition)
///         }
///     }
/// )
/// ```
struct CustomSlider: View {
    // MARK: - Properties

    /// The current value of the slider
    @Binding var value: Double

    /// The range of valid values
    let bounds: ClosedRange<Double>

    /// Whether the slider is currently being dragged
    @Binding var isDragging: Bool

    /// Callback when editing state changes (drag begins/ends)
    let onEditingChanged: (Bool) -> Void

    /// The color of the progress indicator
    var progressColor: Color = .white.opacity(0.85)

    /// The color of the track background
    var trackColor: Color = .white.opacity(0.2)

    /// Whether to provide haptic feedback during dragging
    var enableHaptics: Bool = true
    
    /// Vertical alignment of the slider track within the touch target
    var verticalAlignment: VerticalAlignment = .center

    // MARK: - Private State

    /// The last value at which haptic feedback was triggered
    @State private var lastHapticValue: Double?

    /// Haptic feedback generator
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let sliderHeight: CGFloat = 2 // Fixed thicker height for "solid" vibe
            
            ZStack(alignment: Alignment(horizontal: .leading, vertical: verticalAlignment)) {
                // Background track
                Capsule() // Changed from Capsule to Rectangle
                    .fill(trackColor)
                    .frame(height: sliderHeight)
                
                // Progress indicator
                Group {
                    HStack(spacing: 0) {
                        Capsule() // Changed from Capsule to Rectangle
                            .fill(progressColor)
                            .frame(
                                width: progressWidth(for: geometry),
                                height: isDragging ? 10 : 2
                            )
                        Spacer(minLength: 0)
                    }
                    .modifier(ConditionalGlassEffect(isDragging: isDragging))
                }
            }
            .frame(height: 44) // Touch target size
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        handleDragChanged(gesture: gesture, geometry: geometry)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
            .animation(.linear(duration: 0.1), value: value)
        }
        .frame(height: 44)
        .onAppear {
            hapticGenerator.prepare()
        }
    }

    // MARK: - Private Methods

    /// Calculates the width of the progress indicator
    private func progressWidth(for geometry: GeometryProxy) -> CGFloat {
        let normalizedValue = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        let clampedValue = max(0, min(1, normalizedValue))
        return geometry.size.width * clampedValue
    }

    /// Handles drag gesture changes
    private func handleDragChanged(gesture: DragGesture.Value, geometry: GeometryProxy) {
        if !isDragging {
            isDragging = true
            onEditingChanged(true)
        }

        // Calculate new value based on gesture location
        let normalizedX = max(0, min(1, gesture.location.x / geometry.size.width))
        let newValue = bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * normalizedX
        value = newValue

        // Trigger haptic feedback at regular intervals
        if enableHaptics {
            triggerHapticIfNeeded(for: newValue)
        }
    }

    /// Handles drag gesture end
    private func handleDragEnded() {
        isDragging = false
        lastHapticValue = nil
        onEditingChanged(false)
    }

    /// Triggers haptic feedback if the value has changed significantly
    private func triggerHapticIfNeeded(for newValue: Double) {
        let hapticThreshold = (bounds.upperBound - bounds.lowerBound) / 100.0

        if let lastValue = lastHapticValue {
            if abs(newValue - lastValue) > hapticThreshold {
                hapticGenerator.impactOccurred(intensity: 0.5)
                lastHapticValue = newValue
            }
        } else {
            lastHapticValue = newValue
        }
    }
}

// MARK: - Preview

#Preview("Playback Slider") {
    struct PreviewContainer: View {
        @State private var value: Double = 45.0
        @State private var isDragging = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Playback Position: \(Int(value))s")
                    .foregroundColor(.white)

                CustomSlider(
                    value: $value,
                    bounds: 0...180,
                    isDragging: $isDragging,
                    onEditingChanged: { editing in
                        print("Editing: \(editing)")
                    }
                )
                .padding(.horizontal, 20)

                Text(isDragging ? "Dragging..." : "Ready")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    return PreviewContainer()
}

#Preview("Volume Slider") {
    struct PreviewContainer: View {
        @State private var volume: Double = 0.7
        @State private var isDragging = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Volume: \(Int(volume * 100))%")
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.white.opacity(0.6))

                    CustomSlider(
                        value: $volume,
                        bounds: 0...1,
                        isDragging: $isDragging,
                        onEditingChanged: { editing in
                            if !editing {
                                print("Volume set to: \(volume)")
                            }
                        },
                        progressColor: .white.opacity(0.85),
                        trackColor: .white.opacity(0.2)
                    )

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    return PreviewContainer()
}

// MARK: - Conditional Glass Effect Modifier

struct ConditionalGlassEffect: ViewModifier {
    let isDragging: Bool

    func body(content: Content) -> some View {
        if isDragging {
            content.glassEffect(.clear)
        } else {
            content
        }
    }
}
