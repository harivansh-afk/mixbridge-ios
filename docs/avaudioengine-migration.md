# AVAudioEngine Migration Architecture

## Executive Summary

This document outlines the migration from AVPlayer-based mixing to AVAudioEngine for superior audio processing capabilities. The migration enables real-time DSP, beat alignment, loudness normalization, and professional DJ-style transitions.

---

## Current Architecture Analysis

### File Tree (Current)

```
mixbridge/
├── Services/
│   ├── PlaybackCoordinator.swift      # Main playback orchestrator
│   ├── MixPlaybackEngine.swift        # Current AVPlayer-based mixing
│   ├── StreamURLCache.swift           # Stream URL caching (3min TTL)
│   ├── QueueManager.swift             # Queue state management
│   ├── TrackPrefetcher.swift          # Image/metadata prefetching
│   └── PlaybackPositionTracker.swift  # Position persistence
├── Models/
│   ├── Track.swift                    # Track model
│   ├── PlayerState.swift              # Playback state
│   └── SoundCloudModels.swift         # API models
└── Components/
    └── Player/
        ├── PlayerComponents.swift     # UI components
        └── CarouselState.swift        # Carousel state
```

### Current Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CURRENT ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   User Tap                                                                   │
│      │                                                                       │
│      ▼                                                                       │
│   ┌──────────────────┐                                                       │
│   │ PlaybackCoord-   │──────────┐                                           │
│   │ inator           │          │                                           │
│   └────────┬─────────┘          │                                           │
│            │                    │                                           │
│            │ mixEnabled?        │ !mixEnabled                               │
│            ▼                    ▼                                           │
│   ┌──────────────────┐   ┌──────────────────┐                               │
│   │ MixPlaybackEngine│   │ AVQueuePlayer    │                               │
│   │ (2x AVPlayer)    │   │ (single)         │                               │
│   └────────┬─────────┘   └──────────────────┘                               │
│            │                                                                 │
│            ▼                                                                 │
│   ┌──────────────────┐                                                       │
│   │ StreamURLCache   │◄────── Convex getDirectStreamURL()                   │
│   │ (3min TTL)       │                                                       │
│   └──────────────────┘                                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Limitations of Current Approach

| Limitation | Impact |
|------------|--------|
| Volume-only mixing | No EQ, filtering, or DSP during crossfade |
| No audio analysis | Cannot detect BPM, loudness, or energy |
| No sample-accurate timing | Cannot beat-align transitions |
| Opaque streams | Cannot access raw audio buffers |
| Two separate AVPlayers | No true audio graph processing |

---

## AVAudioEngine Overview

### Core Concepts

AVAudioEngine provides a **node-based audio graph** where audio flows from source nodes through processing nodes to output nodes.

#### Node Types

| Type | Examples | Purpose |
|------|----------|---------|
| **Source** | AVAudioPlayerNode, AVAudioInputNode | Generate audio |
| **Processing** | AVAudioMixerNode, AVAudioUnitEQ, AVAudioUnitReverb | Transform audio |
| **Destination** | AVAudioOutputNode | Output to speaker/headphones |

#### Key Classes

```swift
// Engine - manages the audio graph
let engine = AVAudioEngine()

// Player node - plays audio files/buffers
let player = AVAudioPlayerNode()

// Mixer - combines multiple inputs
let mixer = AVAudioMixerNode()

// EQ - frequency adjustment
let eq = AVAudioUnitEQ(numberOfBands: 3)

// Time pitch - speed/pitch control
let timePitch = AVAudioUnitTimePitch()
```

#### Graph Construction Pattern

```swift
// 1. Attach nodes to engine
engine.attach(player)
engine.attach(eq)
engine.attach(mixer)

// 2. Connect nodes (order matters)
engine.connect(player, to: eq, format: format)
engine.connect(eq, to: mixer, format: format)
engine.connect(mixer, to: engine.mainMixerNode, format: format)

// 3. Prepare and start
engine.prepare()
try engine.start()
```

#### Audio Scheduling

```swift
// Schedule entire file
player.scheduleFile(audioFile, at: nil)

// Schedule with precise timing (for beat alignment)
let sampleTime = AVAudioFramePosition(beatAlignedTime * sampleRate)
let audioTime = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
player.scheduleFile(audioFile, at: audioTime)

// Schedule buffer (for streaming)
player.scheduleBuffer(buffer, at: nil, options: [])
```

#### Audio Taps (Real-time Analysis)

