# MixBridge Local Sync Engine - Handoff Document

## Overview

This document provides context for implementing a local-first sync engine in MixBridge, following patterns from the Phia iOS app. The implementation plan is in `plan.md`.

---

## Repository Locations

| Repo | Path | Purpose |
|------|------|---------|
| **MixBridge** | `/Users/rathi/Documents/GitHub/mixbridge/mixbridge-ios/.worktrees/afabfb` | Target app to refactor |
| **Phia** | `/Users/rathi/Documents/GitHub/phia/phia-swift` | Reference implementation |

---

## Exploration Tree: MixBridge (Current Architecture)

```
mixbridge/
├── mixbridgeApp.swift                    # App entry point
│   ├── Lines 47-52: Preloader initialization
│   ├── Lines 15: selectedTab = 1 (LibraryView is default)
│   └── Splash logic: Fixed 500ms timer (THE PROBLEM)
│
├── Services/
│   ├── ConvexService.swift               # API gateway (KEEP)
│   │   ├── All API calls to Convex backend
│   │   ├── getPlaylists(), getPlayHistory(), getLikedTracks()
│   │   ├── getPlaylistTracks(), getDirectStreamURL()
│   │   └── Queue operations: addTrackToQueue(), removeTrackFromQueue()
│   │
│   ├── AppDataPreloader.swift            # Data orchestrator (REPLACE)
│   │   ├── actor AppDataPreloader
│   │   ├── Tier 1: loadProfile, loadPlayHistory, loadPlaylists (parallel)
│   │   ├── Tier 2: loadLikedTracks, top 5 playlist tracks (sequential)
│   │   ├── Tier 3: remaining playlists, artwork prefetch
│   │   └── refreshIfStale() - freshness checking
│   │
│   ├── PreloadedDataStore.swift          # In-memory store (REPLACE)
│   │   ├── @MainActor @Observable
│   │   ├── playlists, playHistory, likedTracks arrays
│   │   ├── playlistTracks dictionary
│   │   ├── PreloadState enum (idle/loading/loaded/failed)
│   │   └── Freshness tracking (5 min threshold)
│   │
│   ├── StreamURLCache.swift              # Stream caching (KEEP)
│   │   ├── actor StreamURLCache
│   │   ├── 3-minute cache TTL
│   │   ├── Request deduplication via inFlight dictionary
│   │   └── Prefetch queue with rate limiting
│   │
│   ├── PlaybackCoordinator.swift         # Playback control (MODIFY)
│   │   ├── @MainActor final class
│   │   ├── play(), pause(), seek(), playNext()
│   │   ├── Uses PreloadedDataStore for optimistic history update
│   │   └── Line ~180: prependOrMovePlayHistoryTrack() call
│   │
│   ├── MixPlaybackEngine.swift           # Crossfade engine (KEEP)
│   ├── QueueManager.swift                # Queue state (KEEP)
│   ├── TrackPrefetcher.swift             # Image prefetch (KEEP)
│   └── PlaybackPositionTracker.swift     # Position batching (KEEP)
│
├── Models/
│   ├── Track.swift                       # Display model
│   │   └── id, title, artist, album, artwork, duration
│   │
│   ├── Playlist.swift                    # Playlist model
│   │   └── id, name, creator, artwork, tracks[], lastUpdated
│   │
│   ├── SoundCloudModels.swift            # API models
│   │   ├── SoundCloudTrack (id, title, user, duration, artwork_url)
│   │   ├── SoundCloudPlaylist
│   │   ├── SoundCloudUser
│   │   └── Extension: toTrack() conversion
│   │
│   └── ConvexDataModels.swift            # Backend models
│       ├── ConvexPlayHistory
│       ├── ConvexQueueTrack
│       └── ConvexStreamResponse
│
├── Views/
│   ├── Home/HomeView.swift               # Recents view
│   │   ├── @Environment(PreloadedDataStore.self)
│   │   ├── Line 58: checks playHistoryState == .loading
│   │   └── Shows spinner until data loaded
│   │
│   ├── Library/LibraryView.swift         # Library view (DEFAULT TAB)
│   │   ├── @Environment(PreloadedDataStore.self)
│   │   ├── Line 22: checks playlistsState == .loading
│   │   └── Shows spinner until data loaded
│   │
│   ├── Playlist/PlaylistDetailView.swift # Playlist detail
│   ├── Liked/LikedView.swift             # Liked tracks
│   └── Search/SearchView.swift           # Search
│
├── Utilities/
│   └── ImageCacheManager.swift           # Image caching (KEEP)
│       ├── actor ImageCacheManager
│       ├── Memory cache (NSCache, 100 items, 100MB)
│       └── Disk cache (SHA256 filenames)
│
└── ContentView.swift                     # Tab container
    └── Line 15: @State private var selectedTab = 1
```

