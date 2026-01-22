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

### Claude Code Subagent Naming
- Plugin-provided subagents use double-namespace format: `plugin-name:agent-name` (e.g., `code-simplifier:code-simplifier`)
- Built-in agents use simple names: `Explore`, `Plan`, `Bash`, `general-purpose`
- When Task tool fails with "Agent type not found", check the full list of available agents in the error message

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

### GRDB sum() Returns Int, Not Int64
- **Context**: Using GRDB's `select(sum(Column))` for aggregate queries where the result is assigned to an `Int64` property
- **Learning**: GRDB's `sum()` aggregate infers Swift `Int` by default, even when summing `Int64` columns like `fileSize`. If the receiving struct/parameter expects `Int64`, you must explicitly cast: `Int64(totalSize)`.
- **Example**:
```swift
// Query returns Int
let totalSize: Int = try DownloadedTrack.select(sum(DownloadedTrack.Columns.fileSize)).fetchOne(db) ?? 0

// If DownloadedPlaylistInfo.totalFileSize is Int64, must cast
DownloadedPlaylistInfo(
    ...
    totalFileSize: Int64(totalSize)  // Explicit cast required
)
```
- **Session**: Download manager Int64 fix (2026-01-12)

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

### Don't Use AVAssetExportSession for HLS with Per-Segment Auth
- **Context**: Downloading HLS streams where each segment requires authentication
- **Learning**: `AVAssetExportSession` cannot be used to download HLS streams when OAuth headers are required for segment requests. The headers only apply to the manifest, causing segment requests to fail with auth errors. The asset appears to load (`isPlayable: true`) but has 0 tracks.
- **What to do instead**: Use progressive streams when available, or `AVAssetDownloadURLSession` for true HLS offline.
- **Session**: HLS offline download implementation (2026-01-10)

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

## SwiftUI Text Effects

### Simplified Animated Text Pattern
- **Context**: Creating animated text with shine/glow effects that don't require full glass material
- **Learning**: Instead of using `glassEffect` (which requires invisible text + glass modifier), layer a simple `Text` with `foregroundStyle(.white.opacity(0.7))` underneath a masked `ShineLayer`. This is simpler, has fewer dependencies, and renders faster.
- **Example**:
```swift
// Simpler approach - opacity-based base text
ZStack {
    Text(text)
        .font(Font(font))
        .foregroundStyle(.white.opacity(0.7))

    ShineLayer(progress: progress)
        .mask(TextToShape(value: text, font: font))
}

// More complex approach - glass effect
ZStack {
    ShineLayer(progress: progress)
        .mask(TextToShape(value: text, font: font))

    Text(text)
        .font(Font(font))
        .opacity(0)  // Hidden text, glass shows
        .glassEffect(.clear, in: TextToShape(value: text, font: font))
}
```
- **Session**: MixingIndicator simplification (2026-01-09)

### Prefer SwiftUI Font over UIFont for Cross-Platform
- **Context**: Text components using `UIFont` for font specification
- **Learning**: Use SwiftUI `Font` type (`.system(size:weight:)` or `.custom("name", size:)`) instead of `UIFont.systemFont()` when possible. This removes UIKit dependency and is more idiomatic for SwiftUI components.
- **Session**: Text components refactor (2026-01-09)

---

## HLS / Audio Streaming

### HLS OAuth Headers Only Apply to Manifest, Not Segments
- **Context**: Downloading HLS streams that require OAuth authentication
- **Learning**: When using `AVURLAsset` with `AVURLAssetHTTPHeaderFieldsKey` to add OAuth headers, the headers are ONLY applied to the initial HLS manifest (`.m3u8`) request, not to the subsequent segment (`.ts`) requests. This causes `AVFoundation` to report 0 tracks because segments fail to load.
- **Diagnosis**: Error `-12939` (HTTP auth error) and `-12174` (asset inspection failed) in console logs while `isPlayable` returns `true` indicates this exact issue.
- **Session**: HLS offline download implementation (2026-01-10)

### AVAssetExportSession Cannot Export Protected HLS Without Full Download
- **Context**: Attempting to use `AVAssetExportSession` to convert HLS to M4A for offline storage
- **Learning**: `AVAssetExportSession` reads HLS streams progressively and cannot export unless all segments are accessible. If authentication fails on segments (see above), the asset loads with 0 tracks and export fails with "No audio track found".
- **Session**: HLS offline download implementation (2026-01-10)

### Check for Progressive Stream URLs Before HLS
- **Context**: Implementing offline downloads for streaming services like SoundCloud
- **Learning**: Many streaming services offer both HLS and progressive (direct HTTP) stream URLs. Progressive URLs are much simpler to download - just a standard `URLSession.download()` with OAuth headers. Check if the stream URL contains `/http` or lacks `.m3u8` to identify progressive streams.
- **Example**:
```swift
func isProgressiveStream(_ url: URL) -> Bool {
    let path = url.path.lowercased()
    return !path.contains(".m3u8") || path.contains("/http")
}

// Progressive download is simple
var request = URLRequest(url: streamURL)
request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
let (localURL, _) = try await URLSession.shared.download(for: request)
```
- **Session**: HLS offline download implementation (2026-01-10)

### SoundCloud Stream Types and Authentication
- **Context**: Working with SoundCloud API stream URLs
- **Learning**: SoundCloud provides two stream types: `/hls` (HLS manifest) and `/http` (progressive AAC). Both require OAuth headers, but progressive URLs work with simple `URLSession.download()` while HLS requires `AVAssetDownloadURLSession` with proper delegate setup. When the URL is resolved through the API, CDN URLs use query param auth instead.
- **Session**: HLS offline download implementation (2026-01-10)

