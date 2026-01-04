# Accumulated Learnings

This file is automatically updated after each coding session.
The SessionEnd hook triggers `/retrospective` which analyzes the session and adds new learnings here.

---

## Patterns (What Works)

Successful approaches and code patterns that should be reused.

### State Management
- Use `@Observable` macro (Swift 5.9+) for observable classes, not `ObservableObject`
- Pass managers via `.environment(Manager.shared)` in the view hierarchy
- Access in views via `@Environment(ManagerType.self) private var manager`

### SwiftUI View Structure
```swift
struct MyView: View {
    @State private var localState = false
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Title")
                .task { await loadData() }
        }
    }
}
```

### Async Data Loading
- Use `.task { }` modifier for initial data loading
- Use `RefreshableScrollView` with async closure for pull-to-refresh
- Background preloading via `Task(priority: .background) { }`

### Audio Playback
- `PlaybackCoordinator.shared` handles all playback
- Use `PlayerState.shared` for UI state (current track, isPlaying, progress)
- Exponential backoff for retries (`RetryMetadata` pattern)

---

## Failures (What to Avoid)

Approaches that failed, bugs encountered, and time-wasting paths.

### AVPlayer Buffering
- NEVER set `automaticallyWaitsToMinimizeStalling = false` - causes random pauses
- Always set `preferredForwardBufferDuration` to prevent micro-stalls (10 seconds used in this codebase)

### Deprecated Patterns
- Don't use `ObservableObject` + `@Published` - use `@Observable` macro instead
- Don't use completion handlers - use async/await

---

## Edge Cases

Tricky scenarios and non-obvious behaviors discovered during development.

### SoundCloud API
- Track duration is in milliseconds - divide by 1000 for seconds
- Artwork URLs use `t500x500` by default - use `String.upgradeArtworkQuality()` for higher resolution
- Stream URLs require OAuth token in Authorization header for direct CDN access

### Queue Management
- Tracks are removed from queue when they start playing (see `handleTrackStartedPlaying`)
- Queue index becomes -1 after track is removed from queue
- Use `QueueManager.indexOfTrack(withId:)` to find current position
- Queue removal is async - track may still be in queue briefly after playback starts
- "Next" always means top of queue (`queue.peek()`), not queue index + 1

---

## Technology Insights

Framework-specific knowledge, library quirks, and API insights.

### Convex Backend
- Three operation types: `query` (read), `mutation` (write), `action` (side effects/external APIs)
- All responses wrapped in `ConvexResponse<T>` with `status` and `value` fields
- Use `forceRefresh: true` parameter to bypass cache

### SwiftUI iOS 18 Features
- `@Observable` macro replaces ObservableObject
- `Tab` view with `.tabViewBottomAccessory` for mini player
- `.navigationTransition(.zoom(sourceID:in:))` for matched transitions
- `.matchedTransitionSource(id:in:)` for transition sources

### AVAudioEngine (Mix Mode)
- Used for crossfade playback via `MixPlaybackEngine`
- Supports configurable crossfade duration, prewarm time, and fade curves
- Falls back to regular AVPlayer on failure

---

## Conventions

Project-specific coding conventions and style guidelines.

### File Organization
- One primary type per file, file named after the type
- Related extensions can be in the same file
- Views organized by feature in `Views/` subdirectories

### Naming
- Types: PascalCase (`PlaybackCoordinator`, `TrackRow`)
- Properties/methods: camelCase (`currentTrack`, `playNext()`)
- Private properties: prefixed with nothing special, just `private`

### SwiftUI Conventions
- Use `@ViewBuilder` for computed properties returning views
- Use `private var` for sub-views extracted from body
- Include both light and dark mode `#Preview` blocks

### Error Handling
- Define typed error enums (e.g., `ConvexError`, `PlayerState.PlaybackError`)
- Implement `LocalizedError` with `errorDescription` for user-facing messages
- Use `async throws` pattern, catch at call site

### Haptic Feedback
```swift
// Light tap (buttons)
HapticManager.light()

// Medium impact (important actions)
HapticManager.medium()

// Selection change (tab switches, list selections)
HapticManager.selection()
```