---

## Exploration Tree: Phia (Reference Patterns)

```
phia-swift/
├── PhiaSwift/Application/PhiaSwiftApp.swift    # App entry
│   ├── Lines 40-42: isShowingSplash checks BOTH conditions
│   │   └── !(userSessionManager.isInitialized && finishedSplash)
│   ├── Lines 48-52: Shows RootView when initialized
│   ├── Lines 106-114: Splash completion callback
│   └── KEY: Splash waits for AUTH, not DATA
│
├── PhiaSwift/Views/RootView.swift              # Main content
│   ├── Line 84: Task { await userSessionManager.fetchUserData() }
│   └── NO preloader - views load their own data
│
├── Layers/Services/PhiaDB/                     # DATABASE LAYER
│   ├── Sources/PhiaDB.swift                    # DB singleton
│   │   ├── struct PhiaDB
│   │   ├── init(_ writer: DatabaseWriter)
│   │   ├── var reader: DatabaseReader
│   │   ├── var writer: DatabaseWriter
│   │   └── migrator setup
│   │
│   ├── Sources/Persistance.swift               # File persistence
│   │   ├── static let primary = makeShared()
│   │   ├── getDatabaseFilePath() -> ApplicationSupport/Database/db.sqlite
│   │   └── DatabasePool initialization
│   │
│   ├── Sources/MigratableTable.swift           # Migration protocol
│   │   ├── protocol MigratableTable
│   │   └── DatabaseMigrator.registerMigration(for:)
│   │
│   ├── Sources/Migrations/AllTables.swift      # Table registry
│   │   └── var allTables: [any MigratableTable.Type]
│   │
│   └── Sources/Models/                         # GRDB models
│       ├── Product.swift                       # REFERENCE MODEL
│       │   ├── CodingKeys enum
│       │   ├── init(from decoder:) - Decodable
│       │   ├── encode(to container:) - PersistenceContainer
│       │   ├── Columns enum for type-safe queries
│       │   ├── MigratableTable.createTable()
│       │   └── Associations: hasMany, belongsTo
│       │
│       ├── Collection.swift                    # With associations
│       │   ├── static let productAssociation = hasMany(...)
│       │   └── .forKey("savedProducts") mapping
│       │
│       ├── CollectionProduct.swift             # Junction table
│       │   ├── Composite primary key
│       │   ├── Foreign key references
│       │   └── persistenceConflictPolicy: .replace
│       │
│       ├── ProductHistory.swift                # History junction
│       │   ├── trackId as primary key
│       │   ├── createdAt, updatedAt timestamps
│       │   └── static let product = belongsTo(...)
│       │
│       ├── Brand.swift
│       ├── Editorial.swift
│       ├── EditorialProduct.swift
│       ├── Outfit.swift
│       ├── OutfitProduct.swift
│       ├── TrendingProduct.swift
│       ├── PriceDrop.swift
│       └── UserNotification.swift
│
├── Layers/Services/PhiaSync/                   # SYNC LAYER
│   ├── Sources/OperationQueue.swift            # Serial async queue
│   │   ├── actor OperationQueue
│   │   ├── private var tail: Task<Void, Never>?
│   │   └── func run<T>(_ operation:) async throws -> T
│   │
│   ├── Sources/FavoritesSync/
│   │   ├── FavoritesSync.swift                 # Sync coordinator
│   │   │   ├── final class FavoritesSync
│   │   │   ├── let operationQueue: OperationQueue
│   │   │   └── toggleSavedProduct() with optimistic update
│   │   │
│   │   └── Repository/FavoritesSyncRepository.swift
│   │       ├── Snapshot old state
│   │       ├── Apply optimistic update to DB
│   │       ├── Try server request
│   │       └── Rollback on failure
│   │
│   ├── Sources/HistorySync/
│   │   ├── HistorySync.swift
│   │   └── Repository/HistorySyncRepository.swift
│   │       ├── addProductToRecentHistory()
│   │       ├── Dual storage: DB + Keychain
│   │       └── loadHistory() - sync keychain to DB
│   │
│   ├── Sources/CuratedSync/
│   │   ├── CuratedSync.swift
│   │   │   └── async let pattern for parallel fetches
│   │   └── Repository/CuratedRepository.swift
│   │       └── Full refresh with cascade delete pattern
│   │
│   ├── Sources/TrendingSync/
│   └── Sources/PriceDropsSync/
│
├── Layers/Features/PhiaSaved/Sources/
│   └── ViewModels/SavedViewModel.swift         # REFERENCE VIEWMODEL
│       ├── @Observable public class SavedViewModel
│       ├── @ObservationIgnored @Dependency(\.favoritesSync)
│       ├── Lines 94-174: observeDatabase() async
│       │   ├── ValueObservation.trackingConstantRegion { db in ... }
│       │   ├── Multiple queries in single observation
│       │   ├── .values(in: db.reader)
│       │   ├── for try await ... in observation
│       │   └── await MainActor.run { self.property = value }
│       │
│       └── Lines 176-181: fetchData() async
│           └── async let savedBrands, savedCollections
│
├── Layers/Features/PhiaSaved/Sources/Views/
│   └── SavedView.swift                         # REFERENCE VIEW
│       ├── Line 49: .task { await viewModel.observeDatabase() }
│       ├── Line 50: .onFirstAppear { await viewModel.fetchData() }
│       └── NO loading spinner for cached data
│
├── Layers/Features/PhiaExplore/Sources/
│   └── ViewModel/ExploreViewModel.swift
│       ├── Lines 98-113: fetchData() with async let
│       └── Lines 115-204: observeDatabase()
│
└── Layers/Foundation/
    ├── PhiaCore/                               # Utilities
    │   └── Sources/Managers/
    │       └── AppTrackingWorker.swift         # Worker pattern
    │
    └── Domain/                                 # Shared models
        └── Sources/Domain/                     # GraphQL types
```

