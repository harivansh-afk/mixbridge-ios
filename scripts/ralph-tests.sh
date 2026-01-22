#!/bin/bash
set -e

# Ralph Test Generator for mixbridge-ios
# Based on Matt Pocock's Ralph Wiggum pattern
# Usage: ./ralph-tests.sh <iterations> [module]

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [module]"
  echo "Modules: setup, services, viewmodels, models, utils, auth, sync, db, all"
  exit 1
fi

ITERATIONS=$1
MODULE=${2:-all}
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Ensure progress file exists
PROGRESS_FILE="$PROJECT_ROOT/test-progress.txt"
touch "$PROGRESS_FILE"

run_ralph() {
  local prd_file="$1"
  local max_iterations="$2"
  local module_name="$3"

  for ((i=1; i<=$max_iterations; i++)); do
    echo ""
    echo "=============================================="
    echo "=== RALPH ITERATION $i of $max_iterations ($module_name) ==="
    echo "=============================================="
    echo ""

    # Run Claude with PRD and progress context
    result=$(claude --dangerously-skip-permissions -p \
"@$prd_file @$PROGRESS_FILE

You are writing tests for mixbridge-ios.

PROCESS:
1. Read the PRD to see what tests need to be written.
2. Read test-progress.txt to see what's already done.
3. Choose the HIGHEST PRIORITY incomplete task - not necessarily the first one.
   Prioritize: core services > auth > models > viewmodels > utils > sync
4. READ the source file thoroughly before writing tests.
5. Create the test file with comprehensive tests.
6. Run feedback loops: check that Swift files compile (swift build or xcodebuild).
7. Append your progress to test-progress.txt with:
   - What you completed
   - Files created
   - Any issues encountered
8. Make a git commit of your changes.

IMPORTANT:
- ONLY WORK ON A SINGLE TEST FILE PER ITERATION.
- Write quality tests: happy path, error cases, edge cases.
- Use mocks from mixbridgeTests/TestHelpers/ if they exist.

If ALL tests in the PRD are complete, output: <promise>COMPLETE</promise>
")

    echo "$result"

    # Check for completion
    if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
      echo ""
      echo "=============================================="
      echo "ALL TESTS COMPLETE after $i iteration(s)"
      echo "=============================================="
      return 0
    fi

    if [ $i -lt $max_iterations ]; then
      echo ""
      echo "--- Iteration $i done, continuing ---"
      sleep 2
    fi
  done

  echo ""
  echo "=============================================="
  echo "Reached max iterations ($max_iterations)"
  echo "=============================================="
}

# Create PRD files for each module
create_prd() {
  local module=$1
  local prd_file="$PROJECT_ROOT/.ralph/prd-$module.md"

  mkdir -p "$PROJECT_ROOT/.ralph"

  case $module in
    setup)
      cat > "$prd_file" << 'EOF'
# Test Infrastructure PRD

## Tasks

- [ ] Create mixbridgeTests/TestHelpers/MockConvexService.swift
      Mock the ConvexService for testing. Read mixbridge/Services/ConvexService.swift first.

- [ ] Create mixbridgeTests/TestHelpers/MockAuthManager.swift
      Mock auth state and token management. Read mixbridge/Auth/AuthManager.swift first.

- [ ] Create mixbridgeTests/TestHelpers/TestFixtures.swift
      Reusable test data: sample tracks, playlists, users. Read the Models/ directory.

- [ ] Create mixbridgeTests/TestHelpers/XCTestCase+Async.swift
      Async testing utilities: waitForAsync, assertThrowsAsync, assertEventually.

- [ ] Create mixbridgeTests/SampleTests.swift
      Sample test demonstrating how to use mocks and fixtures.

## Completion Criteria
All 5 files created with working Swift code.
EOF
      ;;

    services)
      cat > "$prd_file" << 'EOF'
# Services Tests PRD

## Tasks (Priority Order)

- [ ] mixbridgeTests/Services/QueueManagerTests.swift
      CRITICAL: Core queue logic. Test add/remove/reorder, shuffle, repeat modes.
      Source: mixbridge/Services/QueueManager.swift

- [ ] mixbridgeTests/Services/StreamURLCacheTests.swift
      HIGH: URL caching. Test cache hits, misses, expiration, invalidation.
      Source: mixbridge/Services/StreamURLCache.swift