```swift
// Install tap on any node for real-time audio access
let format = player.outputFormat(forBus: 0)
player.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
    // Analyze buffer for loudness, BPM, etc.
    let samples = buffer.floatChannelData?[0]
    // Process samples...
}
```

---

## Proposed Architecture

### File Tree (Proposed)

```
mixbridge/
├── Services/
│   ├── PlaybackCoordinator.swift         # Orchestrator (updated)
│   ├── MixPlaybackEngine.swift           # DEPRECATED - kept for fallback
│   │
│   ├── Audio/                            # NEW: Audio engine layer
│   │   ├── MixAudioEngine.swift          # AVAudioEngine-based mixer
│   │   ├── AudioFileCache.swift          # Local audio file caching
│   │   ├── AudioFormatConverter.swift    # Format conversion (AAC/MP3 -> PCM)
│   │   └── StreamToFileDownloader.swift  # Progressive download
│   │
│   ├── Analysis/                         # NEW: Audio analysis
│   │   ├── AudioAnalyzer.swift           # Coordinator for analysis
│   │   ├── LoudnessAnalyzer.swift        # LUFS/dB metering
│   │   ├── BeatDetector.swift            # BPM and beat phase
│   │   └── EnergyAnalyzer.swift          # Energy envelope
│   │
│   ├── Transitions/                      # NEW: Transition planning
│   │   ├── TransitionPlanner.swift       # Creates TransitionPlans
│   │   ├── TransitionPlan.swift          # Plan data model
│   │   └── TransitionExecutor.swift      # Executes plans on engine
│   │
│   ├── StreamURLCache.swift              # Unchanged
│   ├── QueueManager.swift                # Unchanged
│   └── TrackPrefetcher.swift             # Updated for audio files
│
├── Models/
│   ├── Track.swift
│   ├── PlayerState.swift
│   └── AudioAnalysisResult.swift         # NEW: Analysis data model
│
└── docs/
    ├── expansion.md
    └── avaudioengine-migration.md        # This document
```

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              MIX AUDIO SYSTEM                                         │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐    │
│   │                          PlaybackCoordinator                                 │    │
│   │                                                                              │    │
│   │   - Receives play() requests from UI                                        │    │
│   │   - Decides: MixAudioEngine vs AVQueuePlayer (fallback)                     │    │
│   │   - Manages position tracking, play history                                 │    │
│   └───────────────────────────────────┬─────────────────────────────────────────┘    │
│                                       │                                              │
│                    ┌──────────────────┴──────────────────┐                           │
│                    │                                      │                           │
│                    ▼                                      ▼                           │
│   ┌────────────────────────────────┐    ┌────────────────────────────────┐           │
│   │       MixAudioEngine           │    │    AVQueuePlayer (fallback)    │           │
│   │                                │    │                                │           │
│   │   Primary mixing engine        │    │    Used when:                  │           │
│   │   AVAudioEngine-based          │    │    - AVAudioEngine fails       │           │
│   │   DSP, EQ, analysis            │    │    - mixEnabled = false        │           │
│   └───────────────┬────────────────┘    └────────────────────────────────┘           │
│                   │                                                                   │
│   ┌───────────────┴───────────────────────────────────────────────────────────┐      │
│   │                         AVAudioEngine Graph                                │      │
│   │                                                                            │      │
│   │   ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────────┐    │      │
│   │   │ PlayerA   │───▶│  EQ_A     │───▶│ Filter_A  │───▶│               │    │      │
│   │   │           │    │ (3-band)  │    │ (lo-pass) │    │               │    │      │
│   │   └─────┬─────┘    └───────────┘    └───────────┘    │               │    │      │
│   │         │                                             │  Transition  │────┼──▶ Out
│   │         │ TAP ─────▶ [AudioAnalyzer]                 │    Mixer     │    │      │
│   │                                                       │               │    │      │
│   │   ┌───────────┐    ┌───────────┐    ┌───────────┐    │               │    │      │
│   │   │ PlayerB   │───▶│  EQ_B     │───▶│ Filter_B  │───▶│               │    │      │
│   │   │           │    │ (3-band)  │    │ (hi-pass) │    │               │    │      │
│   │   └─────┬─────┘    └───────────┘    └───────────┘    └───────────────┘    │      │
│   │         │                                                                  │      │
│   │         │ TAP ─────▶ [AudioAnalyzer]                                      │      │
│   │                                                                            │      │
│   └────────────────────────────────────────────────────────────────────────────┘      │
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐    │
│   │                          Data Pipeline                                       │    │
│   │                                                                              │    │
│   │   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐               │    │
│   │   │ StreamURL-    │    │ AudioFile-    │    │ AVAudioFile   │               │    │
│   │   │ Cache         │───▶│ Cache         │───▶│ (ready to     │               │    │
│   │   │               │    │               │    │  schedule)    │               │    │
│   │   │ URL caching   │    │ Download +    │    │               │               │    │
│   │   │ 3min TTL      │    │ convert       │    │ 44.1kHz PCM   │               │    │
│   │   └───────────────┘    └───────────────┘    └───────────────┘               │    │
│   │                                                                              │    │
│   └─────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐    │
│   │                       TransitionPlanner                                      │    │
│   │                                                                              │    │
│   │   Inputs:                           Outputs:                                 │    │
│   │   - Current track analysis          - TransitionPlan                        │    │
│   │   - Next track analysis               - fadeDuration                        │    │
│   │   - User preferences                  - fadeType                            │    │
│   │   - expansion.md level                - eqCurves                            │    │
│   │                                       - beatAlignOffset                     │    │
│   │                                       - targetLUFS                          │    │
│   │                                                                              │    │
│   └─────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Instant Playback: The Prewarm Pipeline

