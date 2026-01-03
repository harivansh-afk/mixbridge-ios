MixBridge Refactoring Plan: Local Sync Engine Architecture

  Based on the comprehensive analysis of both codebases, here's the architectural refactoring plan to bring Phia's patterns to MixBridge.

  ---
  Executive Summary

  Current MixBridge Architecture

  - In-memory state: PreloadedDataStore is emptied on app restart
  - No local persistence: All data fetched from network each launch
  - Preloader-blocked UI: Views show spinners until network completes
  - Flat file structure: All services in /Services/, all models in /Models/

  Target Architecture (Phia Pattern)

  - Local-first: GRDB SQLite database persists all data
  - Reactive UI: ValueObservation streams database changes to views
  - Instant loading: Views read from local DB, network syncs in background
  - Modular packages: Separate Swift packages for DB, Sync, Features

  ---
  Phase 1: Add GRDB Database Layer

  1.1 Create Database Package Structure

  mixbridge/
  ├── Database/
  │   ├── MixBridgeDB.swift           # Database singleton + configuration
  │   ├── Persistence.swift            # File path + initialization
  │   ├── MigratableTable.swift        # Migration protocol
  │   ├── Migrations/
  │   │   └── AllTables.swift          # Table registry
  │   └── Models/
  │       ├── PersistedPlaylist.swift  # GRDB Playlist model
  │       ├── PersistedTrack.swift     # GRDB Track model
  │       ├── PersistedTrackItem.swift # GRDB TrackItem model
  │       ├── PlayHistory.swift        # Junction: tracks + play history
  │       ├── PlaylistTrack.swift      # Junction: playlist + tracks
  │       └── LikedTrack.swift         # Junction: user + liked tracks

  1.2 Core Database Files

  MixBridgeDB.swift
  import GRDB

  struct MixBridgeDB {
      private let dbWriter: DatabaseWriter

      init(_ writer: DatabaseWriter) throws {
          dbWriter = writer
          try migrator.migrate(writer)
      }

      var reader: DatabaseReader { dbWriter }
      var writer: DatabaseWriter { dbWriter }

      var migrator: DatabaseMigrator {
          var migrator = DatabaseMigrator()
          migrator.eraseDatabaseOnSchemaChange = true

          for table in allTables {
              migrator.registerMigration(for: table)
          }
          return migrator
      }

      static let shared = makeShared()

      private static func makeShared() -> MixBridgeDB {
          do {
              let url = try getDatabasePath()
              let dbPool = try DatabasePool(path: url.path)
              return try MixBridgeDB(dbPool)
          } catch {
              // Fallback to in-memory
              let queue = try! DatabaseQueue()
              return try! MixBridgeDB(queue)
          }
      }

      private static func getDatabasePath() throws -> URL {
          let appSupport = try FileManager.default.url(
              for: .applicationSupportDirectory,
              in: .userDomainMask,
              appropriateFor: nil,
              create: true
          )
          let dbDir = appSupport.appendingPathComponent("Database", isDirectory: true)
          try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
          return dbDir.appendingPathComponent("mixbridge.sqlite")
      }
  }

  MigratableTable.swift
  protocol MigratableTable: TableRecord, FetchableRecord, MutablePersistableRecord {
      static var databaseTableName: String { get }
      static func createTable(table: TableDefinition)
  }

  extension DatabaseMigrator {
      mutating func registerMigration(for table: any MigratableTable.Type) {
          registerMigration("create_\(table.databaseTableName)") { db in
              try db.create(table: table.databaseTableName) { t in
                  table.createTable(table: t)
              }
          }
      }
  }

  1.3 GRDB Model Definitions

  PersistedPlaylist.swift
  import GRDB

  struct PersistedPlaylist: Codable, Equatable, Identifiable {
      var id: String
      var name: String
      var creator: String
      var artwork: String
      var trackCount: Int
      var lastUpdated: Date
      var soundCloudData: Data?  // JSON-encoded SoundCloudPlaylist

      // Computed property to decode SoundCloud data
      var soundCloudPlaylist: SoundCloudPlaylist? {
          guard let data = soundCloudData else { return nil }
          return try? JSONDecoder().decode(SoundCloudPlaylist.self, from: data)
      }
  }

  extension PersistedPlaylist: TableRecord, FetchableRecord, MutablePersistableRecord {
      static var databaseTableName = "playlists"

      enum Columns {
          static let id = Column(CodingKeys.id)
          static let name = Column(CodingKeys.name)
          static let creator = Column(CodingKeys.creator)
          static let artwork = Column(CodingKeys.artwork)
          static let trackCount = Column(CodingKeys.trackCount)
          static let lastUpdated = Column(CodingKeys.lastUpdated)
          static let soundCloudData = Column(CodingKeys.soundCloudData)
      }
  }

  extension PersistedPlaylist: MigratableTable {
      static func createTable(table: TableDefinition) {
          table.column(Columns.id.name, .text).primaryKey()
          table.column(Columns.name.name, .text).notNull()
          table.column(Columns.creator.name, .text).notNull()
          table.column(Columns.artwork.name, .text).notNull()
          table.column(Columns.trackCount.name, .integer).notNull().defaults(to: 0)
          table.column(Columns.lastUpdated.name, .datetime).notNull()
          table.column(Columns.soundCloudData.name, .blob)
      }
  }

  // Association to tracks via junction table
  extension PersistedPlaylist {
      static let playlistTracks = hasMany(PlaylistTrack.self)
      static let tracks = hasMany(
          PersistedTrack.self,
          through: playlistTracks,
          using: PlaylistTrack.track
      ).order(PlaylistTrack.Columns.position)
  }

  // Conversion helpers
  extension PersistedPlaylist {
      init(from playlist: Playlist) {
          self.id = playlist.id
          self.name = playlist.name
          self.creator = playlist.creator
          self.artwork = playlist.artwork
          self.trackCount = playlist.tracks.count
          self.lastUpdated = playlist.lastUpdated
      }

      func toPlaylist(with tracks: [Track] = []) -> Playlist {
          Playlist(
              id: id,
              name: name,
              creator: creator,
              artwork: artwork,
              tracks: tracks,
              lastUpdated: lastUpdated
          )
      }
  }

  PlayHistory.swift (Junction table)
  struct PlayHistory: Codable, Equatable {
      var trackId: String
      var playCount: Int
      var lastPlayedPosition: Double
      var listenedPercentage: Double
      var createdAt: Date
      var updatedAt: Date
  }

  extension PlayHistory: TableRecord, FetchableRecord, MutablePersistableRecord {
      static var databaseTableName = "play_history"

      enum Columns {
          static let trackId = Column(CodingKeys.trackId)
          static let playCount = Column(CodingKeys.playCount)
          static let lastPlayedPosition = Column(CodingKeys.lastPlayedPosition)
          static let listenedPercentage = Column(CodingKeys.listenedPercentage)
          static let createdAt = Column(CodingKeys.createdAt)
          static let updatedAt = Column(CodingKeys.updatedAt)
      }

      static var persistenceConflictPolicy: PersistenceConflictPolicy {
          PersistenceConflictPolicy(insert: .replace, update: .replace)
      }
  }

  extension PlayHistory: MigratableTable {
      static func createTable(table: TableDefinition) {
          table.column(Columns.trackId.name, .text).primaryKey()
              .references("tracks", onDelete: .cascade)
          table.column(Columns.playCount.name, .integer).notNull().defaults(to: 1)
          table.column(Columns.lastPlayedPosition.name, .double).notNull().defaults(to: 0)
          table.column(Columns.listenedPercentage.name, .double).notNull().defaults(to: 0)
          table.column(Columns.createdAt.name, .datetime).notNull()
          table.column(Columns.updatedAt.name, .datetime).notNull().indexed()
      }
  }

  extension PlayHistory {
      static let track = belongsTo(PersistedTrack.self)
  }

  ---
  Phase 2: Create Sync Engine

  2.1 Sync Service Structure

  mixbridge/
  ├── Sync/
  │   ├── OperationQueue.swift         # Serial async operation queue (actor)
  │   ├── PlaylistSync.swift           # Playlist synchronization
  │   ├── HistorySync.swift            # Play history synchronization
  │   ├── LikedSync.swift              # Liked tracks synchronization
  │   └── Repository/
  │       ├── PlaylistSyncRepository.swift
  │       ├── HistorySyncRepository.swift
  │       └── LikedSyncRepository.swift

  2.2 Operation Queue Actor

  OperationQueue.swift
  actor OperationQueue {
      private var tail: Task<Void, Never>?

      func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
          let previous = tail

          let current = Task.detached { () throws -> T in
              _ = await previous?.value
              return try await operation()
          }

          tail = Task.detached {
              _ = try? await current.value
          }

          return try await current.value
      }
  }

  2.3 Sync Classes

  PlaylistSync.swift
  final class PlaylistSync {
      private let db = MixBridgeDB.shared
      private let convex = ConvexService.shared
      private let operationQueue = OperationQueue()

      func syncPlaylists(userId: String) async throws {
          try await operationQueue.run {
              // 1. Fetch from API
              let scPlaylists = try await self.convex.getPlaylists(userId: userId)

              // 2. Convert and save to DB
              try await self.db.writer.write { db in
                  for scPlaylist in scPlaylists {
                      var persisted = PersistedPlaylist(
                          id: String(scPlaylist.id),
                          name: scPlaylist.title,
                          creator: scPlaylist.user.username,
                          artwork: scPlaylist.primaryArtworkUrl,
                          trackCount: scPlaylist.track_count ?? 0,
                          lastUpdated: Date(),
                          soundCloudData: try? JSONEncoder().encode(scPlaylist)
                      )
                      try persisted.upsert(db)
                  }
              }
          }
      }

      func syncPlaylistTracks(userId: String, playlistId: String) async throws {
          try await operationQueue.run {
              // 1. Fetch tracks
              let tracks = try await self.convex.getPlaylistTracks(
                  userId: userId,
                  playlistId: playlistId
              )

              // 2. Save tracks and junction records
              try await self.db.writer.write { db in
                  // Clear existing junction records
                  try PlaylistTrack
                      .filter(PlaylistTrack.Columns.playlistId == playlistId)
                      .deleteAll(db)

                  for (index, scTrack) in tracks.enumerated() {
                      // Save track
                      var track = PersistedTrack(from: scTrack)
                      try track.upsert(db)

                      // Create junction record with position
                      var junction = PlaylistTrack(
                          playlistId: playlistId,
                          trackId: String(scTrack.id),
                          position: index
                      )
                      try junction.insert(db)
                  }

                  // Update playlist track count
                  try PersistedPlaylist
                      .filter(PersistedPlaylist.Columns.id == playlistId)
                      .updateAll(db, PersistedPlaylist.Columns.trackCount.set(to: tracks.count))
              }
          }
      }
  }

  HistorySync.swift
  final class HistorySync {
      private let db = MixBridgeDB.shared
      private let convex = ConvexService.shared
      private let operationQueue = OperationQueue()

      func loadHistory(userId: String) async throws {
          try await operationQueue.run {
              let history = try await self.convex.getPlayHistory(userId: userId, limit: 50)

              try await self.db.writer.write { db in
                  for playItem in history {
                      // Save track
                      var track = PersistedTrack(from: playItem.trackData)
                      try track.upsert(db)

                      // Upsert play history
                      var historyRecord = PlayHistory(
                          trackId: String(playItem.trackData.id),
                          playCount: 1,
                          lastPlayedPosition: playItem.playbackPosition ?? 0,
                          listenedPercentage: playItem.listenedPercentage ?? 0,
                          createdAt: Date(),
                          updatedAt: Date()
                      )

                      // Increment play count if exists
                      if let existing = try PlayHistory.fetchOne(db, key: historyRecord.trackId) {
                          historyRecord.playCount = existing.playCount + 1
                          historyRecord.createdAt = existing.createdAt
                      }

                      try historyRecord.upsert(db)
                  }
              }
          }
      }

      // Optimistic update for immediate UI feedback
      func addToHistory(_ track: Track, soundCloudTrack: SoundCloudTrack) async throws {
          let now = Date()

          try await db.writer.write { db in
              // Save track
              var persisted = PersistedTrack(from: soundCloudTrack)
              try persisted.upsert(db)

              // Update or create history
              var history: PlayHistory
              if let existing = try PlayHistory.fetchOne(db, key: track.id) {
                  history = existing
                  history.playCount += 1
                  history.updatedAt = now
              } else {
                  history = PlayHistory(
                      trackId: track.id,
                      playCount: 1,
                      lastPlayedPosition: 0,
                      listenedPercentage: 0,
                      createdAt: now,
                      updatedAt: now
                  )
              }
              try history.upsert(db)
          }

          // Async sync to backend (fire-and-forget)
          Task(priority: .utility) {
              try? await convex.addPlay(
                  userId: AuthManager.shared.currentUserId ?? "",
                  track: soundCloudTrack,
                  sessionId: UUID().uuidString,
                  queueIndex: nil
              )
          }
      }
  }

  ---
  Phase 3: Refactor ViewModels with ValueObservation

  3.1 New ViewModel Pattern

  LibraryViewModel.swift
  @Observable
  @MainActor
  final class LibraryViewModel {
      private let db = MixBridgeDB.shared
      private let playlistSync = PlaylistSync()

      // Observable state - updated by database observation
      private(set) var playlists: [Playlist] = []
      private(set) var isLoading = false
      private(set) var error: Error?

      init() {}

      // Start observing database - called from view's .task
      func observeDatabase() async {
          let observation = ValueObservation.tracking { db in
              try PersistedPlaylist
                  .order(PersistedPlaylist.Columns.lastUpdated.desc)
                  .fetchAll(db)
          }
          .values(in: db.reader)

          do {
              for try await persistedPlaylists in observation {
                  self.playlists = persistedPlaylists.map { $0.toPlaylist() }
              }
          } catch {
              self.error = error
          }
      }

      // Refresh from network - called on pull-to-refresh or first appear
      func refresh() async {
          guard let userId = AuthManager.shared.currentUserId else { return }

          isLoading = playlists.isEmpty

          do {
              try await playlistSync.syncPlaylists(userId: userId)
              // No need to update playlists manually - ValueObservation handles it
          } catch {
              self.error = error
          }

          isLoading = false
      }
  }

  HomeViewModel.swift
  @Observable
  @MainActor
  final class HomeViewModel {
      private let db = MixBridgeDB.shared
      private let historySync = HistorySync()

      private(set) var playHistory: [TrackItem] = []
      private(set) var isLoading = false

      func observeDatabase() async {
          let observation = ValueObservation.tracking { db in
              try PlayHistory
                  .including(required: PlayHistory.track)
                  .order(PlayHistory.Columns.updatedAt.desc)
                  .limit(100)
                  .fetchAll(db)
          }
          .values(in: db.reader)

          do {
              for try await historyRecords in observation {
                  self.playHistory = historyRecords.compactMap { record in
                      guard let track = record.track else { return nil }
                      return TrackItem(
                          track: track.toTrack(),
                          soundCloudTrack: track.soundCloudTrack,
                          playCount: record.playCount,
                          lastPlayedPosition: record.lastPlayedPosition,
                          listenedPercentage: record.listenedPercentage
                      )
                  }
              }
          } catch {
              logError(.db, "Failed to observe history: \(error)")
          }
      }

      func refresh() async {
          guard let userId = AuthManager.shared.currentUserId else { return }
          isLoading = playHistory.isEmpty
          try? await historySync.loadHistory(userId: userId)
          isLoading = false
      }
  }

  3.2 Updated View Pattern

  LibraryView.swift (refactored)
  struct LibraryView: View {
      @State private var viewModel = LibraryViewModel()
      @Environment(AuthManager.self) private var authManager

      var body: some View {
          NavigationStack {
              content
                  .navigationTitle("Library")
                  .refreshable {
                      await viewModel.refresh()
                  }
                  // Start database observation
                  .task {
                      await viewModel.observeDatabase()
                  }
                  // Fetch fresh data on first appear
                  .task {
                      await viewModel.refresh()
                  }
          }
      }

      @ViewBuilder
      private var content: some View {
          // No loading check needed for cached data!
          // Only show loading if truly empty (first install)
          if viewModel.isLoading && viewModel.playlists.isEmpty {
              ProgressView()
          } else if viewModel.playlists.isEmpty {
              emptyState
          } else {
              playlistGrid
          }
      }

      private var playlistGrid: some View {
          ScrollView {
              LazyVGrid(columns: [.init(), .init(), .init()], spacing: 20) {
                  ForEach(viewModel.playlists) { playlist in
                      PlaylistCard(playlist: playlist)
                  }
              }
              .padding()
          }
      }
  }

  ---
  Phase 4: Update App Initialization

  4.1 Refactored App Entry

  mixbridgeApp.swift (refactored)
  @main
  struct mixbridgeApp: App {
      @State private var authManager = AuthManager.shared
      @State private var queueManager = QueueManager.shared

      // Remove PreloadedDataStore - views now use ViewModels with DB observation

      @State private var isAppInitialized = false

      var body: some Scene {
          WindowGroup {
              ZStack {
                  if authManager.isAuthenticated {
                      ContentView()
                  } else {
                      OnboardingView()
                  }

                  if !isAppInitialized {
                      SplashView()
                  }
              }
              .environment(authManager)
              .environment(queueManager)
              .task {
                  // Auth check only - no data preloading needed!
                  await authManager.checkAuthStatus()

                  // Short delay for splash animation
                  try? await Task.sleep(for: .milliseconds(400))

                  withAnimation {
                      isAppInitialized = true
                  }
              }
          }
      }
  }

  4.2 Remove Preloader

  The AppDataPreloader and PreloadedDataStore can be deleted once all views are migrated to the new ViewModel pattern with database observation.

  ---
  Phase 5: File Changes Summary

  Files to Create

  Database/
  ├── MixBridgeDB.swift
  ├── Persistence.swift
  ├── MigratableTable.swift
  ├── Migrations/AllTables.swift
  └── Models/
      ├── PersistedPlaylist.swift
      ├── PersistedTrack.swift
      ├── PlayHistory.swift
      ├── PlaylistTrack.swift
      └── LikedTrack.swift

  Sync/
  ├── OperationQueue.swift
  ├── PlaylistSync.swift
  ├── HistorySync.swift
  ├── LikedSync.swift
  └── Repository/
      └── [sync repositories]

  ViewModels/
  ├── LibraryViewModel.swift
  ├── HomeViewModel.swift
  ├── PlaylistDetailViewModel.swift
  ├── LikedViewModel.swift
  └── SearchViewModel.swift

  Files to Modify

  - mixbridgeApp.swift - Remove preloader, simplify initialization
  - LibraryView.swift - Use LibraryViewModel with .task observation
  - HomeView.swift - Use HomeViewModel with .task observation
  - PlaylistDetailView.swift - Use PlaylistDetailViewModel
  - LikedView.swift - Use LikedViewModel
  - PlaybackCoordinator.swift - Use HistorySync.addToHistory() for optimistic updates

  Files to Delete

  - Services/AppDataPreloader.swift
  - Services/PreloadedDataStore.swift

  ---
  Phase 6: Migration Steps

  1. Add GRDB dependency to Package.swift
  2. Create Database layer (Phase 1)
  3. Create Sync layer (Phase 2)
  4. Migrate one view at a time (start with HomeView)
  5. Test each view before moving to next
  6. Remove old preloader once all views migrated
  7. Clean up unused code

  ---
  Expected Results

  | Metric                | Before                   | After                   |
  |-----------------------|--------------------------|-------------------------|
  | Cold start to content | 1-3s (network dependent) | <100ms (from SQLite)    |
  | Network dependency    | Required for any content | Background refresh only |
  | Memory usage          | All data in RAM          | On-demand from SQLite   |
  | Offline support       | None                     | Full read access        |
  | Code complexity       | Preloader tiers          | Simple sync classes     |

  This architecture matches Phia's patterns and will provide the instant loading experience you're looking for.