- [ ] mixbridgeTests/Services/DownloadManagerTests.swift
      HIGH: Download state machine. Test start/pause/resume/cancel, progress tracking.
      Source: mixbridge/Services/DownloadManager.swift

- [ ] mixbridgeTests/Services/PlaybackPositionTrackerTests.swift
      MEDIUM: Position tracking accuracy, persistence.
      Source: mixbridge/Services/PlaybackPositionTracker.swift

- [ ] mixbridgeTests/Services/TrackPrefetcherTests.swift
      MEDIUM: Prefetch logic, cancellation, priority.
      Source: mixbridge/Services/TrackPrefetcher.swift

- [ ] mixbridgeTests/Services/RecentSearchManagerTests.swift
      LOW: Search history CRUD, limits.
      Source: mixbridge/Models/RecentSearchManager.swift

## Completion Criteria
All 6 test files with comprehensive coverage of public APIs.
EOF
      ;;

    viewmodels)
      cat > "$prd_file" << 'EOF'
# ViewModel Tests PRD

## Tasks (Priority Order)

- [ ] mixbridgeTests/ViewModels/PlaylistDetailViewModelTests.swift
      HIGH: Playlist CRUD operations, track management.
      Source: mixbridge/ViewModels/PlaylistDetailViewModel.swift

- [ ] mixbridgeTests/ViewModels/HomeViewModelTests.swift
      MEDIUM: Play history loading, state management.
      Source: mixbridge/ViewModels/HomeViewModel.swift

- [ ] mixbridgeTests/ViewModels/LikedViewModelTests.swift
      MEDIUM: Like/unlike operations, sync state.
      Source: mixbridge/ViewModels/LikedViewModel.swift

- [ ] mixbridgeTests/ViewModels/LibraryViewModelTests.swift
      MEDIUM: Library data fetching, filtering.
      Source: mixbridge/ViewModels/LibraryViewModel.swift

- [ ] mixbridgeTests/ViewModels/CreatePlaylistViewModelTests.swift
      LOW: Playlist creation validation.
      Source: mixbridge/ViewModels/CreatePlaylistViewModel.swift

- [ ] mixbridgeTests/ViewModels/EditPlaylistViewModelTests.swift
      LOW: Edit validation, save operations.
      Source: mixbridge/ViewModels/EditPlaylistViewModel.swift

## Completion Criteria
All 6 test files testing @Published properties and async operations.
EOF
      ;;

    models)
      cat > "$prd_file" << 'EOF'
# Models Tests PRD

## Tasks (Priority Order)

- [ ] mixbridgeTests/Models/TrackTests.swift
      HIGH: Track init, equality, Codable roundtrip.
      Source: mixbridge/Models/Track.swift

- [ ] mixbridgeTests/Models/PlaylistTests.swift
      HIGH: Playlist operations, track ordering.
      Source: mixbridge/Models/Playlist.swift

- [ ] mixbridgeTests/Models/PlaybackQueueTests.swift
      HIGH: Queue operations, shuffle, repeat.
      Source: mixbridge/Models/PlaybackQueue.swift

- [ ] mixbridgeTests/Models/PlayerStateTests.swift
      MEDIUM: State transitions, persistence.
      Source: mixbridge/Models/PlayerState.swift

- [ ] mixbridgeTests/Models/MixSettingsTests.swift
      LOW: Settings validation, defaults.
      Source: mixbridge/Models/MixSettings.swift

- [ ] mixbridgeTests/Models/SoundCloudModelsTests.swift
      LOW: API response parsing.
      Source: mixbridge/Models/SoundCloudModels.swift

- [ ] mixbridgeTests/Models/ConvexDataModelsTests.swift
      LOW: Backend model mapping.
      Source: mixbridge/Models/ConvexDataModels.swift

## Completion Criteria
All 7 test files with Codable, Equatable, and edge case tests.
EOF
      ;;

    utils)
      cat > "$prd_file" << 'EOF'
# Utilities Tests PRD

## Tasks

- [ ] mixbridgeTests/Utilities/ImageCacheManagerTests.swift
      Cache operations, memory limits, cleanup.
      Source: mixbridge/Utilities/ImageCacheManager.swift

- [ ] mixbridgeTests/Utilities/LogManagerTests.swift
      Log levels, filtering.
      Source: mixbridge/Utilities/LogManager.swift

- [ ] mixbridgeTests/Utilities/KeychainManagerTests.swift
      Secure storage CRUD.
      Source: mixbridge/Auth/KeychainManager.swift

