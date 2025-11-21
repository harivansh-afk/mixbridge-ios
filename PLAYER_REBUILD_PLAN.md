# Music Player Rebuild Plan

## Problem Analysis

Your current player is choppy because:
1. **UI state is tightly coupled to PlayerState** - When you swipe, it calls `onNext()` which updates PlayerState, triggering full re-render mid-gesture
2. **No debouncing** - PlayerState updates propagate immediately causing jank
3. **Missing state machine** - Animation states can conflict
4. **No velocity consideration** - Quick flicks should advance even with < 25% swipe

## Proposed Architecture

### Three-Layer Separation

```
┌─────────────────────────────────────────┐
│  Layer 3: UI Display State              │  ← Pure visual, instant updates
│  - displayedTrack, displayedNext/Prev   │
│  - dragOffset, isDragging               │
│  - NO PlayerState dependencies          │
└──────────────┬──────────────────────────┘
               │ Sync on change
┌──────────────▼──────────────────────────┐
│  Layer 2: Player State (Debounced)      │  ← @Observable, updates 4x/sec
│  - currentTrack                          │
│  - isPlaying, position, duration        │
│  - Debounced updates (250ms)            │
└──────────────┬──────────────────────────┘
               │ Snapshots
┌──────────────▼──────────────────────────┐
│  Layer 1: Audio Engine                  │  ← Background thread
│  - AVPlayer, seek, play/pause           │
│  - Heavy I/O operations                  │
└─────────────────────────────────────────┘
```

## Implementation Plan

### Step 1: Add Debouncing to PlayerState

**File:** `Models/PlayerState.swift`

```swift
@Observable
@MainActor
final class PlayerState: NSObject {
    // Existing properties...

    // New: Debounce subject for position updates
    private var positionUpdateSubject = PassthroughSubject<Double, Never>()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupDebouncedUpdates()
    }

    private func setupDebouncedUpdates() {
        // Update UI only 4x per second, not 60x
        positionUpdateSubject
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] position in
                self?.playbackPosition = position
            }
            .store(in: &cancellables)
    }

    func updatePosition(_ newPosition: Double) {
        // Send to debounced subject instead of direct update
        positionUpdateSubject.send(newPosition)
    }
}
```

**Why**: Prevents 60fps updates from audio engine causing UI thrashing

---

### Step 2: Create Carousel State Machine

**New File:** `Components/Player/CarouselState.swift`

```swift
@Observable
class CarouselState {
    enum AnimationPhase {
        case idle
        case dragging(offset: CGFloat)
        case settling(from: CGFloat, to: CGFloat, startTime: TimeInterval)
        case committed // Track changed, waiting for sync
    }

    var phase: AnimationPhase = .idle
    var dragOffset: CGFloat = 0

    // Display tracks (independent of player state)
    var displayedTrack: Track
    var displayedNext: Track?
    var displayedPrevious: Track?

    init(current: Track, next: Track?, previous: Track?) {
        self.displayedTrack = current
        self.displayedNext = next
        self.displayedPrevious = previous
    }

    // State transitions
    func beginDrag() {
        phase = .dragging(offset: 0)
    }

    func updateDrag(offset: CGFloat) {
        dragOffset = offset
        phase = .dragging(offset: offset)
    }

    func commitNext() {
        phase = .committed
        // Swap tracks instantly (no waiting for player)
        displayedTrack = displayedNext!
        displayedPrevious = displayedTrack // Will update from queue
        dragOffset = 0
    }

    func commitPrevious() {
        phase = .committed
        displayedTrack = displayedPrevious!
        displayedNext = displayedTrack
        dragOffset = 0
    }

    func syncWithPlayer(current: Track, next: Track?, previous: Track?) {
        // Only update if out of sync
        if displayedTrack.id != current.id {
            displayedTrack = current
            displayedNext = next
            displayedPrevious = previous
            dragOffset = 0
            phase = .idle
        }
    }
}
```

**Why**: Single source of truth for carousel state, atomic updates, no conflicts

---

### Step 3: Rebuild Gesture Handler with Velocity

**File:** `Components/ExpandedMusicPlayer.swift`