---

## Key Code Patterns to Reference

### 1. GRDB Model Definition Pattern

**File:** `phia-swift/Layers/Services/PhiaDB/Sources/Models/Product.swift`

```swift
// 1. Define columns
enum Columns {
    static let id = Column(CodingKeys.id)
    static let name = Column(CodingKeys.name)
    // ...
}

// 2. GRDB protocol conformance
extension Product: TableRecord, FetchableRecord, MutablePersistableRecord {
    static var databaseTableName = "products"
}

// 3. Migration
extension Product: MigratableTable {
    static func createTable(table: TableDefinition) {
        table.column(Columns.id.name, .text).primaryKey()
        table.column(Columns.name.name, .text).notNull()
        // ...
    }
}

// 4. Associations
extension Product {
    static let collections = hasMany(Collection.self, through: collectionProducts, using: ...)
}
```

### 2. ValueObservation Pattern

**File:** `phia-swift/Layers/Features/PhiaSaved/Sources/ViewModels/SavedViewModel.swift`

```swift
func observeDatabase() async {
    @Dependency(\.phiaDB) var db

    let observation = ValueObservation.trackingConstantRegion { db in
        // All queries execute in single transaction
        let collections = try Collection.fetchAll(db)
        let products = try Product.filter(...).fetchAll(db)
        return (collections, products)
    }
    .values(in: db.reader)

    for try await (collections, products) in observation {
        await MainActor.run {
            self.collections = collections
            self.products = products
        }
    }
}
```

### 3. Optimistic Update Pattern

**File:** `phia-swift/Layers/Services/PhiaSync/Sources/FavoritesSync/Repository/FavoritesSyncRepository.swift`

```swift
func toggleSavedProduct(_ product: Product, collectionId: String) async throws {
    // 1. Snapshot old state
    let oldCollectionIds = product.collectionIds

    // 2. Apply optimistic update to DB
    try await db.writer.write { db in
        var updated = product
        updated.collectionIds.append(collectionId)
        try updated.upsert(db)
    }

    // 3. Try server request
    do {
        try await apiClient.performAsync(mutation: AddProductMutation(...))
    } catch {
        // 4. Rollback on failure
        try await db.writer.write { db in
            var rolledBack = product
            rolledBack.collectionIds = oldCollectionIds
            try rolledBack.upsert(db)
        }
        throw error
    }
}
```

### 4. OperationQueue Actor Pattern

**File:** `phia-swift/Layers/Services/PhiaSync/Sources/OperationQueue.swift`

```swift
actor OperationQueue {
    private var tail: Task<Void, Never>?

    func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = tail

        let current = Task.detached { () throws -> T in
            _ = await previous?.value  // Wait for previous
            return try await operation()
        }

        tail = Task.detached {
            _ = try? await current.value
        }

        return try await current.value
    }
}
```

### 5. View + ViewModel Pattern

**File:** `phia-swift/Layers/Features/PhiaSaved/Sources/Views/SavedView.swift`

```swift
struct SavedView: View {
    @State private var viewModel: SavedViewModel

    var body: some View {
        content
            .task { await viewModel.observeDatabase() }  // Start observation
            .onFirstAppear {
                Task { await viewModel.fetchData() }     // Fetch fresh
            }
    }
}
```