- [ ] mixbridgeTests/Utilities/HapticManagerTests.swift
      Haptic generation (mock UIKit).
      Source: mixbridge/Utilities/HapticManager.swift

- [ ] mixbridgeTests/Utilities/BackgroundExecutorTests.swift
      Background task execution.
      Source: mixbridge/Utilities/BackgroundExecutor.swift

## Completion Criteria
All 5 test files created.
EOF
      ;;

    auth)
      cat > "$prd_file" << 'EOF'
# Auth Tests PRD

## Tasks (Priority Order)

- [ ] mixbridgeTests/Auth/AuthManagerTests.swift
      CRITICAL: Auth state machine, token management, logout.
      Source: mixbridge/Auth/AuthManager.swift

- [ ] mixbridgeTests/Auth/SessionTokenDecoderTests.swift
      HIGH: JWT decoding, expiration checking.
      Source: mixbridge/Auth/SessionTokenDecoder.swift

- [ ] mixbridgeTests/Auth/SpotifyAuthManagerTests.swift
      MEDIUM: Spotify OAuth flow (mock network).
      Source: mixbridge/Auth/SpotifyAuthManager.swift

## Completion Criteria
All 3 test files with state transition and error handling tests.
EOF
      ;;

    sync)
      cat > "$prd_file" << 'EOF'
# Sync Tests PRD

## Tasks (Priority Order)

- [ ] mixbridgeTests/Sync/PlaylistSyncTests.swift
      HIGH: Sync logic, conflict resolution.
      Source: mixbridge/Sync/PlaylistSync.swift

- [ ] mixbridgeTests/Sync/QueueSyncTests.swift
      HIGH: Queue state sync.
      Source: mixbridge/Sync/QueueSync.swift

- [ ] mixbridgeTests/Sync/OperationQueueTests.swift
      MEDIUM: Background operation scheduling, retry.
      Source: mixbridge/Sync/OperationQueue.swift

- [ ] mixbridgeTests/Sync/LikedSyncTests.swift
      LOW: Liked tracks sync.
      Source: mixbridge/Sync/LikedSync.swift

- [ ] mixbridgeTests/Sync/HistorySyncTests.swift
      LOW: Play history sync.
      Source: mixbridge/Sync/HistorySync.swift

## Completion Criteria
All 5 test files with sync state machine tests.
EOF
      ;;

    db)
      cat > "$prd_file" << 'EOF'
# Database Tests PRD

## Tasks (Priority Order)

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/PersistedTrackTests.swift
      HIGH: Track CRUD, queries.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/PersistedPlaylistTests.swift
      HIGH: Playlist CRUD, relationships.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/PersistedQueueTests.swift
      MEDIUM: Queue persistence.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/LikedTrackTests.swift
      MEDIUM: Liked tracks CRUD.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/PlayHistoryTests.swift
      LOW: History CRUD.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/DownloadedTrackTests.swift
      LOW: Download tracking.

- [ ] Packages/MixBridgeDB/Tests/MixBridgeDBTests/MigrationTests.swift
      LOW: Schema migration tests.

## Completion Criteria
All 7 test files with GRDB integration tests.
EOF
      ;;
  esac

  echo "$prd_file"
}

# Execute based on module
case $MODULE in
  setup|services|viewmodels|models|utils|auth|sync|db)
    prd=$(create_prd "$MODULE")
    echo "=== Running Ralph for $MODULE ==="
    echo "=== PRD: $prd ==="
    echo "=== Progress: $PROGRESS_FILE ==="
    run_ralph "$prd" "$ITERATIONS" "$MODULE"
    ;;
  all)
    echo "=== Running Ralph for ALL modules ==="
    echo ""

    # Module:iterations pairs (bash 3.x compatible)
    for entry in "setup:5" "services:6" "models:7" "auth:3" "viewmodels:6" "utils:5" "sync:5" "db:7"; do
      mod="${entry%%:*}"
      count="${entry##*:}"
      echo ""
      echo "########################################"
      echo "### MODULE: $mod ($count iterations max)"
      echo "########################################"
      prd=$(create_prd "$mod")
      run_ralph "$prd" "$count" "$mod"
    done

    echo ""
    echo "=== All modules complete ==="
    ;;
  *)
    echo "Unknown module: $MODULE"
    echo "Available: setup, services, viewmodels, models, utils, auth, sync, db, all"
    exit 1
    ;;
esac