---

## Metal / GPU Programming

Insights from implementing Metal shaders and GPU-based effects.

### MTKView Texture Loading Race Condition
- **Context**: When using MTKView with UIViewRepresentable for image morphing
- **Learning**: The first `draw(in:)` call often happens before textures are loaded. If you return early without drawing, uninitialized GPU buffer memory may show (appears as red/garbage colors). Always explicitly clear to transparent when textures aren't ready.
- **Example**:
```swift
guard let fromTexture = fromTexture, let toTexture = toTexture else {
    // DON'T just return - clear to transparent
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
        encoder.endEncoding()
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
    return
}
```
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### MTKView Transparency Setup
- **Context**: Making MTKView content properly transparent for layering
- **Learning**: Must set multiple properties: `isOpaque = false`, `backgroundColor = .clear`, `framebufferOnly = false`. The clearColor in render pass must also have alpha = 0.
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### Layer Behind GPU Views for Seamless Transitions
- **Context**: SwiftUI conditionally rendering Metal views during animations
- **Learning**: Always layer the "destination" content behind GPU views. When the GPU view is removed (conditional becomes false), the correct content is already visible - prevents flicker.
- **Example**:
```swift
ZStack {
    // Base layer - destination artwork always visible
    PlayerArtworkView(artwork: destinationArtwork)

    // Overlay - Metal morph only during transition
    if isTransitioning {
        MetalMorphView(from: currentArtwork, to: destinationArtwork)
    }
}
```
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

---

## SwiftUI State Synchronization

### DisplayedTrack vs PlayerState.currentTrack Race Condition
- **Context**: Carousel UI state (`displayedTrack`) vs actual playback state (`playerState.currentTrack`)
- **Learning**: During crossfade completion, `isCrossfading` becomes false before `displayedTrack` updates via `.onChange`. Using `playerState.currentTrack.artwork` instead of `displayedTrack.artwork` prevents the brief flicker to old artwork.
- **Example**:
```swift
// BAD - uses displayedTrack which may be stale
artwork: track.artwork  // where track = displayedTrack

// GOOD - uses playerState which is already updated
artwork: playerState.crossfadeNextTrack?.artwork ?? playerState.currentTrack.artwork
```
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### Progress Bar Interpolation During Crossfade
- **Context**: Audio crossfade where playback position jumps from end of track A to start of track B
- **Learning**: Interpolate both position and duration during crossfade to create smooth progress bar transition. Formula: `displayedPosition = outgoingPosition * (1 - progress) + incomingPosition * progress`
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### Carousel State Order of Operations
- **Context**: Swipeable carousel with displayedNext/displayedPrevious mirroring queue state
- **Learning**: When swiping to next track, update `displayedNext` AFTER popping from queue, not before. Reading queue.peek() before the pop returns the current item (about to be removed) instead of the true next item.
- **Example**:
```swift
// BAD - reads queue before mutation
let newCurrent = displayedNext
displayedNext = queue.peek()  // Still returns old value!
onNext()  // Queue mutated here

// GOOD - read from queue after mutation
let newCurrent = displayedNext
onNext()  // Queue mutated first
displayedNext = queue.peek()  // Now returns correct next
```
- **Session**: Queue carousel sync fix (2026-01-03)

### Direct Queue Access vs Passed Props
- **Context**: UI components receiving `nextTrack`/`previousTrack` as props vs reading from QueueManager
- **Learning**: Props passed from parent may be stale during rapid interactions. For carousel/gesture-driven UI that needs real-time queue state, read directly from `queueManager.queue.peek()` rather than relying on props that may be one render cycle behind.
- **Session**: Queue carousel sync fix (2026-01-03)

---

## Metal Shader Tips