### HLS Diagnostic Pattern for Debugging Downloads
- **Context**: Debugging why HLS downloads fail
- **Learning**: Build a diagnostic function that logs key `AVURLAsset` properties: `isPlayable`, `hasProtectedContent`, track count (with and without headers), and `isExportable`. This quickly identifies whether the issue is DRM, authentication, or URL problems.
- **Key checks**:
  - `isPlayable: false` = URL or auth issue
  - `hasProtectedContent: true` = DRM, need FairPlay
  - `tracks.count: 0` = Segment authentication failing
  - `isExportable: false` = Cannot be converted offline
- **Session**: HLS offline download implementation (2026-01-10)

### For True HLS Offline, Use AVAssetDownloadURLSession
- **Context**: When progressive streams are not available and HLS is required
- **Learning**: Apple's official API for HLS offline download is `AVAssetDownloadURLSession`, not `AVAssetExportSession`. It handles segment authentication properly and stores the asset in a format AVPlayer can play offline. See Apple sample code: "Using AVFoundation to play and persist HTTP live streams".
- **Session**: HLS offline download implementation (2026-01-10)

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

---

## SwiftUI List Styling for Apple Music-Style UIs

### Use Native List with InsetGroupedListStyle Over Custom VStack
- **Context**: Creating track picker UIs that need to match Apple Music's visual style
- **Learning**: Don't build custom VStack/LazyVStack layouts with manual dividers and backgrounds. Use SwiftUI's native `List` with `.listStyle(InsetGroupedListStyle())` and `.listSectionSpacing()` for proper section spacing. This provides automatic dark mode support, proper touch targets, and consistent styling.
- **Example**:
```swift
// Bad - manual layout that doesn't match Apple Music
VStack(spacing: 0) {
    ForEach(items) { item in
        Row(item)
        Divider()
    }
    .background(Color(.secondarySystemGroupedBackground))
}

// Good - native List with proper styling
List {
    Section {
        ForEach(items) { item in
            Row(item)
        }
    }
}
.listStyle(InsetGroupedListStyle())
.listSectionSpacing(16)
```
- **Session**: Playlist track picker UI refinement (2026-01-13)

### Background Blending with .listRowBackground
- **Context**: Making certain List sections blend into the background while keeping others styled
- **Learning**: Use `.listRowBackground(Color.clear)` to make specific sections blend into the system background. Apply this selectively to sections that should appear "flat" while keeping other sections with the grouped background.
- **Session**: Playlist track picker UI refinement (2026-01-13)

### Dynamic Navigation Title for Selection Count
- **Context**: Showing selection count in navigation title like Apple Music does
- **Learning**: Use a computed property for `navigationTitle` that reflects current selection state: "Add to 'Playlist Name'" when empty, "X songs added to 'Playlist Name'" when tracks are selected. Quote the playlist name for clarity.
- **Example**:
```swift
private var navigationTitle: String {
    let count = viewModel.selectedCount
    if count == 0 {
        return "Add to \"\(viewModel.playlistName)\""
    } else {
        let songText = count == 1 ? "song" : "songs"
        return "\(count) \(songText) added to \"\(viewModel.playlistName)\""
    }
}
```
- **Session**: Playlist track picker UI refinement (2026-01-13)

---

## UI Iteration Workflow

### Rapid UI Refinement Through Screenshot Feedback
- **Context**: Iterating on UI designs with user providing screenshots
- **Learning**: When user provides screenshots showing issues, make incremental changes rather than large rewrites. Address one visual concern at a time (icon colors, background blending, spacing) and verify each change before moving on. This prevents regression and allows quick course correction.
- **Session**: Playlist track picker UI refinement (2026-01-13)

### Colorful vs White Icons in Selection UIs
- **Context**: Icon styling for library navigation rows in selection contexts
- **Learning**: In playlist/track selection UIs, use white icons with consistent styling rather than colorful filled icons. The colorful icons can be distracting when the focus should be on track selection. Use `.foregroundStyle(.white)` consistently.
- **Session**: Playlist track picker UI refinement (2026-01-13)

---

## SwiftUI Sheet and Dialog Patterns

### Use confirmationDialog for Deletion Instead of Tooltip
- **Context**: Confirmation UI for destructive actions like playlist deletion
- **Learning**: Don't use custom tooltip views for confirmation dialogs. Use SwiftUI's native `.confirmationDialog()` modifier which provides a standard iOS bottom sheet with proper accessibility, animation, and theming.
- **Example**:
```swift
.confirmationDialog(
    "Delete Playlist",
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        performDelete()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Are you sure you want to delete this playlist?")
}
```
- **Session**: Playlist deletion confirmation fix (2026-01-13)

### Camera Icon Placeholder for Image Upload
- **Context**: Allowing users to upload custom playlist artwork
- **Learning**: For image upload placeholders, center a camera icon (`camera.fill`) within the placeholder area. Make the entire area tappable to trigger image picker. Don't combine with existing placeholder imagery - the camera icon alone indicates the action clearly.
- **Session**: Playlist creation image upload (2026-01-13)

---

## Section Spacing and Padding

### listSectionSpacing vs Individual Padding
- **Context**: Adding padding around List sections
- **Learning**: Use `.listSectionSpacing(16)` at the List level for consistent section spacing. For internal section padding (top/bottom of content within a section), use `.listRowInsets()` or wrap content in a container with padding. Note: Applying padding to individual rows may create unwanted spacing between all items.
- **Session**: Playlist track picker UI refinement (2026-01-13)

---

## SwiftUI Dependency Injection Refactoring