For instant playback, we need aggressive prewarming at multiple levels:

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                        INSTANT PLAYBACK PIPELINE                                      │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│   Timeline: Track N playing                                                          │
│   ─────────────────────────────────────────────────────────────────────────────────  │
│                                                                                       │
│   0%        25%        50%        75%        90%        100%                         │
│   │          │          │          │          │          │                           │
│   │          │          │          │          │          │                           │
│   │          │    ┌─────┴──────────┴──────────┴──────────┤                           │
│   │          │    │                                      │                           │
│   │          │    │  PREWARM WINDOW (N+1, N+2)          │                           │
│   │          │    │                                      │                           │
│   │          │    │  Level 1: Stream URL (already done) │                           │
│   │          │    │  Level 2: Download audio file       │                           │
│   │          │    │  Level 3: Convert to AVAudioFile    │                           │
│   │          │    │  Level 4: Schedule on PlayerB       │                           │
│   │          │    │  Level 5: Pre-analyze (BPM, LUFS)   │                           │
│   │          │    │  Level 6: Compute TransitionPlan    │                           │
│   │          │    │                                      │                           │
│   │          │    └──────────────────────────────────────┤                           │
│   │          │                                           │                           │
│   │          │                               ┌───────────┴───────┐                   │
│   │          │                               │  CROSSFADE WINDOW │                   │
│   │          │                               │  Execute plan     │                   │
│   │          │                               │  EQ curves active │                   │
│   │          │                               │  Volume ramping   │                   │
│   │          │                               └───────────────────┘                   │
│   │          │                                                                       │
│   │          │                                                                       │
│   │   ┌──────┴──────────────────────────────────────────────────────────────────┐   │
│   │   │                                                                          │   │
│   │   │  BACKGROUND PREFETCH (N+2, N+3, N+4, N+5)                               │   │
│   │   │                                                                          │   │
│   │   │  - Stream URLs (existing StreamURLCache)                                │   │
│   │   │  - Audio file downloads (low priority)                                  │   │
│   │   │  - Artwork images (existing TrackPrefetcher)                            │   │
│   │   │                                                                          │   │
│   │   └──────────────────────────────────────────────────────────────────────────┘   │
│   │                                                                                   │
│   └───────────────────────────────────────────────────────────────────────────────   │
│                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### State Machine

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                        MixAudioEngine STATE MACHINE                                   │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│   ┌─────────────┐                                                                    │
│   │    IDLE     │◄───────────────────────────────────────────────────────────────┐   │
│   └──────┬──────┘                                                                │   │
│          │ play()                                                                │   │
│          ▼                                                                       │   │
│   ┌─────────────┐                                                                │   │
│   │  LOADING    │──── error ────▶ IDLE (fallback to AVPlayer)                   │   │
│   └──────┬──────┘                                                                │   │
│          │ audio ready                                                           │   │
│          ▼                                                                       │   │
│   ┌─────────────┐                                                                │   │
│   │  PLAYING    │◄──────────────────────────────────────────────────────────┐   │   │
│   │  (single)   │                                                            │   │   │
│   └──────┬──────┘                                                            │   │   │
│          │ reach prewarm point                                               │   │   │
│          ▼                                                                   │   │   │
│   ┌─────────────┐                                                            │   │   │
│   │  PREWARMING │                                                            │   │   │
│   │             │──── no next track ───▶ PLAYING (single)                   │   │   │
│   │             │──── prewarm failed ──▶ PLAYING (single, fallback later)   │   │   │
│   └──────┬──────┘                                                            │   │   │
│          │ next ready + reach fade point                                     │   │   │
│          ▼                                                                   │   │   │
│   ┌─────────────┐                                                            │   │   │
│   │ CROSSFADING │                                                            │   │   │
│   │             │──── abort (seek, skip, queue change) ──▶ PLAYING (single) │   │   │
│   └──────┬──────┘                                                            │   │   │
│          │ fade complete                                                     │   │   │
│          ▼                                                                   │   │   │
│   ┌─────────────┐                                                            │   │   │
│   │  PROMOTED   │────────────────────────────────────────────────────────────┘   │   │
│   │  PlayerB    │                                                                │   │
│   │  -> PlayerA │                                                                │   │
│   └─────────────┘                                                                │   │
│          │ stop()                                                                │   │
│          ▼                                                                       │   │
│   ┌─────────────┐                                                                │   │
│   │    IDLE     │────────────────────────────────────────────────────────────────┘   │
│   └─────────────┘                                                                    │
│                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Data Models

