#!/bin/bash
# Shared prompts for ralph test generation scripts

SETUP_PROMPT="You are setting up the test infrastructure for the mixbridge-ios project.

TASK: Create the XCTest target and test infrastructure.

1. First, check if a test target exists in the Xcode project
2. If no test target exists:
   - Create the directory structure: mixbridgeTests/
   - Create a basic XCTestCase template file
   - Add test utilities (mocks, helpers, fixtures)
3. Create test naming conventions document
4. Set up test isolation patterns (dependency injection helpers)

Files to create:
- mixbridgeTests/TestHelpers/MockConvexService.swift
- mixbridgeTests/TestHelpers/MockAuthManager.swift
- mixbridgeTests/TestHelpers/TestFixtures.swift
- mixbridgeTests/TestHelpers/XCTestCase+Async.swift

When complete and all test infrastructure is ready, end your response with: <promise>COMPLETE</promise>"

SERVICES_PROMPT="You are writing unit tests for the Services layer of mixbridge-ios.

TASK: Write comprehensive unit tests for core services.

Target services (in priority order):
1. QueueManager.swift - Queue state management, add/remove/reorder operations
2. StreamURLCache.swift - URL caching logic, expiration, invalidation
3. DownloadManager.swift - Download state machine, progress tracking
4. PlaybackPositionTracker.swift - Position tracking accuracy
5. TrackPrefetcher.swift - Prefetch logic and cancellation
6. RecentSearchManager.swift - Search history persistence

For each service:
- Test happy path scenarios
- Test error handling
- Test edge cases (empty state, maximum capacity, etc.)
- Use dependency injection with mocks
- Follow naming convention: test_methodName_condition_expectedResult

Create test files:
- mixbridgeTests/Services/QueueManagerTests.swift
- mixbridgeTests/Services/StreamURLCacheTests.swift
- mixbridgeTests/Services/DownloadManagerTests.swift
- mixbridgeTests/Services/PlaybackPositionTrackerTests.swift
- mixbridgeTests/Services/TrackPrefetcherTests.swift
- mixbridgeTests/Services/RecentSearchManagerTests.swift

When all service tests are written and compile, end with: <promise>COMPLETE</promise>"

VIEWMODELS_PROMPT="You are writing unit tests for ViewModels in mixbridge-ios.

TASK: Write unit tests for all ViewModels following MVVM testing patterns.

Target ViewModels:
1. HomeViewModel.swift - Play history loading, state management
2. LibraryViewModel.swift - Library data fetching and filtering
3. PlaylistDetailViewModel.swift - Playlist operations (add/remove tracks)
4. CreatePlaylistViewModel.swift - Playlist creation validation
5. EditPlaylistViewModel.swift - Edit operations and validation
6. LikedViewModel.swift - Like/unlike operations, sync

For each ViewModel:
- Test @Published property updates
- Test async loading states (loading -> loaded -> error)
- Test user action handlers
- Mock all service dependencies
- Test state consistency after operations

Create test files:
- mixbridgeTests/ViewModels/HomeViewModelTests.swift
- mixbridgeTests/ViewModels/LibraryViewModelTests.swift
- mixbridgeTests/ViewModels/PlaylistDetailViewModelTests.swift
- mixbridgeTests/ViewModels/CreatePlaylistViewModelTests.swift
- mixbridgeTests/ViewModels/EditPlaylistViewModelTests.swift
- mixbridgeTests/ViewModels/LikedViewModelTests.swift

When all ViewModel tests compile and cover key scenarios, end with: <promise>COMPLETE</promise>"

MODELS_PROMPT="You are writing unit tests for Models in mixbridge-ios.

TASK: Write unit tests for data models and transformations.

Target Models:
1. Track.swift - Track initialization, equality, encoding/decoding
2. Playlist.swift - Playlist operations, track ordering
3. PlayerState.swift (and extensions) - State transitions, persistence
4. PlaybackQueue.swift - Queue operations, shuffle, repeat
5. MixSettings.swift - Settings validation, defaults
6. SoundCloudModels.swift - API response parsing
7. ConvexDataModels.swift - Backend model mapping

Test patterns:
- Codable encoding/decoding roundtrips
- Equatable/Hashable correctness
- Edge cases (nil values, empty arrays, invalid data)
- Model transformations between layers
- State machine transitions for PlayerState