### Replace Singleton Access with @Environment for @Observable Types
- **Context**: Migrating from `PlayerState.shared` or `DownloadManager.shared` direct access to proper dependency injection
- **Learning**: For `@Observable` classes, use `@Environment(TypeName.self)` injection pattern. For `ObservableObject` classes that can't migrate to `@Observable`, use `@EnvironmentObject`. Inject at app root via `.environment(Singleton.shared)` or `.environmentObject(Singleton.shared)`.
- **Example**:
```swift
// Before (tight coupling to singleton)
private var playerState = PlayerState.shared
PlayerState.shared.play(track: track)

// After (dependency injection)
@Environment(PlayerState.self) private var playerState
playerState.play(track: track)

// At app root (mixbridgeApp.swift)
.environment(PlayerState.shared)
.environmentObject(DownloadManager.shared)
```
- **Benefits**: Easier testing, preview support, and clearer data flow
- **Session**: PR01-PR02 PlayerState/DownloadManager environment injection (2026-01-14)

### @Bindable Required for Two-Way Binding with @Environment
- **Context**: Using `@Binding` or `$property` syntax with `@Environment`-injected `@Observable` objects
- **Learning**: `@Environment` provides read-only access. For two-way bindings, create a local `@Bindable` copy inside the body or function scope.
- **Example**:
```swift
@Environment(PlayerState.self) private var playerState

var body: some View {
    @Bindable var playerState = playerState  // Enable $binding syntax

    Slider(value: $playerState.playbackPosition)
}
```
- **Session**: PR01 ExpandedMusicPlayer bindings (2026-01-14)

---

## SwiftUI ForEach Stability

### IndexedRow Pattern for Stable ForEach Identity
- **Context**: Using `ForEach(Array(collection.enumerated()), id: \.element.id)` causes re-renders when indices change
- **Learning**: Create a dedicated `IndexedRow<Item>` wrapper that derives its `id` from the item, not the tuple. This prevents row recreation when items are added/removed from other positions in the list.
- **Example**:
```swift
// Utility type (IndexedRow.swift)
struct IndexedRow<Item: Identifiable>: Identifiable {
    let item: Item
    let index: Int
    var id: Item.ID { item.id }  // Identity from item, not index
}

extension Collection where Element: Identifiable {
    func indexedRows() -> [IndexedRow<Element>] {
        enumerated().map { IndexedRow(item: $0.element, index: $0.offset) }
    }
}

// Usage in views
let rows = items.indexedRows()
ForEach(rows) { row in
    TrackRow(row.item, number: row.index + 1)
}
```
- **Why it matters**: The standard `enumerated()` pattern uses a tuple `(offset, element)` where the index is part of identity, causing full row recreation on any collection mutation.
- **Session**: PR03 Stable ForEach rows (2026-01-14)

### Pre-compute IndexedRows in ViewModel for Performance
- **Context**: Large lists where `.indexedRows()` is called in body
- **Learning**: For frequently updated collections, pre-compute `indexedRows` in the ViewModel and expose as a separate published property. Update it atomically when the source collection changes.
- **Example**:
```swift
@Observable final class PlaylistDetailViewModel {
    private(set) var trackItems: [TrackItem] = []
    private(set) var trackRows: [IndexedRow<TrackItem>] = []

    func handleUpdate(_ items: [TrackItem]) {
        trackItems = items
        trackRows = items.indexedRows()  // Pre-computed
    }
}
```
- **Session**: PR03 ViewModels pre-computing rows (2026-01-14)

---

## SwiftUI Task Consolidation

### Consolidate Multiple .task Modifiers Using async let
- **Context**: Views with multiple `.task { }` modifiers for observation and data fetching
- **Learning**: Multiple `.task` modifiers can cause race conditions and unnecessary complexity. Consolidate into a single `.task(id:)` using `async let` for concurrent operations that don't depend on each other.
- **Example**:
```swift
// Before - multiple tasks, potential race conditions
.task { await viewModel.observeDatabase() }
.task { await viewModel.observePlaylistsDatabase() }
.task {
    if let userId = authManager.currentUserId {
        await viewModel.refresh(userId: userId)
    }
}

// After - single consolidated task
.task(id: authManager.currentUserId) {
    async let observeTracks: Void = viewModel.observeDatabase()
    async let observePlaylists: Void = viewModel.observePlaylistsDatabase()

    if let userId = authManager.currentUserId {
        await viewModel.refresh(userId: userId)
    }

    _ = await (observeTracks, observePlaylists)
}
```
- **Benefits**:
  - Task restarts when `id` changes (e.g., user logs out/in)
  - Clear ordering: fetches complete before awaiting observation
  - Single cancellation point
- **Session**: PR04 Consolidate screen tasks (2026-01-14)

### Use .task(id:) for User-Dependent Operations
- **Context**: Tasks that should restart when the authenticated user changes
- **Learning**: Wrap user-dependent async operations in `.task(id: authManager.currentUserId)`. The task automatically cancels and restarts when the user ID changes (login/logout).
- **Session**: PR04 Consolidate screen tasks (2026-01-14)

---

## Large File Decomposition

### Split Large Files into Extensions by Responsibility
- **Context**: Files exceeding 600+ lines with multiple distinct responsibilities
- **Learning**: Use Swift extensions in separate files to group related functionality. Name files as `TypeName+Responsibility.swift`. Keep the main file focused on core state and initialization.
- **Example** (PlayerState split into 6 files):
```
PlayerState.swift                           - Core state, init, main API
PlayerState+AudioSession.swift              - AVAudioSession setup, interruption handling
PlayerState+NowPlaying.swift                - MPNowPlayingInfoCenter updates
PlayerState+Persistence.swift               - UserDefaults save/load
PlayerState+PlaybackCoordinatorDelegate.swift - Delegate callbacks
PlayerState+RemoteCommands.swift            - MPRemoteCommandCenter setup
```
- **Key insight**: Extensions in separate files can access `internal` properties. Change `private` to `internal` (or omit access modifier) for properties needed across extensions.
- **Session**: PR09 Split PlayerState into focused files (2026-01-14)