### Liquid Morph Effect Pattern
- **Context**: Creating visually appealing image transitions
- **Learning**: FBM (Fractional Brownian Motion) noise-based displacement + crossfade creates a "liquid morph" effect. The displacement amplitude should peak at mid-transition (progress = 0.5), so images appear to transform rather than just dissolve.
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### Background Metal View Optimization
- **Context**: Using Metal for blurred background effects
- **Learning**: For heavily blurred backgrounds, consider using SwiftUI opacity crossfade instead of Metal - simpler, more reliable, and the blur hides most detail anyway. Reserve Metal for where the effect is clearly visible.
- **Session**: Metal artwork crossfade morph implementation (2026-01-01)

### Always Add Solid Base Layer in Background ZStacks
- **Context**: Multi-layer blurred backgrounds with crossfade transitions
- **Learning**: When compositing multiple semi-transparent or blurred layers (especially with dark artwork), always add a solid `Color.black.ignoresSafeArea()` as the bottommost layer. Without it, when all layers have low opacity (dark artwork + crossfade), uninitialized GPU memory (red/magenta garbage) bleeds through. This is especially problematic during crossfade where opacity values interpolate through low values.
- **Example**:
```swift
ZStack {
    // CRITICAL: Solid base prevents GPU garbage from showing
    Color.black
        .ignoresSafeArea()

    // Layer 1: Stable background (fades out during crossfade)
    PlayerBackgroundView(artwork: currentArtwork)
        .blur(radius: 60)
        .opacity(isCrossfading ? 1.0 - crossfadeProgress : 1.0)

    // Layer 2: Incoming background (fades in during crossfade)
    if isCrossfading {
        PlayerBackgroundView(artwork: nextArtwork)
            .blur(radius: 60)
            .opacity(crossfadeProgress)
    }
}
```
- **Session**: Dark artwork crossfade red flash fix (2026-01-01)

---

## Architecture Insights

### PlaybackCoordinator "Top of Cue" Policy
- **Context**: Determining which track to play next in queue-based playback
- **Learning**: `playNext()` always selects `queueManager.queueTracks.first` (top of queue), NOT the next index after current. The currently playing track is removed from queue, so "next" is always index 0. Contains defensive check: if current track somehow still at index 0, skip to index 1.
- **Session**: Queue architecture research (2026-01-03)

### Parallel Subagent Research Pattern
- **Context**: Understanding complex multi-repo systems (iOS + Convex backend)
- **Learning**: Launch 5+ subagents in parallel with specific focus areas (QueueManager, PlaybackCoordinator, UI mutations, Convex mutations, Convex schema) to build comprehensive understanding quickly. Each agent returns detailed documentation that can be synthesized.
- **Session**: Queue architecture research (2026-01-03)

---

## GRDB / Local-First Architecture

### GRDB Associations Must Be in Separate File
- **Context**: Defining GRDB associations like `hasMany`, `belongsTo`, `hasOne` between models
- **Learning**: GRDB associations that reference other model types cause Swift circular reference compiler errors when defined in the same file as the model. Move ALL association definitions to a single `Associations.swift` file that imports all models.
- **Example**:
```swift
// BAD - in PersistedTrack.swift
extension PersistedTrack {
    static let playHistory = hasOne(PlayHistory.self)  // Circular reference!
}

// GOOD - in Associations.swift
extension PersistedTrack {
    static let playlistTracks = hasMany(PlaylistTrack.self)
    static let playHistory = hasOne(PlayHistory.self)
    static let likedTrack = hasOne(LikedTrack.self)
}
```
- **Session**: Local-first refactor (2026-01-04)

### Helper Structs for GRDB Association Fetching
- **Context**: Fetching records with their associations using GRDB's `.including(required:)`
- **Learning**: GRDB requires explicit helper structs when fetching records with associations. The struct property names must match the association key path names exactly.
- **Example**:
```swift
struct PlayHistoryWithTrack: Codable, FetchableRecord, Sendable {
    var playHistory: PlayHistory   // Must match table name convention
    var track: PersistedTrack      // Must match association name
}

// Usage in query
let records = try PlayHistory
    .including(required: PlayHistory.track)
    .order(PlayHistory.Columns.updatedAt.desc)
    .asRequest(of: PlayHistoryWithTrack.self)
    .fetchAll(db)
```
- **Session**: Local-first refactor (2026-01-04)