```swift
struct ExpandedPlayerView: View {
    @State private var carouselState: CarouselState
    @State private var playerState = PlayerState.shared

    // Haptics
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width

            ZStack {
                // Render all 3 tracks
                carouselView(screenWidth: screenWidth)
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        handleDragChanged(value, screenWidth: screenWidth)
                    }
                    .onEnded { value in
                        handleDragEnded(value, screenWidth: screenWidth)
                    }
            )
            .onChange(of: playerState.currentTrack.id) { _, newID in
                // Sync displayed tracks when player changes externally
                carouselState.syncWithPlayer(
                    current: playerState.currentTrack,
                    next: getNextTrack(),
                    previous: getPreviousTrack()
                )
            }
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, screenWidth: CGFloat) {
        if case .idle = carouselState.phase {
            carouselState.beginDrag()
            selectionFeedback.prepare()
        }

        carouselState.updateDrag(offset: value.translation.width)

        // Haptic at threshold
        let threshold = screenWidth * 0.25
        if abs(value.translation.width) > threshold && abs(value.translation.width) < threshold + 10 {
            selectionFeedback.selectionChanged()
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, screenWidth: CGFloat) {
        let threshold = screenWidth * 0.25
        let velocity = value.predictedEndTranslation.width - value.translation.width

        // Consider velocity for quick flicks
        let shouldAdvance = abs(value.translation.width) > threshold || abs(velocity) > 500

        if shouldAdvance {
            if value.translation.width > 0 && carouselState.displayedPrevious != nil {
                // Swipe right → previous
                impactFeedback.impactOccurred()
                carouselState.commitPrevious()

                // Update player in background (won't trigger re-render)
                Task.detached {
                    await MainActor.run {
                        playerState.playPreviousFromQueue()
                    }
                }
            } else if value.translation.width < 0 && carouselState.displayedNext != nil {
                // Swipe left → next
                impactFeedback.impactOccurred()
                carouselState.commitNext()

                Task.detached {
                    await MainActor.run {
                        playerState.playNextFromQueue()
                    }
                }
            }
        } else {
            // Snap back
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                carouselState.dragOffset = 0
                carouselState.phase = .idle
            }
        }
    }
}
```

**Why**:
- Velocity consideration for natural feel
- Haptics at decision point
- `Task.detached` prevents re-render blocking
- Clean state machine transitions

---

### Step 4: Optimize Carousel Rendering

```swift
private func carouselView(screenWidth: CGFloat) -> some View {
    ZStack {
        // Previous (left)
        if let prev = carouselState.displayedPrevious {
            artworkView(track: prev, namespace: nil)
                .offset(x: -screenWidth + carouselState.dragOffset)
                .opacity(calculateOpacity(offset: carouselState.dragOffset, direction: .left))
                .scaleEffect(0.9) // Slightly smaller
        }

        // Current (center)
        artworkView(track: carouselState.displayedTrack, namespace: namespace)
            .offset(x: carouselState.dragOffset)
            .scaleEffect(carouselState.phase.isInteractive ? 0.95 : 1.0)

        // Next (right)
        if let next = carouselState.displayedNext {
            artworkView(track: next, namespace: nil)
                .offset(x: screenWidth + carouselState.dragOffset)
                .opacity(calculateOpacity(offset: carouselState.dragOffset, direction: .right))
                .scaleEffect(0.9)
        }
    }
    .contentShape(Rectangle())
}

private func calculateOpacity(offset: CGFloat, direction: Direction) -> Double {
    let normalizedOffset = abs(offset) / UIScreen.main.bounds.width
    return direction == .left
        ? 0.5 + (offset > 0 ? normalizedOffset * 0.5 : 0)
        : 0.5 - (offset < 0 ? normalizedOffset * 0.5 : 0)
}
```

---

## Key Improvements Over Current Implementation

| Issue | Current | New Approach |
|-------|---------|--------------|
| **Choppy swipes** | Calls `onNext()` → PlayerState updates → re-render | Local `carouselState` updates → background player update |
| **No velocity** | 25% threshold only | Velocity OR threshold (500pt/s) |
| **Update frequency** | 60fps player updates | Throttled to 4fps (250ms) |
| **State conflicts** | No animation state tracking | State machine with clear phases |
| **Haptics timing** | On gesture end | At decision threshold |
| **Re-render blocking** | Synchronous state updates | `Task.detached` for player updates |

## Testing Checklist

- [ ] Swipe feels instant (< 16ms frame time)
- [ ] Quick flicks advance even at 20% swipe
- [ ] Haptic fires at 25% threshold
- [ ] Button navigation still works
- [ ] Auto-advance syncs correctly
- [ ] No visual glitches during rapid swipes
- [ ] Song title updates with artwork
- [ ] Background blur transitions smoothly

## References

Based on research from:
- **iPod Player (keremersu35)**: State machine pattern, gesture delegation
- **LocalWave (nexo-tech)**: Debounced updates, fractional seeking
- **WWDC 2023/2024**: @Observable, performance optimization
- **iOS HIG**: Touch targets, gesture thresholds
- **Best Practices Doc**: `/BEST_PRACTICES_GESTURE_MUSIC_UI.md`

---

## Next Steps

1. Review this plan together
2. Implement debouncing (Step 1)
3. Create CarouselState (Step 2)
4. Rebuild gesture handling (Step 3)
5. Test and iterate

Ready to start implementing?