### Decompose Complex SwiftUI Views into Subviews
- **Context**: Large view files (500+ lines) with multiple distinct sections
- **Learning**: Extract self-contained view sections into separate files. Pass only required data as parameters. Good candidates: background stacks, sheet content, reusable row types.
- **Example** (ExpandedMusicPlayer decomposition):
```swift
// Before: 800+ line ExpandedMusicPlayer.swift

// After: Split into focused views
ExpandedMusicPlayer.swift              - Main view, orchestration
ExpandedPlayerBackgroundStack.swift    - Blurred background layers
ExpandedPlayerQueueSheet.swift         - Queue sheet overlay
```
- **Session**: PR10 Decompose ExpandedMusicPlayer (2026-01-14)

---

## UI Component Deduplication

### Extract Reusable ArtworkView Component
- **Context**: Multiple views with identical artwork loading/placeholder logic
- **Learning**: Create a configurable `ArtworkView` component that handles URL loading, placeholders, corner radius, and shadows. Use parameters for customization rather than duplicating code.
- **Example**:
```swift
struct ArtworkView: View {
    let artwork: String           // URL string
    let size: CGFloat?            // nil for flexible
    let cornerRadius: CGFloat
    var placeholderIcon: String = "music-note-simple"
    var placeholderIconSize: CGFloat? = nil
    var showsProgressWhileLoading: Bool = true
    var shadow: (color: Color, radius: CGFloat, y: CGFloat)? = nil

    // Handles: URL validation, CachedAsyncImage, placeholder, shadow
}

// Usage - replaces 30+ lines of inline code
ArtworkView(
    artwork: playlist.artwork,
    size: artworkSize,
    cornerRadius: 20,
    placeholderIcon: "playlist",
    shadow: (color: .black.opacity(0.3), radius: 20, y: 10)
)
```
- **Session**: PR11 Deduplicate artwork + avatar UI components (2026-01-14)

---

## Git Rebase Conflict Resolution

### Rebase PR Branches to Incorporate Main Changes
- **Context**: PR branch conflicts with main after main receives new commits
- **Learning**: Use `git rebase origin/main` to replay PR commits on top of main. This ensures main's changes form the base and PR changes are applied cleanly on top. Force push after rebase with `git push --force-with-lease`.
- **Conflict resolution strategy**:
  1. For UI changes: Keep main's visual changes (icons, sizes), apply PR's structural changes (dependency injection, task consolidation)
  2. For component extraction: Use the new component but preserve main's placeholder icons/assets
- **Example conflict resolution**:
```swift
// Main had: Image("playlist") as placeholder
// PR had: ArtworkView(placeholderIcon: "music-note")
// Resolution: ArtworkView(placeholderIcon: "playlist")  // PR component + main's icon
```
- **Session**: Rebasing PR#66 onto main (2026-01-14)

---

## Swift Testing Patterns

### Test Data Structure Not Manager Class
- **Context**: Writing unit tests for `QueueManager` which has many external dependencies (ConvexService, KeychainManager, QueueSync, PlaybackCoordinator)
- **Learning**: When a manager class has heavy dependencies that are hard to mock, test the underlying data structure directly instead. `QueueManager` wraps `PlaybackQueue` - all queue logic (append, remove, move, peek, pop) lives in `PlaybackQueue`. Testing `PlaybackQueue` gives comprehensive coverage of queue behavior without needing to mock authentication, network services, or notification systems.
- **Example**:
```swift
// Hard to test - requires mocking 5+ dependencies
class QueueManager {
    let queue = PlaybackQueue()
    private let queueSync = QueueSync.shared
    private func requireUserId() throws -> String { ... }  // Needs KeychainManager
    func addTrack(...) async throws {
        let userId = try requireUserId()  // Auth dependency
        // ... ConvexService calls, HapticManager calls, etc.
    }
}

// Easy to test - pure data structure
class PlaybackQueue {
    func append(_ item: QueueItem) { ... }
    func pop() -> QueueItem? { ... }
    func move(from: Int, to: Int) { ... }
}

// Test the data structure
func testAppendAndPop() {
    let queue = PlaybackQueue()
    queue.append(makeQueueItem())
    XCTAssertEqual(queue.count, 1)
    let popped = queue.pop()
    XCTAssertNotNil(popped)
    XCTAssertEqual(queue.count, 0)
}
```
- **When to apply**: Any manager class where the core logic is delegated to a contained data structure
- **Session**: QueueManagerTests implementation (2026-01-22)

### Create Test Fixtures Using Minimal Valid Objects
- **Context**: Creating test data for Track and QueueItem types
- **Learning**: Create factory functions that produce minimal valid instances of complex types. Use predictable IDs (track-0, track-1) for assertion clarity. Keep fixture creation separate from test logic.
- **Example**:
```swift
// In test file or shared TestFixtures
private func makeTrack(index: Int = 0) -> Track {
    Track(
        id: "track-\(index)",
        title: "Track \(index)",
        artistName: "Artist \(index)",
        duration: 180,
        artwork: nil,
        artworkLowRes: nil
    )
}

private func makeQueueItem(index: Int = 0) -> QueueItem {
    QueueItem(
        id: "item-\(index)",
        serverId: "server-\(index)",
        trackId: "track-\(index)",
        track: makeTrack(index: index),
        soundCloudTrack: nil
    )
}

// Usage in tests - clear and predictable
let item0 = makeQueueItem(index: 0)
let item1 = makeQueueItem(index: 1)
queue.append(item0)
queue.append(item1)
XCTAssertEqual(queue.items[0].id, "item-0")
XCTAssertEqual(queue.items[1].id, "item-1")
```
- **Session**: QueueManagerTests implementation (2026-01-22)