### TransitionPlan

```swift
/// A complete plan for transitioning between two tracks
struct TransitionPlan {
    // MARK: - Tracks
    let outgoingTrackId: String
    let incomingTrackId: String

    // MARK: - Timing
    let fadeOutStartTime: Double        // When to begin fading out (seconds from start)
    let fadeDuration: Double            // How long the crossfade lasts
    let incomingStartOffset: Double     // Where in incoming track to begin (for beat alignment)

    // MARK: - Curve
    let fadeType: FadeType              // .equalPower, .linear, .sCurve, .exponential

    // MARK: - EQ (Level 6: DJ Polish)
    let outgoingEQCurve: EQCurve?       // High cut during fadeout
    let incomingEQCurve: EQCurve?       // High duck during fadein

    // MARK: - Loudness
    let outgoingGainAdjust: Float       // dB adjustment for loudness matching
    let incomingGainAdjust: Float       // dB adjustment for loudness matching

    // MARK: - Sync (Level 3)
    let beatAlignmentOffset: Double?    // Sample offset for beat grid alignment
    let syncMode: SyncMode              // .none, .beat, .bar

    // MARK: - Metadata
    let confidence: Float               // 0-1, how confident we are in this plan
    let analysisAvailable: Bool         // Whether we had analysis data
}

enum FadeType {
    case linear
    case equalPower      // cos/sin curve (current)
    case sCurve          // Smoother than equal power
    case exponential     // Aggressive
}

enum SyncMode {
    case none
    case beat            // Align to beat
    case bar             // Align to bar (4 beats)
}

struct EQCurve {
    let lowGain: Float       // dB, -12 to +12
    let midGain: Float
    let highGain: Float
    let lowPassCutoff: Float?   // Hz, nil = no filter
    let highPassCutoff: Float?  // Hz, nil = no filter
}
```

### AudioAnalysisResult

```swift
/// Analysis results for a single track
struct AudioAnalysisResult {
    let trackId: String
    let analyzedAt: Date

    // Loudness
    let integratedLUFS: Float       // -23 to 0 typical
    let peakdB: Float               // Peak level
    let dynamicRange: Float         // Difference between loud and quiet

    // Tempo
    let bpm: Float?                 // nil if detection failed
    let bpmConfidence: Float        // 0-1
    let beatPhase: Double?          // Offset to first downbeat (seconds)

    // Energy
    let averageEnergy: Float        // 0-1
    let energyProfile: [Float]      // Energy over time (e.g., 10 samples)

    // Sections (Level 5)
    let introEndTime: Double?       // Where intro ends
    let outroStartTime: Double?     // Where outro begins
    let hasVocalPresence: Bool      // Detected vocals
}
```

---

## Implementation Phases

### Phase 1: Foundation (Parity + Basic Polish)

**Goal**: Replace AVPlayer mixing with AVAudioEngine, maintain feature parity, add basic EQ.

**Files to Create**:
- `Services/Audio/MixAudioEngine.swift`
- `Services/Audio/AudioFileCache.swift`
- `Services/Audio/StreamToFileDownloader.swift`

**Key Implementation**:

```swift
@MainActor
final class MixAudioEngine {
    private let engine = AVAudioEngine()

    // Two player chains (A = current, B = next)
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let eqA = AVAudioUnitEQ(numberOfBands: 3)
    private let eqB = AVAudioUnitEQ(numberOfBands: 3)
    private let transitionMixer = AVAudioMixerNode()

    private var activePlayer: AVAudioPlayerNode { playerA }
    private var standbyPlayer: AVAudioPlayerNode { playerB }

    func setupGraph() throws {
        // Attach all nodes
        [playerA, playerB, eqA, eqB, transitionMixer].forEach { engine.attach($0) }

        // Connect chains
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerA, to: eqA, format: format)
        engine.connect(eqA, to: transitionMixer, format: format)
        engine.connect(playerB, to: eqB, format: format)
        engine.connect(eqB, to: transitionMixer, format: format)
        engine.connect(transitionMixer, to: engine.mainMixerNode, format: format)

        engine.prepare()
        try engine.start()
    }

    func play(audioFile: AVAudioFile, on player: AVAudioPlayerNode) {
        player.scheduleFile(audioFile, at: nil)
        player.play()
    }

    func crossfade(duration: Double) {
        // Animate volumes using CADisplayLink (like current impl)
        // But now we can also animate EQ parameters!
    }
}
```

### Phase 2: Audio File Caching

**Goal**: Download and convert streaming audio to local files for AVAudioEngine.

**Pattern**: Progressive download with format conversion.

```swift
actor AudioFileCache {
    private let fileManager = FileManager.default
    private var cache: [String: URL] = [:]  // trackId -> local file URL
    private var inFlight: [String: Task<URL, Error>] = [:]

    func ensureAudioFile(
        for trackId: String,
        streamData: CachedStreamData
    ) async throws -> AVAudioFile {
        // Check cache first
        if let cachedURL = cache[trackId],
           fileManager.fileExists(atPath: cachedURL.path) {
            return try AVAudioFile(forReading: cachedURL)
        }

        // Download and convert
        let localURL = try await downloadAndConvert(trackId: trackId, streamData: streamData)
        cache[trackId] = localURL

        return try AVAudioFile(forReading: localURL)
    }

    private func downloadAndConvert(
        trackId: String,
        streamData: CachedStreamData
    ) async throws -> URL {
        // 1. Download to temp file
        // 2. Convert AAC/MP3 -> PCM using AVAudioConverter
        // 3. Save to cache directory
        // ...
    }
}
```

### Phase 3: Audio Analysis

**Goal**: Enable real-time audio analysis for smart transitions.

**Implementation**: Install taps on player nodes.

```swift
final class AudioAnalyzer {
    func analyzeLoudness(buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return -100 }

        var sumSquares: Float = 0
        let frameLength = Int(buffer.frameLength)

        for i in 0..<frameLength {
            sumSquares += samples[i] * samples[i]
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        return 20 * log10(rms)  // Convert to dB
    }

    func installAnalysisTap(on player: AVAudioPlayerNode) {
        let format = player.outputFormat(forBus: 0)

        player.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            let loudness = self?.analyzeLoudness(buffer: buffer) ?? -100
            // Store/emit loudness data
        }
    }
}
```

### Phase 4: Transition Planning

**Goal**: Generate intelligent TransitionPlans based on analysis.

```swift
final class TransitionPlanner {
    func createPlan(
        outgoing: AudioAnalysisResult,
        incoming: AudioAnalysisResult,
        preferences: MixPreferences
    ) -> TransitionPlan {
        // Calculate optimal fade duration
        let baseDuration = preferences.crossfadeSeconds
        let adjustedDuration = adjustForContent(
            base: baseDuration,
            outgoing: outgoing,
            incoming: incoming
        )

        // Calculate loudness matching
        let loudnessDelta = incoming.integratedLUFS - outgoing.integratedLUFS
        let gainAdjust = -loudnessDelta / 2  // Split the difference

        // Calculate beat alignment (if enabled)
        var beatOffset: Double? = nil
        if preferences.beatSync != .none,
           let incomingBPM = incoming.bpm,
           let outgoingBPM = outgoing.bpm,
           abs(incomingBPM - outgoingBPM) < 5 {  // Similar tempo
            beatOffset = calculateBeatAlignment(outgoing: outgoing, incoming: incoming)
        }

        return TransitionPlan(
            outgoingTrackId: outgoing.trackId,
            incomingTrackId: incoming.trackId,
            fadeOutStartTime: outgoing.outroStartTime ?? (outgoing.duration - adjustedDuration),
            fadeDuration: adjustedDuration,
            incomingStartOffset: beatOffset ?? 0,
            fadeType: .equalPower,
            outgoingEQCurve: preferences.djPolish ? createOutgoingEQ() : nil,
            incomingEQCurve: preferences.djPolish ? createIncomingEQ() : nil,
            outgoingGainAdjust: gainAdjust,
            incomingGainAdjust: -gainAdjust,
            beatAlignmentOffset: beatOffset,
            syncMode: preferences.beatSync,
            confidence: calculateConfidence(outgoing: outgoing, incoming: incoming),
            analysisAvailable: true
        )
    }
}
```