⏺ ---
  Summary

  I've analyzed both codebases in depth using parallel subagents and created a comprehensive refactoring plan. Here are the key findings:

  Why Phia is Faster

  1. Local-first architecture: Phia uses GRDB (SQLite) to persist ALL data locally
  2. Database observation: Views use ValueObservation to reactively stream changes
  3. Splash waits for auth, not data: Views render with cached data instantly
  4. Background sync: Network fetches update the database, which automatically updates UI

  What MixBridge Needs

  1. Add GRDB database layer - persist playlists, tracks, history to SQLite
  2. Create sync engine - classes that fetch from Convex and write to local DB
  3. Refactor ViewModels - use ValueObservation instead of PreloadedDataStore
  4. Remove preloader - views read from DB immediately, sync in background

  Key Pattern Differences

  | Aspect           | MixBridge (Current)          | Phia (Target)                  |
  |------------------|------------------------------|--------------------------------|
  | Data storage     | In-memory PreloadedDataStore | SQLite via GRDB                |
  | View data source | Environment object           | ViewModel with DB observation  |
  | Initial load     | Wait for network             | Read from local cache          |
  | State updates    | Manual store updates         | Automatic via ValueObservation |
  | Offline support  | None                         | Full read access               |

  The refactoring plan above provides all the code needed to implement this. Would you like me to start implementing any specific phase?