### MigratableTable Protocol Pattern
- **Context**: Registering GRDB table migrations cleanly
- **Learning**: Create a protocol that combines `TableRecord`, `FetchableRecord`, `MutablePersistableRecord` with a `createTable(table:)` static method. This allows type-safe migration registration via an `allTables` array.
- **Example**:
```swift
protocol MigratableTable: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { get }
    static func createTable(table: TableDefinition)
}

let allTables: [any MigratableTable.Type] = [
    PersistedTrack.self,
    PersistedPlaylist.self,
    PlaylistTrack.self,
    PlayHistory.self,
    LikedTrack.self,
]
```
- **Session**: Local-first refactor (2026-01-04)

### ValueObservation for Reactive UI
- **Context**: Connecting SwiftUI views to GRDB database changes
- **Learning**: Use `ValueObservation.tracking { }.values(in:)` to create async streams that update whenever the database changes. Call `observeDatabase()` from `.task` modifier - it never returns (infinite async for loop).
- **Example**:
```swift
@Observable @MainActor
final class LibraryViewModel {
    private(set) var playlists: [Playlist] = []

    func observeDatabase() async {
        let observation = ValueObservation.tracking { db in
            try PersistedPlaylist.order(Columns.lastUpdated.desc).fetchAll(db)
        }.values(in: MixBridgeDB.shared.reader)

        for try await persisted in observation {
            self.playlists = persisted.map { $0.toPlaylist() }
        }
    }
}

// In View:
.task { await viewModel.observeDatabase() }
.task { await viewModel.refresh() }  // Separate task for network sync
```
- **Session**: Local-first refactor (2026-01-04)

### OperationQueue Actor for Serial Sync
- **Context**: Preventing race conditions in database sync operations
- **Learning**: Wrap sync operations in an actor-based operation queue that chains tasks. This ensures only one sync operation runs at a time while still allowing async behavior.
- **Example**:
```swift
actor SyncOperationQueue {
    private var tail: Task<Void, Never>?

    func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let current = Task.detached { () throws -> T in
            _ = await previous?.value
            return try await operation()
        }
        tail = Task.detached { _ = try? await current.value }
        return try await current.value
    }
}
```
- **Session**: Local-first refactor (2026-01-04)

### Optimistic UI Updates with Rollback
- **Context**: Like/unlike actions that need instant UI feedback
- **Learning**: Write to local database immediately for instant UI update, then sync to backend. If backend fails, rollback the local change. ValueObservation handles all UI updates automatically.
- **Example**:
```swift
func toggleLike(track: Track) async throws {
    let wasLiked = try await db.read { try LikedTrack.fetchOne(db, key: track.id) != nil }

    // Optimistic local update
    try await db.write { db in
        if wasLiked {
            try LikedTrack.deleteOne(db, key: track.id)
        } else {
            try LikedTrack(trackId: track.id, likedAt: Date()).insert(db)
        }
    }

    // Sync to backend
    do {
        if wasLiked {
            try await convex.unlikeTrack(userId: userId, trackId: track.id)
        } else {
            try await convex.likeTrack(userId: userId, track: soundCloudTrack)
        }
    } catch {
        // Rollback on failure
        try? await db.write { db in
            if wasLiked {
                try LikedTrack(trackId: track.id, likedAt: Date()).insert(db)
            } else {
                try LikedTrack.deleteOne(db, key: track.id)
            }
        }
        throw error
    }
}
```
- **Session**: Local-first refactor (2026-01-04)

### Database as Single Source of Truth
- **Context**: Eliminating PreloadedDataStore and in-memory caching
- **Learning**: With GRDB, the database becomes the single source of truth. Network syncs write to the database, and ValueObservation automatically updates all observing views. This eliminates complex cache invalidation logic and provides offline support for free.
- **Session**: Local-first refactor (2026-01-04)