### Test Edge Cases Systematically
- **Context**: Comprehensive queue testing requiring edge case coverage
- **Learning**: For data structures, systematically test: empty state, single item, boundary indices (0, count-1, count), invalid indices (-1, count+1), operations that should no-op (move to same index), and operations that should clamp (reinsert beyond bounds).
- **Test categories for queue-like structures**:
  1. **Initial state**: isEmpty, count, peek returns nil, pop returns nil
  2. **Single item**: append/pop round-trip, remove only item
  3. **Boundaries**: remove at index 0, remove at last index, move from 0, move to 0
  4. **Invalid inputs**: negative indices, indices beyond count
  5. **Edge behaviors**: move to same index (no-op), contains non-existent ID
  6. **Stress tests**: large number of items (100+) to verify no performance regression
- **Session**: QueueManagerTests implementation (2026-01-22)

### Build Verification for Swift Test Files
- **Context**: Verifying test files compile before committing
- **Learning**: Use `xcodebuild build-for-testing` to verify test files compile without running them. This catches syntax errors and import issues early. Specify destination and scheme explicitly.
- **Command**:
```bash
xcodebuild build-for-testing \
    -project mixbridge.xcodeproj \
    -scheme mixbridge \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    2>&1 | tail -20
```
- **Session**: QueueManagerTests implementation (2026-01-22)

### Testable Actor Pattern for Network-Dependent Actors
- **Context**: Testing Swift actors like `StreamURLCache` that have dependencies on network services (ConvexService, SpotifyStreamService)
- **Learning**: Create a "testable" actor that mirrors the production actor's interface and logic but allows direct cache manipulation. This enables testing cache behavior (hits, misses, expiration, prefetch queue) without mocking network services.
- **Key implementation details**:
  - Mirror the production actor's private state (`cache`, `inFlight`, `pendingPrefetch`, `pendingPrefetchSet`)
  - Expose methods for direct cache manipulation: `setCache(for:stream:expiresAt:)`, `simulatePrefetchEnqueue()`
  - Keep the same expiration logic and buffer constants
  - Test concurrent access patterns using `TaskGroup`
- **Example**:
```swift
// TestableStreamURLCache - mirrors StreamURLCache but testable
actor TestableStreamURLCache {
    private var cache: [String: TestCachedStream] = [:]
    private var pendingPrefetch: [(trackId: String, spotifyUrl: String?)] = []
    private var pendingPrefetchSet: Set<String> = []
    private let maxQueuedPrefetches = 50

    // Direct cache manipulation for testing
    func setCache(for trackId: String, stream: CachedStreamData, expiresAt: Date, isSpotify: Bool = false) {
        cache[trackId] = TestCachedStream(
            url: stream.url,
            streamType: stream.streamType,
            accessToken: stream.accessToken,
            cachedAt: Date(),
            expiresAt: expiresAt,
            isSpotify: isSpotify,
            spotifyUrl: nil
        )
    }

    // Test production logic without network
    func getCachedStream(for trackId: String) -> CachedStreamData? {
        guard let cached = cache[trackId] else { return nil }
        if cached.isExpired {
            cache.removeValue(forKey: trackId)
            return nil
        }
        return CachedStreamData(url: cached.url, streamType: cached.streamType, accessToken: cached.accessToken)
    }
}
```
- **Test categories enabled**:
  1. Cache hits/misses
  2. Expiration with different buffers (SoundCloud 60s, Spotify 300s)
  3. Deadline-based expiration checks
  4. Prefetch queue: enqueue, dedup, max size, batch operations
  5. Concurrent access safety via TaskGroup
- **Session**: StreamURLCacheTests implementation (2026-01-22)

### Testable Class Pattern for @MainActor Singletons
- **Context**: Testing `@MainActor` singleton classes like `DownloadManager` that depend on network, file system, and database
- **Learning**: Create a `Testable[ClassName]` class that mirrors the production class's public API but replaces dependencies with in-memory state. Unlike the actor pattern (TestableStreamURLCache), this pattern is for `@MainActor` classes where you need to test state machine transitions (downloading/downloaded/failed) and simulated file operations.
- **Key differences from actor pattern**:
  - Use `class` not `actor` since production is `@MainActor`
  - Replace file system operations with dictionary-based "simulated" files
  - Replace network downloads with direct state manipulation via `simulateDownloadComplete()`
  - Track download state transitions through the full lifecycle
- **Example**:
```swift
@MainActor
final class TestableDownloadManager {
    private var downloadStatuses: [String: DownloadStatus] = [:]
    private var simulatedFiles: [String: (url: URL, size: Int64)] = [:]  // trackId -> (localURL, fileSize)
    private var activeDownloads: Set<String> = []

    // Simulate download completion without network
    func simulateDownloadComplete(for trackId: String, fileSize: Int64 = 1024) {
        let localURL = URL(fileURLWithPath: "/simulated/\(trackId).m4a")
        simulatedFiles[trackId] = (localURL, fileSize)
        downloadStatuses[trackId] = .downloaded
        activeDownloads.remove(trackId)
    }

    // Production logic can be tested
    func storageUsed() -> Int64 {
        simulatedFiles.values.reduce(0) { $0 + $1.size }
    }
}
```
- **Test categories enabled**:
  1. State transitions: notDownloaded -> downloading -> downloaded/failed
  2. Concurrent download requests (thread safety)
  3. Storage calculations
  4. Partial file cleanup on cancel
  5. Batch operations
