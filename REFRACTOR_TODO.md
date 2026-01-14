# Mixbridge iOS — Refactor TODO (Axiom-aligned)

This is the step-by-step refactor queue. Goal: one focused PR at a time, easy to review + rollback.

## PR Rules

- One PR = one theme (no drive-by cleanup).
- Keep diffs small; avoid “reformat the world”.
- Prefer architecture/perf wins that reduce view updates and global coupling.
- After each PR: smoke test app flows touched (Home/Library/Search/Player/Downloads) and fix regressions before moving on.

## PR Queue (in order)

### PR 01 — Inject `PlayerState` via environment (reduce singleton coupling) ✅

- Add `PlayerState.shared` to app environment in `mixbridge/mixbridgeApp.swift`.
- Replace direct `PlayerState.shared` usages in views with `@Environment(PlayerState.self)` / `@Bindable`.
- Target files: `mixbridge/mixbridgeApp.swift`, `mixbridge/ContentView.swift`, `mixbridge/Components/ExpandedMusicPlayer.swift`, `mixbridge/Views/Settings/AutomixSettingsView.swift`.
- Acceptance: app builds; mini player + expanded player + play/pause/next/prev all still work.

### PR 02 — Fix `@StateObject`-singleton anti-pattern for `DownloadManager` ✅

- Provide `DownloadManager.shared` via `environmentObject` at the app root.
- Replace `@StateObject private var downloadManager = DownloadManager.shared` with `@EnvironmentObject var downloadManager: DownloadManager`.
- Target files: `mixbridge/mixbridgeApp.swift`, `mixbridge/Components/TrackRow.swift`, `mixbridge/Views/Library/DownloadsView.swift`, `mixbridge/Views/Playlist/PlaylistDetailView.swift`.
- Acceptance: downloads list renders; “Download All” still works; download status updates in rows.

### PR 03 — Remove `ForEach(Array(...enumerated()))` (stable identity, fewer allocations) ✅

- Introduce an “indexed row” model (e.g. `IndexedTrackItem`, `IndexedPlaylist`) built in the ViewModel when data changes.
- Update views to `ForEach(viewModel.rows)` using stable IDs (NOT index-based IDs).
- Target files (minimum): `mixbridge/Views/Home/HomeView.swift`, `mixbridge/ViewModels/HomeViewModel.swift`.
- Follow-up PRs should apply the same pattern to:
  - `mixbridge/Views/Playlist/PlaylistDetailView.swift` + `mixbridge/ViewModels/PlaylistDetailViewModel.swift`
  - `mixbridge/Views/Liked/LikedView.swift`
  - `mixbridge/Views/Library/LibraryView.swift`
  - `mixbridge/Views/Search/SearchView.swift`
  - `mixbridge/Views/Library/AllSongsView.swift`, `mixbridge/Views/Library/AllArtistsView.swift`, `mixbridge/Views/Library/ArtistDetailView.swift`, `mixbridge/Views/Library/DownloadsView.swift`
  - `mixbridge/Components/ExpandedMusicPlayer.swift`
- Acceptance: lists no longer allocate “context arrays” in view body; row selection and playback context still correct.

### PR 04 — Consolidate multi-`.task` lifecycles (structured concurrency, predictable ordering) ✅

- Replace multiple `.task {}` blocks per screen with a single `.task(id:)` that:
  - starts GRDB observation(s)
  - runs refresh/profile load in a predictable sequence
- Target files (minimum): `mixbridge/Views/Home/HomeView.swift`, `mixbridge/Views/Liked/LikedView.swift`, `mixbridge/Views/Library/LibraryView.swift`, `mixbridge/Views/Playlist/PlaylistDetailView.swift`.
- Acceptance: no double-fetching; leaving/re-entering screens doesn’t spawn duplicate observers.

### PR 05 — Navigation hygiene: remove deprecated `NavigationView` and “hidden NavigationLink” overlays ✅