### Swift Package Module Separation for GRDB Circular References
- **Context**: When GRDB model types with protocol conformances cause Swift circular reference errors in a single module
- **Learning**: Split models into two packages: Domain (pure Swift structs, no GRDB) and DB (GRDB extensions with `@retroactive` conformances). This mirrors the best architecture pattern. The `@retroactive` keyword tells Swift the conformance is being added to a type from another module.
- **Example**:
```swift
// MixBridgeDomain/Sources/Models/PersistedTrack.swift (no GRDB)
public struct PersistedTrack: Codable, Equatable, Sendable { ... }

// MixBridgeDB/Sources/Models/PersistedTrack+GRDB.swift
extension PersistedTrack: @retroactive TableRecord {}
extension PersistedTrack: @retroactive FetchableRecord, @retroactive MutablePersistableRecord { ... }
```
- **Session**: MixBridge GRDB refactor (2026-01-04)

### Explicit Foreign Keys in GRDB Associations
- **Context**: GRDB associations between tables with non-standard column names
- **Learning**: Always specify explicit ForeignKey when column names don't match GRDB's expected conventions (e.g., `trackId` vs `persistedTrackId`). Without this, GRDB generates incorrect SQL.
- **Example**:
```swift
// Wrong - GRDB expects "persistedTrackId"
public static let track = belongsTo(PersistedTrack.self)

// Correct - explicit foreign key
public static let track = belongsTo(PersistedTrack.self, using: ForeignKey(["trackId"]))
```
- **Session**: MixBridge playlist tracks fix (2026-01-04)

### Two-Step Query Pattern for Ordered Junction Tables
- **Context**: Fetching records through a junction table with ordering on the junction table column
- **Learning**: When ordering by a junction table column (like `position`), don't use `.joining().order()` as it creates incorrect SQL referencing the wrong table. Instead, fetch junction records first, then fetch main records and reorder in memory.
- **Example**:
```swift
// Wrong - creates "ORDER BY tracks.position" error
try PersistedTrack
    .joining(required: PersistedTrack.playlistTracks.filter(...))
    .order(PlaylistTrack.Columns.position)

// Correct - two-step fetch
let playlistTracks = try PlaylistTrack
    .filter(PlaylistTrack.Columns.playlistId == playlistId)
    .order(PlaylistTrack.Columns.position)
    .fetchAll(db)
let trackIds = playlistTracks.map(\.trackId)
let tracksDict = try PersistedTrack
    .filter(trackIds.contains(PersistedTrack.Columns.id))
    .fetchAll(db)
    .reduce(into: [:]) { $0[$1.id] = $1 }
return trackIds.compactMap { tracksDict[$0] }
```
- **Session**: MixBridge playlist ordering fix (2026-01-04)

### Public CodingKeys Required for Cross-Package GRDB
- **Context**: Swift packages with models used by GRDB extensions in another package
- **Learning**: Auto-synthesized CodingKeys are private. When GRDB extensions in another package need to reference CodingKeys for Column definitions, you must add explicit `public enum CodingKeys` to the model in the Domain package.
- **Session**: MixBridge package build errors (2026-01-04)

---

## Failures (What to Avoid) - GRDB Specific

### Don't Try Random Protocol Conformance Patterns for Circular References
- **Context**: Swift circular reference errors with GRDB protocol conformances in a single module
- **Learning**: When circular references occur with GRDB models in a single module, the ONLY fix is module separation. Failed approaches that wasted significant time:
  - Consolidating extensions into single extension
  - Using computed properties for associations
  - Making `allTables` a computed var instead of let
  - Removing Sendable conformance
  - Various extension orderings
  - Moving associations to separate file (within same module)
- **Session**: MixBridge GRDB refactor (2026-01-04)

### Don't Use hasLoaded with Empty Check Logic
- **Context**: ViewModel state management for data loading
- **Learning**: Logic like `var hasLoaded: Bool { !items.isEmpty || (!isLoading && error == nil) }` is flawed - it returns true initially when items is empty, preventing first load from ever triggering. Use explicit `hasAttemptedLoad` flag set after first attempt.
- **Session**: MixBridge playlist loading bug (2026-01-04)