- **Session**: DownloadManagerTests implementation (2026-01-22)

### Test State Machine Transitions Exhaustively
- **Context**: Testing enum-based state machines like `DownloadStatus` with associated values
- **Learning**: Test every valid state transition, equality edge cases, and ensure invalid transitions are handled. For enums with associated values (like `downloading(progress: Double)` or `failed(Error)`), test equality with same/different values.
- **Key test cases for state machines**:
  1. **Equality by case**: Same case with same associated value
  2. **Inequality by value**: Same case with different associated values
  3. **Inequality by case**: Different cases
  4. **Error equality**: `failed(Error)` should equal any `failed(_)` (error type agnostic)
  5. **Valid transitions**: notDownloaded -> downloading -> downloaded
  6. **Edge transitions**: downloaded -> notDownloaded (after delete)
  7. **Failed state recovery**: failed -> downloading (retry scenario)
- **Example**:
```swift
// Test DownloadStatus equality
func testDownloadStatusEqualityDownloading() {
    let status1 = DownloadStatus.downloading(progress: 0.5)
    let status2 = DownloadStatus.downloading(progress: 0.5)
    let status3 = DownloadStatus.downloading(progress: 0.7)
    XCTAssertEqual(status1, status2)
    XCTAssertNotEqual(status1, status3)
}

func testDownloadStatusEqualityFailedIgnoresErrorType() {
    let error1 = NSError(domain: "test", code: 1)
    let error2 = NSError(domain: "test", code: 2)
    let status1 = DownloadStatus.failed(error1)
    let status2 = DownloadStatus.failed(error2)
    XCTAssertEqual(status1, status2)  // Same case, ignores error details
}
```
- **Session**: DownloadManagerTests implementation (2026-01-22)

### Concurrent Operations Testing with TaskGroup
- **Context**: Verifying thread safety for managers handling concurrent requests
- **Learning**: Use `withTaskGroup` to simulate concurrent operations (downloads, status updates, cancellations) and verify the manager handles them without crashes or data corruption. Focus on testing that concurrent requests to the same resource are handled idempotently.
- **Key concurrent scenarios**:
  1. Multiple simultaneous download requests for same track (should not duplicate)
  2. Download and cancel racing
  3. Status queries during active downloads
  4. Batch operations with concurrent single operations
- **Example**:
```swift
func testConcurrentDownloadRequests() async throws {
    let manager = TestableDownloadManager()
    let track = makeTrack()

    // Simulate 10 concurrent download requests for same track
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask { @MainActor in
                await manager.downloadTrack(track)
            }
        }
    }

    // Should result in exactly one download, not 10
    XCTAssertTrue(manager.isDownloading(trackId: track.id) || manager.isDownloaded(trackId: track.id))
    // Download count should be 1, not 10
}

func testConcurrentDownloadAndCancel() async throws {
    let manager = TestableDownloadManager()
    let track = makeTrack()

    await withTaskGroup(of: Void.self) { group in
        group.addTask { @MainActor in
            await manager.downloadTrack(track)
        }
        group.addTask { @MainActor in
            await manager.cancelDownload(trackId: track.id)
        }
    }

    // Final state should be consistent (either downloading or cancelled, not corrupted)
    let status = manager.downloadStatus(for: track.id)
    // Verify status is one of the valid states, not in an inconsistent state
}
```
- **Session**: DownloadManagerTests implementation (2026-01-22)

### Testable Class with Time Manipulation for Interval-Based Logic
- **Context**: Testing `@MainActor` classes like `PlaybackPositionTracker` that have time-based behavior (flush every N seconds)
- **Learning**: When testing classes with interval-based logic (timers, periodic flushes), create a testable version that:
  1. Uses dependency injection for services (ConvexService, AuthManager)
  2. Exposes private state via `forTesting` accessors (e.g., `lastPositionForTesting`)
  3. Provides a `simulateTimePassedForTesting(seconds:)` method that manipulates `lastFlushTime` by subtracting time
- **Example**:
```swift
@MainActor
final class TestablePlaybackPositionTracker {
    private var lastFlushTime: Date = Date()
    private let flushInterval: TimeInterval

    init(convexService: MockPositionConvexService, currentUserId: String?, flushInterval: TimeInterval = 10.0) {
        self.convexService = convexService
        self.currentUserId = currentUserId
        self.flushInterval = flushInterval
    }

    func simulateTimePassedForTesting(seconds: TimeInterval) {
        // Move lastFlushTime backwards to simulate time passing
        lastFlushTime = lastFlushTime.addingTimeInterval(-seconds)
    }

    func updatePosition(_ position: Double, duration: Double) {
        // ... existing logic ...
        if Date().timeIntervalSince(lastFlushTime) >= flushInterval {
            flush()  // Now triggers because "enough time has passed"
        }
    }
}

// Test usage
func testCustomFlushInterval() {
    let tracker = TestablePlaybackPositionTracker(flushInterval: 5.0)
    tracker.simulateTimePassedForTesting(seconds: 6)  // Simulate 6 seconds
    tracker.updatePosition(10.0, duration: 180.0)     // Should flush
}
```
- **Why not use real delays**: Real `Task.sleep()` makes tests slow and flaky. Time manipulation is instant and deterministic.
- **Session**: PlaybackPositionTrackerTests implementation (2026-01-22)