- Convert `NavigationView` → `NavigationStack`.
- Replace “invisible NavigationLink in a ZStack” with a real `NavigationLink` row or `navigationDestination`.
- Target files: `mixbridge/Components/AccountBottomSheet.swift`.
- Acceptance: account sheet navigation works; no regressions in dismissal behavior/detents.

### PR 06 — Mix crossfade timer: remove per-tick `Task` creation

- `Timer.scheduledTimer` already fires on main run loop; call `updateFade()` directly (no `Task { @MainActor in … }`).
- Consider adding timer tolerance (if acceptable) and ensure invalidation happens on stop/deinit.
- Target files: `mixbridge/Services/MixPlaybackEngine.swift`.
- Acceptance: crossfade remains smooth; no CPU spike from spawning tasks at 60Hz.

### PR 07 — Now Playing / Remote Commands: match Axiom “expert checklist”

- Keep strong references to command targets returned by `addTarget`.
- Ensure teardown removes targets appropriately (and doesn’t leak).
- Decide whether to adopt `MPNowPlayingSession` (iOS 16+) vs manual `MPNowPlayingInfoCenter` updates; document choice.
- Target files: `mixbridge/Models/PlayerState.swift`.
- Acceptance: lock screen/Control Center commands work reliably; Now Playing doesn’t disappear after backgrounding.

### PR 08 — Reduce `Task.detached` sprawl; introduce background workers where needed

- Replace `Task.detached` inside `@MainActor` types with:
  - `Task {}` + call into an actor/service that is *not* main-actor isolated, or
  - dedicated worker actor for queue sync/persist, history writes, prefetching.
- Revisit `mixbridge/Utilities/BackgroundExecutor.swift` and `mixbridge/Sync/OperationQueue.swift` detached semantics explicitly (keep only where cancellation independence is truly required).
- Target files: `mixbridge/Services/QueueManager.swift`, `mixbridge/Services/PlaybackCoordinator.swift`, `mixbridge/Utilities/BackgroundExecutor.swift`, `mixbridge/Sync/OperationQueue.swift`.
- Acceptance: fewer cross-actor hops; cancellation behavior is intentional and documented.

### PR 09 — Split `PlayerState` (stop being a “god object”)

- Extract:
  - Audio session config + interruptions/route changes
  - Now Playing + remote command registration
  - Persistence/settings (UserDefaults)
  - Crossfade visual state (if it shouldn’t live in the core player model)
- Keep `PlayerState` as the UI-facing state bridge and delegate target.
- Target files: `mixbridge/Models/PlayerState.swift` (+ new files under `mixbridge/Models/PlayerState/`).
- Acceptance: no behavior regression; fewer reasons for unrelated UI updates.

### PR 10 — Split `ExpandedMusicPlayer` (large view decomposition)

- Extract subviews (carousel, background, queue sheet, transport controls) with stable inputs.
- Move non-UI computations out of the view body where possible.
- Target file: `mixbridge/Components/ExpandedMusicPlayer.swift` (+ new component files).
- Acceptance: same UX; simpler view update graph; easier profiling.

### PR 11 — Remove duplicated UI patterns (components)

- Extract reusable components:
  - toolbar profile button/avatar
  - shared artwork placeholder and artwork loader view
- Target files: `mixbridge/Views/Home/HomeView.swift`, `mixbridge/Views/Library/LibraryView.swift`, `mixbridge/Views/Playlist/PlaylistDetailView.swift`, `mixbridge/Components/TrackRow.swift`.
- Acceptance: one canonical implementation; consistent loading/fallback visuals.

## Parking Lot (do later / only if needed)

- GRDB observation coalescing / removeDuplicates/debounce for heavy tables (only after profiling).
- Metal/MTKView frame pacing improvements (only if instruments shows GPU/display bottlenecks).
- Accessibility sweep (replace gesture-only affordances with semantic controls).
