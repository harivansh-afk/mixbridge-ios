# Sync Engine Architecture

This document covers the local-first sync engine implementation in mixbridge, including module organization patterns in Swift.

## Overview

The sync engine provides offline-first data persistence using GRDB (SQLite) with background synchronization to the Convex backend. UI always reads from the local database, ensuring instant responsiveness.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     SwiftUI Views                           │
│   (HomeView, LibraryView, LikedView, PlaylistDetailView)   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     ViewModels                              │
│   (@Observable, GRDB ValueObservation, MainActor)          │
│   LibraryViewModel, HomeViewModel, LikedViewModel, etc.    │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────┐
│      Sync Classes       │     │     GRDB Database           │
│   (Sendable, actor-    │     │   (MixBridgeDB.shared)      │
│    serialized)         │     │                             │
│                        │     │   reader: DatabaseReader    │
│  - PlaylistSync        │────▶│   writer: DatabaseWriter    │
│  - HistorySync         │     │                             │
│  - LikedSync           │     │   Tables:                   │
└─────────────────────────┘     │   - tracks                  │
              │                 │   - playlists               │
              ▼                 │   - playlist_tracks         │
┌─────────────────────────┐     │   - play_history            │
│     ConvexService       │     │   - liked_tracks            │
│   (Backend REST API)    │     └─────────────────────────────┘
└─────────────────────────┘
```

## Module Organization (Swift Package Manager)

### Package Structure

```
Packages/
├── MixBridgeDomain/           # Pure Swift domain models
│   ├── Package.swift
│   └── Sources/
│       └── Models/
│           ├── PersistedTrack.swift
│           ├── PersistedPlaylist.swift
│           ├── PlaylistTrack.swift
│           ├── PlayHistory.swift
│           └── LikedTrack.swift
│
└── MixBridgeDB/               # GRDB database layer
    ├── Package.swift
    ├── Package.resolved
    └── Sources/
        ├── MixBridgeDB.swift          # Main entry point
        ├── Migrations/
        │   └── Migrations.swift       # Schema definition
        └── Models/
            ├── PersistedTrack+GRDB.swift
            ├── PersistedPlaylist+GRDB.swift
            ├── PlaylistTrack+GRDB.swift
            ├── PlayHistory+GRDB.swift
            └── LikedTrack+GRDB.swift
```

### Why This Separation?

1. **MixBridgeDomain** - No external dependencies
   - Pure Swift `Codable` structs
   - Can be used anywhere (app, tests, previews)
   - Defines `CodingKeys` for database column mapping
   - Sendable, Hashable, Identifiable conformances

2. **MixBridgeDB** - Depends on GRDB + MixBridgeDomain
   - `@retroactive` protocol conformances for GRDB
   - Database migrations and schema
   - Column definitions and associations
   - Helper structs for joined queries (e.g., `PlayHistoryWithTrack`)

### Re-exporting Pattern

In `MixBridgeDB.swift`:
```swift
@_exported import GRDB
@_exported import MixBridgeDomain
```

This allows app code to import just `MixBridgeDB` and get access to:
- All GRDB types (DatabaseWriter, ValueObservation, etc.)
- All domain models (PersistedTrack, PersistedPlaylist, etc.)
- Database extensions (Columns, associations)

### Adding GRDB Conformances Retroactively

Since domain models are in a separate module, we use `@retroactive` to add protocol conformances:

```swift
// In MixBridgeDB package
extension PersistedTrack: @retroactive TableRecord {
    public static let databaseTableName = "tracks"
}

extension PersistedTrack: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let title = Column(CodingKeys.title)
        // ...
    }
}
```

## Sync Classes

### SyncOperationQueue (Actor-based Serialization)

```swift
actor SyncOperationQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail

        // Detach to prevent cancellation propagation
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

**Key design decisions:**
- Actor ensures only one operation runs at a time per sync class
- `Task.detached` prevents caller cancellation from aborting queued work
- Each sync class has its own queue (playlists, history, liked are independent)

### Sync Class Pattern

Each sync class follows this pattern:

```swift
final class PlaylistSync: Sendable {
    private let db = MixBridgeDB.shared
    private let convex = ConvexService.shared
    private let operationQueue = SyncOperationQueue()

    static let shared = PlaylistSync()
    private init() {}

    // Full sync from backend
    func syncPlaylists(userId: String, forceRefresh: Bool = false) async throws {
        try await operationQueue.run { [self] in
            let scPlaylists = try await convex.getPlaylists(userId: userId, forceRefresh: forceRefresh)
            try await db.writer.write { db in
                for scPlaylist in scPlaylists {
                    var persisted = PersistedPlaylist(from: scPlaylist)
                    try persisted.upsert(db)
                }
            }
        }
    }

    // Local queries (no network)
    func getLocalPlaylists() async throws -> [PersistedPlaylist] {
        try await db.reader.read { db in
            try PersistedPlaylist.order(PersistedPlaylist.Columns.lastUpdated.desc).fetchAll(db)
        }
    }
}
```

## ViewModel Pattern with ValueObservation

ViewModels observe the local database and trigger syncs:

```swift
@Observable
@MainActor
final class LibraryViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    private let db = MixBridgeDB.shared
    private let playlistSync = PlaylistSync.shared

    // Start reactive observation
    func observeDatabase() async {
        let observation = ValueObservation.trackingConstantRegion { db in
            try PersistedPlaylist
                .order(PersistedPlaylist.Columns.lastUpdated.desc)
                .fetchAll(db)
        }
        .values(in: db.reader)

        do {
            for try await persistedPlaylists in observation {
                self.playlists = persistedPlaylists.map { $0.toPlaylist() }
                self.error = nil
            }
        } catch {
            self.error = error
        }
    }

    // Trigger network sync
    func refresh(userId: String, forceRefresh: Bool = false) async {
        isLoading = playlists.isEmpty
        do {
            try await playlistSync.syncPlaylists(userId: userId, forceRefresh: forceRefresh)
            error = nil
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
```

### View Integration (Dual .task Pattern)

```swift
struct LibraryView: View {
    @State private var viewModel = LibraryViewModel()
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        // ...
        .task {
            await viewModel.observeDatabase()  // Start observation (runs forever)
        }
        .task {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId)  // Trigger sync
            }
        }
        .refreshable {
            if let userId = authManager.currentUserId {
                await viewModel.refresh(userId: userId, forceRefresh: true)
            }
        }
    }
}
```

## Optimistic Updates with Rollback

For user-initiated actions (like/unlike), use optimistic updates:

```swift
func likeTrack(_ scTrack: SoundCloudTrack) async throws {
    let trackId = String(scTrack.id)

    // 1. Optimistic update to local DB
    try await db.writer.write { db in
        var track = PersistedTrack(from: scTrack)
        try track.upsert(db)

        var likedTrack = LikedTrack(trackId: trackId, likedAt: Date())
        try likedTrack.upsert(db)
    }

    // 2. Sync to backend
    do {
        try await convex.likeTrack(trackId: trackId)
    } catch {
        // 3. Rollback on failure
        try await db.writer.write { db in
            try LikedTrack.deleteOne(db, key: trackId)
        }
        throw error
    }
}
```

## Database Schema

### Tables and Relationships

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    playlists    │     │ playlist_tracks │     │     tracks      │
├─────────────────┤     ├─────────────────┤     ├─────────────────┤
│ id (PK)         │◄───┤ playlistId (FK) │     │ id (PK)         │
│ name            │     │ trackId (FK)    │────▶│ title           │
│ creator         │     │ position        │     │ artist          │
│ creatorId       │     │ addedAt         │     │ artistId        │
│ artwork         │     └─────────────────┘     │ artwork         │
│ trackCount      │                             │ duration        │
│ lastUpdated     │                             │ soundCloudData  │
└─────────────────┘                             └─────────────────┘
                                                        │
                        ┌───────────────────────────────┼───────────────────────────────┐
                        ▼                               ▼                               ▼
               ┌─────────────────┐             ┌─────────────────┐             ┌─────────────────┐
               │  play_history   │             │  liked_tracks   │             │ playlist_tracks │
               ├─────────────────┤             ├─────────────────┤             ├─────────────────┤
               │ trackId (PK,FK) │             │ trackId (PK,FK) │             │ (see above)     │
               │ playCount       │             │ likedAt         │             └─────────────────┘
               │ lastPlayedPos   │             └─────────────────┘
               │ listenedPct     │
               │ updatedAt       │
               └─────────────────┘
```

### Conflict Resolution

All tables use REPLACE policy for idempotent syncs:

```swift
public static var persistenceConflictPolicy: PersistenceConflictPolicy {
    PersistenceConflictPolicy(insert: .replace, update: .replace)
}
```

This ensures:
- Re-syncing the same data doesn't create duplicates
- Upsert operations are safe to retry
- Primary keys enforce uniqueness

## Key Patterns

### 1. History Aggregation

When syncing history, aggregate multiple play entries for the same track:

```swift
// Backend returns: [trackA, trackB, trackA, trackA]
// Should result in: trackA.playCount = 3, trackB.playCount = 1

var aggregated: [String: AggregatedHistory] = [:]
for playItem in history {
    let trackId = String(playItem.trackData.id)
    if var existing = aggregated[trackId] {
        existing.playCount += 1
        // Keep most recent position/time
        aggregated[trackId] = existing
    } else {
        aggregated[trackId] = AggregatedHistory(trackData: playItem.trackData, playCount: 1, ...)
    }
}
```

### 2. Preloading Playlist Tracks

Sync playlist tracks in background when playlist cards become visible:

```swift
.onAppear {
    if let userId = authManager.currentUserId {
        Task(priority: .background) {
            await viewModel.preloadPlaylistTracks(userId: userId, playlistId: playlist.id)
        }
    }
}
```

### 3. Force Refresh

Use `forceRefresh: true` to bypass Convex cache on pull-to-refresh:

```swift
.refreshable {
    await viewModel.refresh(userId: userId, forceRefresh: true)
}
```

## Common Pitfalls

1. **Don't increment counts per API record** - Aggregate first, then save
2. **Use db.reader for reads, db.writer for writes** - Prevents blocking
3. **Each sync class has its own queue** - They don't block each other
4. **ValueObservation runs forever** - Use in `.task` (auto-cancels on disappear)
5. **Optimistic updates need rollback** - Except fire-and-forget cases (history)