### Mock Service with Minimal API Surface
- **Context**: Creating mocks for services where only a few methods need testing
- **Learning**: When the class under test only uses one or two methods from a large service (e.g., PlaybackPositionTracker only uses `updatePlayPosition` from ConvexService), create a minimal mock that only implements those methods. This avoids maintaining a large mock with methods that are never exercised by the tests.
- **Example**:
```swift
// Instead of mocking all 20+ ConvexService methods:
final class MockPositionConvexService: @unchecked Sendable {
    private(set) var updatePlayPositionCallCount = 0
    private(set) var lastSessionId: String?
    private(set) var lastUserId: String?
    private(set) var lastPlaybackPosition: Double?
    private(set) var lastDuration: Double?
    var errorToThrow: Error?

    func updatePlayPosition(sessionId: String, userId: String, playbackPosition: Double, duration: Double) async throws {
        updatePlayPositionCallCount += 1
        lastSessionId = sessionId
        lastUserId = userId
        lastPlaybackPosition = playbackPosition
        lastDuration = duration
        if let error = errorToThrow { throw error }
    }
}
```
- **Benefits**: Simpler to maintain, clear test intent, faster to write
- **Session**: PlaybackPositionTrackerTests implementation (2026-01-22)

---

## Xcode / iOS Simulator

### iOS 26 Simulator Device Names
- **Context**: Running xcodebuild with destination specifier
- **Learning**: In iOS 26 / Xcode 17, simulator device names have changed. `iPhone 16 Pro` does not exist - use `iPhone 17 Pro`, `iPhone 17`, or `iPhone 17 Pro Max` instead. Always check available destinations if build fails with "device not found".
- **Command to list available simulators**:
```bash
xcodebuild -scheme YourScheme -showdestinations
```
- **Common iOS 26.1 simulators**: iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air, iPhone 16e, iPad Pro 11-inch (M5), iPad Pro 13-inch (M5)
- **Session**: PlaybackPositionTrackerTests build verification (2026-01-22)

### MockUserDefaults Pattern for Persistence Testing
- **Context**: Testing `@MainActor` classes that use `UserDefaults` for persistence (like `RecentSearchManager`)
- **Learning**: Create a `MockUserDefaults` class with dictionary-based storage instead of using real `UserDefaults`. This avoids test pollution, enables isolation, and allows verification of what was saved.
- **Example**:
```swift
// MockUserDefaults - dictionary-backed storage
final class MockUserDefaults {
    var storage: [String: Any] = [:]

    func stringArray(forKey key: String) -> [String]? {
        storage[key] as? [String]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value = value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
}

// Testable version with DI
@MainActor
final class TestableRecentSearchManager {
    private let userDefaults: MockUserDefaults

    init(userDefaults: MockUserDefaults) {
        self.userDefaults = userDefaults
        loadSearches()
    }
}

// Test verification
func testAddSearchPersistsToStorage() {
    manager.addSearch("swift")
    let stored = mockDefaults.storage["storageKey"] as? [String]
    XCTAssertEqual(stored, ["swift"])
}
```
- **Key benefit**: Tests can pre-populate storage, verify saves, and run in complete isolation
- **Session**: RecentSearchManagerTests implementation (2026-01-22)

### Testing Wrapper Types with Custom Equality
- **Context**: Testing types like `PlaylistItem` or `TrackItem` that wrap a model and add extra data (e.g., `soundCloudPlaylist`)
- **Learning**: Wrapper types often have custom equality that only considers the inner model's ID, ignoring other fields. This is intentional (for deduplication in collections) but must be tested explicitly to document and verify the behavior.
- **Example**:
```swift
// PlaylistItem equality is based ONLY on playlist.id
func testPlaylistItemEqualityIgnoresSoundCloudPlaylist() {
    let playlist = Playlist(id: "pl-1", name: "Test", creator: "User")
    let item1 = PlaylistItem(playlist: playlist, soundCloudPlaylist: nil)
    let item2 = PlaylistItem(playlist: playlist, soundCloudPlaylist: someSCPlaylist)
    XCTAssertEqual(item1, item2)  // Equal despite different soundCloudPlaylist!
}

// This enables correct Set/Dictionary behavior
func testPlaylistItemDeduplicationInSet() {
    var set = Set<PlaylistItem>()
    set.insert(PlaylistItem(playlist: playlist1, soundCloudPlaylist: nil))
    set.insert(PlaylistItem(playlist: playlist1, soundCloudPlaylist: scPlaylist))  // Same playlist
    XCTAssertEqual(set.count, 1)  // Deduplicated correctly
}
```
- **Why it matters**: Surprising equality semantics can cause bugs if not understood. Tests serve as documentation.
- **Session**: PlaylistTests model testing (2026-01-22)

### Testing Swift Protocol Conformances Systematically
- **Context**: Testing models that conform to Codable, Equatable, Hashable, Identifiable, and Sendable
- **Learning**: For value types with multiple protocol conformances, test each conformance explicitly rather than assuming compiler-synthesized implementations work correctly. This catches issues with custom implementations and documents expected behavior.
- **Test categories for protocol conformances**:
  1. **Equatable**: Test equality with all fields matching, then test inequality by changing each field individually
  2. **Hashable**: Test hash consistency (same object, same hash), equal objects have same hash, and Set/Dictionary usage
  3. **Codable**: Test encode/decode roundtrip, empty/nil fields, unicode, and error cases (missing required fields)
  4. **Identifiable**: Verify `id` property matches expected value
  5. **Sendable**: Verify can be used across actor boundaries (compile-time check, but document expected usage)
