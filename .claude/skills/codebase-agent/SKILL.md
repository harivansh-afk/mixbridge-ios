---
name: codebase-agent
description: |
  Expert coding agent for this codebase. Learns from every session to improve
  code quality, catch edge cases, and apply proven patterns. Use for ANY coding
  task: writing, debugging, refactoring, testing. Accumulates project knowledge.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Codebase Expert Agent

You are an expert coding agent that learns and improves over time.

## Accumulated Learnings

Reference [learnings.md](learnings.md) for patterns, failures, and insights
discovered in previous sessions. Apply these to avoid repeating mistakes
and leverage proven approaches.

## Behavior

1. **Check learnings first**: Before implementing, scan learnings.md for relevant patterns and failures
2. **Apply proven patterns**: Use approaches that worked in past sessions
3. **Follow conventions**: Adhere to project conventions discovered in learnings
4. **Note discoveries**: When you find something new (pattern, failure, edge case), mention it

## Codebase Context

### Architecture

**mixbridge** is a native iOS music streaming app that integrates with SoundCloud. It follows a SwiftUI-first architecture with:

- **Observable pattern**: Uses Swift's `@Observable` macro for state management (managers are singletons with `.shared`)
- **Service layer**: Backend communication via `ConvexService` (connects to Convex backend at mixbridge.app)
- **Coordinator pattern**: `PlaybackCoordinator` handles all audio playback including mix/crossfade mode
- **Local-first sync engine**: GRDB-backed SQLite with `PlaylistSync`, `HistorySync`, `LikedSync` for offline-first data with Convex backend synchronization

### Tech Stack

- **Language**: Swift 5.9+ (iOS 18+, uses new Swift concurrency features)
- **UI Framework**: SwiftUI (declarative, uses `@Observable`, `@Environment`, `@State`)
- **Audio**: AVFoundation (`AVQueuePlayer`, `AVAudioEngine` for mix mode)
- **Database**: GRDB (SQLite wrapper with reactive ValueObservation)
- **Backend**: Convex (BaaS) - queries, mutations, actions via REST API
- **Auth**: OAuth 2.0 via SoundCloud, JWT session tokens stored in Keychain
- **Animation**: Lottie (via SPM)

### Key Directories

- `mixbridge/` - Main source directory
  - `Auth/` - Authentication (AuthManager, KeychainManager, SessionTokenDecoder)
  - `Components/` - Reusable SwiftUI views (TrackRow, PlaylistCard, ExpandedMusicPlayer, etc.)
  - `Extensions/` - Swift/SwiftUI extensions (Color+Theme, String+SoundCloud, View+Animations)
  - `Models/` - Data models (Track, Playlist, SoundCloudModels, PlayerState, MixSettings)
  - `Services/` - Business logic (ConvexService, PlaybackCoordinator, QueueManager, etc.)
  - `Sync/` - Local-first sync engine (PlaylistSync, HistorySync, LikedSync, SyncOperationQueue)
  - `Utilities/` - Helpers (HapticManager, LogManager, Debouncer, ImageCacheManager)
  - `Views/` - Screen views organized by feature (Home, Library, Search, Settings, etc.)
  - `ViewModels/` - Observable ViewModels with GRDB database observation
  - `Onboarding/` - Onboarding flow views
- `Packages/` - Local Swift packages for modular architecture
  - `MixBridgeDomain/` - Pure Swift domain models (no external dependencies)
  - `MixBridgeDB/` - GRDB database layer with migrations and model extensions

### Build & Test Commands

- Build: `xcodebuild -project mixbridge.xcodeproj -scheme mixbridge -destination 'platform=iOS Simulator,name=iPhone 16'`
- Tests: No dedicated test target currently exists
- CI: `ci_scripts/ci_post_clone.sh` for Xcode Cloud

### Conventions

1. **Singletons with `.shared`**: Managers use `static let shared = ManagerName()` pattern
2. **@Observable macro**: Modern Swift observation for state (not ObservableObject)
3. **Environment injection**: Managers passed via `.environment(Manager.shared)`
4. **Haptic feedback**: Use `HapticManager.light()`, `.medium()`, `.selection()` for interactions
5. **Async/await**: All async operations use Swift concurrency (no completion handlers)
6. **File naming**: PascalCase for types, feature-organized directories
7. **Preview providers**: Both light and dark mode previews for views
8. **Adaptive colors**: Use `Color.adaptive*` extensions for theme support
9. **Error handling**: Typed errors (e.g., `ConvexError`, `PlayerState.PlaybackError`)
10. **Logging**: Use `logInfo()`, `logWarning()`, `logError()`, `logDebug()` from LogManager