---

## Nuances and Gotchas

### MixBridge Specific

1. **Default tab is Library (index 1)** - ContentView.swift line 15
2. **Splash uses fixed 500ms timer** - mixbridgeApp.swift - this is why it feels slow
3. **SoundCloudTrack uses `Int` for ID** - must convert to String for DB
4. **TrackItem bundles Track + SoundCloudTrack + metadata** - need to preserve this
5. **ConvexService is non-isolated static** - safe to call from anywhere
6. **StreamURLCache has 3-minute TTL** - keep this for stream URLs
7. **PlaybackCoordinator calls `prependOrMovePlayHistoryTrack()`** - update to use HistorySync

### Phia Specific

1. **Uses @Dependency macro** from swift-dependencies - MixBridge doesn't have this
2. **Uses @ObservationIgnored** to prevent dependency re-renders
3. **observeDatabase() runs until task cancellation** - view disappearing cancels it
4. **Junction tables use composite primary keys** - prevents duplicates
5. **JSON arrays stored as TEXT** in SQLite - encode/decode at boundary
6. **eraseDatabaseOnSchemaChange = true** - dev-friendly, full reset on migration

### GRDB Specific

1. **DatabasePool for reads, DatabaseQueue for writes** - or use DatabasePool for both
2. **upsert() requires MutablePersistableRecord** - handles insert or update
3. **ValueObservation.trackingConstantRegion** - tracks whole tables, simpler
4. **ValueObservation.tracking** - more granular, tracks specific queries
5. **for try await** on observation - async stream, auto-cancels on task cancel
6. **MainActor.run {} inside observation** - required for UI property updates

---

## Implementation Order

1. **Phase 1: Database Layer**
   - Add GRDB to Package.swift
   - Create MixBridgeDB.swift (copy Phia pattern)
   - Create PersistedPlaylist.swift model
   - Create PersistedTrack.swift model
   - Create junction tables (PlayHistory, PlaylistTrack, LikedTrack)
   - Test: Can write and read playlists

2. **Phase 2: Sync Layer**
   - Create OperationQueue.swift actor
   - Create PlaylistSync.swift
   - Create HistorySync.swift
   - Test: Can sync from Convex to local DB

3. **Phase 3: Migrate HomeView**
   - Create HomeViewModel with observeDatabase()
   - Update HomeView to use ViewModel
   - Test: Home shows cached data instantly

4. **Phase 4: Migrate LibraryView**
   - Create LibraryViewModel with observeDatabase()
   - Update LibraryView to use ViewModel
   - Test: Library shows cached data instantly

5. **Phase 5: Migrate Remaining Views**
   - PlaylistDetailView
   - LikedView
   - AllPlaylistsView, AllSongsView, AllArtistsView

6. **Phase 6: Update PlaybackCoordinator**
   - Use HistorySync.addToHistory() instead of PreloadedDataStore
   - Test: Playing track updates history instantly

7. **Phase 7: Cleanup**
   - Remove AppDataPreloader.swift
   - Remove PreloadedDataStore.swift
   - Update mixbridgeApp.swift splash logic
   - Test: Cold start shows content instantly

---

## Testing Checklist

- [ ] Cold start: Library shows playlists in <100ms
- [ ] Cold start: Home shows history in <100ms
- [ ] Pull to refresh: Updates data from network
- [ ] Play track: History updates instantly (optimistic)
- [ ] Offline: Can browse all cached data
- [ ] Re-launch: Data persists across app restarts
- [ ] Memory: No significant increase in RAM usage

---

## Files to Read Before Implementation

### MixBridge (understand current state)
1. `Services/ConvexService.swift` - API methods to wrap
2. `Services/PreloadedDataStore.swift` - State structure to replace
3. `Models/SoundCloudModels.swift` - Data models to persist
4. `Views/Library/LibraryView.swift` - View to migrate

### Phia (reference patterns)
1. `Layers/Services/PhiaDB/Sources/PhiaDB.swift` - DB setup
2. `Layers/Services/PhiaDB/Sources/Models/Product.swift` - Model pattern
3. `Layers/Services/PhiaSync/Sources/OperationQueue.swift` - Actor pattern
4. `Layers/Features/PhiaSaved/Sources/ViewModels/SavedViewModel.swift` - ViewModel pattern
5. `Layers/Features/PhiaSaved/Sources/Views/SavedView.swift` - View pattern

---

## Contact

Created by Claude Code analysis session on 2026-01-04.
Reference: This document synthesizes findings from 4 parallel exploration agents analyzing both codebases.