- **Example**:
```swift
// Equatable - test each field matters
func testInequalityByTitleOnly() {
    let track1 = Track(id: "same", title: "Title 1", artist: "Artist")
    let track2 = Track(id: "same", title: "Title 2", artist: "Artist")
    XCTAssertNotEqual(track1, track2)
}

// Hashable - Set usage
func testHashableInSet() {
    let track1 = Track(id: "1", title: "T1", artist: "A")
    let track2 = Track(id: "1", title: "T1", artist: "A")  // Equal to track1
    var set = Set([track1])
    set.insert(track2)  // Should not add
    XCTAssertEqual(set.count, 1)
}

// Codable - roundtrip
func testCodableRoundtrip() throws {
    let original = Track(id: "test", title: "Title", artist: "Artist")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Track.self, from: data)
    XCTAssertEqual(original, decoded)
}
```
- **Session**: TrackTests comprehensive model testing (2026-01-22)

### Testing Task Cancellation and Priority in Swift Actors
- **Context**: Testing actors that spawn cancellable tasks with different priorities (like TrackPrefetcher which prefetches current track at high priority, upcoming at utility)
- **Learning**: Create testable actor versions that track task cancellation and priority assignment. Expose methods to verify:
  1. Previous tasks are cancelled when new ones start
  2. Task priority varies by context (current vs upcoming items)
  3. Rapid successive calls don't cause race conditions
- **Key testable state to expose**:
  - `hasCurrentPrefetchTask()` - whether a task is running
  - `getLoadedPriorities()` - array of TaskPriority values in load order
  - Counter for items processed (to verify cancellation stopped previous work)
- **Example**:
```swift
// TestableTrackPrefetcher exposes task state for testing
actor TestableTrackPrefetcher {
    private var currentPrefetchTask: Task<Void, Never>?
    private var loadedPriorities: [TaskPriority] = []

    func hasCurrentPrefetchTask() -> Bool { currentPrefetchTask != nil }
    func getLoadedPriorities() -> [TaskPriority] { loadedPriorities }

    func prefetchForQueue(_ tracks: [Track], currentIndex: Int) {
        currentPrefetchTask?.cancel()  // Cancel previous
        currentPrefetchTask = Task(priority: .utility) {
            for (i, track) in tracks[currentIndex...].prefix(6).enumerated() {
                guard !Task.isCancelled else { break }
                let priority: TaskPriority = (i == 0) ? .high : .utility
                loadedPriorities.append(priority)
                // ... prefetch logic
            }
        }
    }
}

// Tests
func testCancelsPreviousTask() async {
    await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
    await prefetcher.prefetchForQueue(tracks, currentIndex: 10)  // Cancels first
    try? await Task.sleep(nanoseconds: 200_000_000)
    // Verify only second prefetch's items were processed
    XCTAssertTrue(prefetchedIds.contains("track-10"))
}

func testCurrentTrackHasHighPriority() async {
    await prefetcher.prefetchForQueue(tracks, currentIndex: 0)
    let priorities = await prefetcher.getLoadedPriorities()
    XCTAssertEqual(priorities.first, TaskPriority.high)
}
```
- **Session**: TrackPrefetcherTests implementation (2026-01-22)

### Model Test File Consistency Pattern
- **Context**: Writing multiple test files for related model types (Track, Playlist, PlaybackQueue, etc.)
- **Learning**: Maintain consistency across test files by following the same structure and test categories. Read an existing model test file before writing a new one to match: section organization, naming conventions, edge case categories, and fixture usage. This makes the test suite easier to navigate and maintain.
- **Test structure pattern for model tests**:
  1. Initialization tests (all params, defaults, unique IDs)
  2. Special character/unicode tests
  3. Field-specific behavior tests (tracks, dates, optionals)
  4. Equatable tests (equality by all fields, inequality by each field)
  5. Hashable tests (consistency, Set usage, Dictionary usage)
  6. Codable tests (roundtrip, edge cases, error cases)
  7. Identifiable tests
  8. Wrapper type tests (e.g., PlaylistItem, TrackItem)
  9. Edge cases (long strings, large counts, empty data)
  10. Concurrent access tests (thread safety)
- **Session**: PlaylistTests consistency with TrackTests (2026-01-22)

### SoundCloud Model Artwork Fallback Chain
- **Context**: Testing `SoundCloudPlaylist.primaryArtworkUrl` and similar computed properties
- **Learning**: SoundCloud models have fallback chains for artwork URLs. Understanding these chains is critical for writing accurate tests:
  - `SoundCloudPlaylist.primaryArtworkUrl`: `artworkUrl ?? user?.avatarUrl ?? ""`
  - `SoundCloudTrack.toTrack()` artwork: `artworkUrl ?? user?.avatarUrl`
- **Testing approach**: Test each branch of the fallback: primary present, primary nil but fallback present, all nil returns empty/default.
- **Example**:
```swift
func testPrimaryArtworkUrlFallbackChain() {
    // Primary artwork present
    let playlist1 = SoundCloudPlaylist(artworkUrl: "https://art.jpg", user: nil)
    XCTAssertEqual(playlist1.primaryArtworkUrl, "https://art.jpg")

    // Fallback to user avatar
    let user = SoundCloudUser(avatarUrl: "https://avatar.jpg")
    let playlist2 = SoundCloudPlaylist(artworkUrl: nil, user: user)
    XCTAssertEqual(playlist2.primaryArtworkUrl, "https://avatar.jpg")

    // All nil returns empty
    let playlist3 = SoundCloudPlaylist(artworkUrl: nil, user: nil)
    XCTAssertEqual(playlist3.primaryArtworkUrl, "")
}
```
- **Session**: PlaylistTests SoundCloudPlaylist conversion (2026-01-22)