---

## Fallback Strategy

AVAudioEngine can fail in rare cases (audio route changes, interruptions). We need graceful fallback:

```swift
final class MixAudioEngine {
    weak var delegate: MixAudioEngineDelegate?

    private func handleEngineConfigurationChange() {
        // AVAudioEngine posts this notification when audio route changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleConfigChange() {
        // Try to restart
        do {
            try engine.start()
        } catch {
            // Fall back to AVPlayer
            delegate?.mixEngineDidFail(self, error: error)
        }
    }
}

// In PlaybackCoordinator:
func mixEngineDidFail(_ engine: MixAudioEngine, error: Error) {
    logWarning("AVAudioEngine failed, falling back to AVPlayer: \(error)")
    isUsingMixMode = false

    // Continue playback with AVPlayer
    if let context = currentContext {
        Task {
            await startPlayback(with: context)  // Uses AVPlayer path
        }
    }
}
```

---

## Performance Considerations

### Memory Management

| Item | Memory | Strategy |
|------|--------|----------|
| AVAudioFile (per track) | ~few KB (just metadata) | Keep N+1, N+2 in memory |
| Audio buffers (if buffering) | ~1-5 MB per track | Use ring buffer, limit to 30s |
| Analysis results | ~1 KB per track | Cache in memory, persist to disk |

### CPU Impact

| Operation | CPU | Mitigation |
|-----------|-----|------------|
| Playback | Low (hardware accelerated) | - |
| EQ processing | Low-Medium | Limit to 3 bands |
| Analysis taps | Medium | Run on background queue |
| BPM detection | High (during analysis) | Pre-analyze, cache results |

### Threading Model

```
Main Thread:
- UI updates
- State changes
- Scheduling decisions

Audio Thread (AVAudioEngine):
- Actual audio processing
- EQ application
- Volume ramping

Background Thread:
- Audio analysis (tap callbacks)
- File downloads
- Format conversion
```

---

## Testing Strategy

### Unit Tests

- TransitionPlan generation
- Loudness calculation
- Beat alignment math
- EQ curve generation

### Integration Tests

- AVAudioEngine graph construction
- File caching and conversion
- Crossfade execution

### Manual Testing

- Various audio formats (AAC, MP3, FLAC)
- Long tracks, short tracks
- Rapid skip during crossfade
- Audio route changes (Bluetooth, AirPlay)
- Background/foreground transitions

---

## References

### Apple Documentation
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)
- [AVAudioUnitEQ](https://developer.apple.com/documentation/avfaudio/avaudiouniteq)

### Tutorials
- [Kodeco: AVAudioEngine Tutorial](https://www.kodeco.com/21672160-avaudioengine-tutorial-for-ios-getting-started)
- [Metova: Audio Manipulation Using AVAudioEngine](https://metova.com/audio-manipulation-using-avaudioengine/)
- [Streaming Audio with AVAudioEngine](https://www.syedharisali.com/articles/streaming-audio-with-avaudioengine/)

### Sample Code
- [Apple AVAEMixerSample (Swift)](https://github.com/ooper-shlab/AVAEMixerSample-Swift)
- [AVAudioEngine GitHub Topics](https://github.com/topics/avaudioengine)

---

## Appendix: expansion.md Level Mapping

| Level | Feature | AVAudioEngine Component |
|-------|---------|------------------------|
| 0 | Clean queueing | AVAudioPlayerNode scheduling |
| 1 | Simple crossfade | AVAudioMixerNode volume + EQ |
| 2 | Smart length | AudioAnalyzer + TransitionPlanner |
| 3 | Beat-aligned | AVAudioTime sample-accurate scheduling |
| 4 | Key-aware | FFT analysis (future) |
| 5 | Phrase-aware | Energy envelope analysis |
| 6 | DJ polish | AVAudioUnitEQ curves during fade |