### Don't Use Multiple .task Modifiers for Related Operations
- **Context**: SwiftUI views needing to start observation and fetch data
- **Learning**: Multiple `.task` modifiers can cause race conditions. Combine related async operations in a single `.task` using `async let` for concurrent execution.
- **Example**:
```swift
// Bad - race conditions between observation and fetch
.task { await viewModel.observeDatabase() }
.task { await viewModel.refresh() }

// Good - combined with proper ordering
.task {
    async let observe: () = viewModel.observeDatabase()
    await viewModel.refresh()
    await observe
}
```
- **Session**: MixBridge view loading fixes (2026-01-04)

---

## Sync Engine Architecture

**See [sync-engine.md](sync-engine.md) for comprehensive documentation.**

### History Sync Aggregation Bug Fix
- **Context**: `syncHistory()` was incrementing `playCount` for every API record, causing overcounting
- **Learning**: When backend returns multiple history entries for the same track, aggregate them first before saving. The naive approach of incrementing `playCount` for each record causes N plays of the same track to result in playCount = N * existingCount instead of playCount = N.
- **Fix**: Create aggregation map keyed by trackId, count occurrences, then save once per unique track with accurate count.
- **Example**:
```swift
// Bad - increments per record (overcounts)
for playItem in history {
    if let existing = try PlayHistory.fetchOne(db, key: trackId) {
        historyRecord = existing
        historyRecord.playCount += 1  // Adds 1 for EACH api record!
    }
}

// Good - aggregate first, then save
var aggregated: [String: AggregatedHistory] = [:]
for playItem in history {
    let trackId = String(playItem.trackData.id)
    if var existing = aggregated[trackId] {
        existing.playCount += 1
        aggregated[trackId] = existing
    } else {
        aggregated[trackId] = AggregatedHistory(playCount: 1, ...)
    }
}
// Then save aggregated counts once per track
for (trackId, agg) in aggregated {
    historyRecord.playCount = max(existing.playCount, agg.playCount)
}
```
- **Session**: Sync engine review (2026-01-04)

### Sync Must Handle Deletions
- **Context**: `PlaylistSync.syncPlaylists` only upserted, never deleted playlists removed from backend
- **Learning**: Full sync operations must handle three cases: add new, update existing, AND delete removed. Compare local IDs vs backend IDs and remove the difference.
- **Pattern**: Same as `LikedSync.syncLikedTracks` which correctly removes unliked tracks
- **Example**:
```swift
let currentLocalIds = try Model.fetchAll(db).map(\.id)
let newIds = Set(backendItems.map { $0.id })

// Remove items no longer in backend
for id in currentLocalIds where !newIds.contains(id) {
    try Model.deleteOne(db, key: id)
}

// Add/update items
for item in backendItems {
    try item.upsert(db)
}
```
- **Session**: Sync engine review (2026-01-04)

### Module Loading Pattern (Swift Package Manager)
- **Context**: Organizing GRDB models to avoid circular references
- **Learning**: Use two-package pattern: Domain (pure Swift models) + DB (GRDB extensions with `@retroactive` conformances). Re-export both from DB package for convenience.
- **Key files**:
  - `Packages/MixBridgeDomain/` - Pure Codable structs, no external deps
  - `Packages/MixBridgeDB/` - GRDB extensions, migrations, associations
- **Re-export pattern**:
```swift
// In MixBridgeDB.swift
@_exported import GRDB
@_exported import MixBridgeDomain
```
- **Session**: Sync engine review (2026-01-04)

---

## SwiftUI Performance

### State vs Computed Properties for Expensive Derived Data
- **Context**: SwiftUI views with expensive computed properties that recalculate on every render
- **Learning**: Use `@State` with `.onChange` instead of computed properties for derived data that's expensive to compute. Computed properties run on every body evaluation.
- **Example**:
```swift
// Bad - recalculates on every render, causes glitching
private var artists: [ArtistInfo] {
    viewModel.likedTracks.map { ... } // expensive grouping operation
}

// Good - only updates when source changes
@State private var artists: [ArtistInfo] = []
.onChange(of: viewModel.likedTracks) { _, newTracks in
    artists = buildArtists(from: newTracks)
}
```
- **Session**: MixBridge artists view fix (2026-01-04)