Create test files:
- mixbridgeTests/Models/TrackTests.swift
- mixbridgeTests/Models/PlaylistTests.swift
- mixbridgeTests/Models/PlayerStateTests.swift
- mixbridgeTests/Models/PlaybackQueueTests.swift
- mixbridgeTests/Models/MixSettingsTests.swift
- mixbridgeTests/Models/SoundCloudModelsTests.swift
- mixbridgeTests/Models/ConvexDataModelsTests.swift

When all model tests are complete and pass, end with: <promise>COMPLETE</promise>"

UTILS_PROMPT="You are writing unit tests for Utilities in mixbridge-ios.

TASK: Write unit tests for utility classes.

Target Utilities:
1. ImageCacheManager.swift - Cache operations, memory limits, cleanup
2. HapticManager.swift - Haptic generation (mock UIKit)
3. LogManager.swift - Log levels, filtering, output
4. BackgroundExecutor.swift - Background task execution
5. KeychainManager.swift - Secure storage operations

Test patterns:
- Singleton access patterns
- Thread safety
- Memory management
- Error handling for I/O operations

Create test files:
- mixbridgeTests/Utilities/ImageCacheManagerTests.swift
- mixbridgeTests/Utilities/HapticManagerTests.swift
- mixbridgeTests/Utilities/LogManagerTests.swift
- mixbridgeTests/Utilities/BackgroundExecutorTests.swift
- mixbridgeTests/Utilities/KeychainManagerTests.swift

When all utility tests compile and pass, end with: <promise>COMPLETE</promise>"

AUTH_PROMPT="You are writing unit tests for Authentication in mixbridge-ios.

TASK: Write unit tests for auth-related classes.

Target Auth:
1. AuthManager.swift - Auth state machine, token management
2. SpotifyAuthManager.swift - Spotify OAuth flow (mock network)
3. SessionTokenDecoder.swift - JWT decoding, expiration checking

Test patterns:
- Auth state transitions (logged out -> logging in -> logged in -> error)
- Token refresh logic
- Secure token storage integration
- Error recovery scenarios
- Session expiration handling

Create test files:
- mixbridgeTests/Auth/AuthManagerTests.swift
- mixbridgeTests/Auth/SpotifyAuthManagerTests.swift
- mixbridgeTests/Auth/SessionTokenDecoderTests.swift

When all auth tests are complete, end with: <promise>COMPLETE</promise>"

SYNC_PROMPT="You are writing unit tests for Sync modules in mixbridge-ios.

TASK: Write unit tests for data synchronization classes.

Target Sync modules:
1. PlaylistSync.swift - Playlist sync logic, conflict resolution
2. LikedSync.swift - Liked tracks sync
3. QueueSync.swift - Queue state sync
4. HistorySync.swift - Play history sync
5. OperationQueue.swift - Background operation scheduling

Test patterns:
- Sync state machines (idle -> syncing -> synced -> error)
- Conflict resolution strategies
- Offline queue handling
- Retry logic
- Incremental vs full sync

Create test files:
- mixbridgeTests/Sync/PlaylistSyncTests.swift
- mixbridgeTests/Sync/LikedSyncTests.swift
- mixbridgeTests/Sync/QueueSyncTests.swift
- mixbridgeTests/Sync/HistorySyncTests.swift
- mixbridgeTests/Sync/OperationQueueTests.swift

When all sync tests are complete, end with: <promise>COMPLETE</promise>"

DB_PROMPT="You are writing unit tests for the MixBridgeDB package.

TASK: Write unit tests for database operations.

Target: Packages/MixBridgeDB/

Test patterns:
1. CRUD operations for each model type
2. Migration testing (schema upgrades)
3. Query performance (within thresholds)
4. Transaction handling
5. Concurrent access safety

Models to test:
- PersistedTrack
- PersistedPlaylist
- PersistedQueue/PersistedQueueTrack
- PlaylistTrack
- LikedTrack/LikedPlaylist
- DownloadedTrack
- PlayHistory
- PersistedUserProfile

Create tests in:
- Packages/MixBridgeDB/Tests/MixBridgeDBTests/

When database tests are complete and pass, end with: <promise>COMPLETE</promise>"

export SETUP_PROMPT SERVICES_PROMPT VIEWMODELS_PROMPT MODELS_PROMPT UTILS_PROMPT AUTH_PROMPT SYNC_PROMPT DB_PROMPT
