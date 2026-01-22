#!/bin/bash
set -e

# Ralph Test Generator for mixbridge-ios
# Usage: ./ralph-tests.sh <iterations> [module]
# Modules: setup, services, viewmodels, models, utils, auth, sync, db, all

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [module]"
  echo "Modules: setup, services, viewmodels, models, utils, auth, sync, db, all"
  exit 1
fi

ITERATIONS=$1
MODULE=${2:-all}
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

run_ralph() {
  local prompt="$1"
  local max_iterations="$2"

  for ((i=1; i<=$max_iterations; i++)); do
    echo ""
    echo "=============================================="
    echo "=== RALPH ITERATION $i of $max_iterations ==="
    echo "=============================================="
    echo ""

    # Run Claude in full agentic mode
    # --dangerously-skip-permissions bypasses all permission prompts
    # --verbose shows tool calls as they happen
    output_file=$(mktemp)

    claude --dangerously-skip-permissions --verbose "$prompt" 2>&1 | tee "$output_file"

    # Check if Claude signaled completion
    if grep -q "<promise>COMPLETE</promise>" "$output_file"; then
      echo ""
      echo "=============================================="
      echo "Ralph COMPLETE after $i iteration(s)"
      echo "=============================================="
      rm -f "$output_file"
      return 0
    fi

    rm -f "$output_file"

    if [ $i -lt $max_iterations ]; then
      echo ""
      echo "--- Iteration $i done, continuing to next iteration ---"
      sleep 2
    fi
  done

  echo ""
  echo "=============================================="
  echo "Completed $max_iterations iterations (no early exit signal)"
  echo "=============================================="
}

# Module-specific prompts
SETUP_PROMPT="You are setting up the test infrastructure for the mixbridge-ios project.

TASK: Create the XCTest target and test infrastructure.

1. First, check if a test target/directory exists
2. Create the directory structure: mixbridgeTests/
3. Create test utilities and mocks:
   - mixbridgeTests/TestHelpers/MockConvexService.swift
   - mixbridgeTests/TestHelpers/MockAuthManager.swift
   - mixbridgeTests/TestHelpers/TestFixtures.swift
   - mixbridgeTests/TestHelpers/XCTestCase+Async.swift
4. Create a sample test file to verify structure works

IMPORTANT: Actually create the files using your tools. Read existing code first to understand what needs to be mocked.

When ALL test infrastructure files are created, end your response with exactly: <promise>COMPLETE</promise>"

SERVICES_PROMPT="You are writing unit tests for the Services layer of mixbridge-ios.

TASK: Write comprehensive unit tests for core services.

Target services (do these in order):
1. QueueManager.swift - Queue state management
2. StreamURLCache.swift - URL caching logic
3. DownloadManager.swift - Download state machine
4. PlaybackPositionTracker.swift - Position tracking
5. TrackPrefetcher.swift - Prefetch logic
6. RecentSearchManager.swift - Search history

For each service:
- READ the source file first to understand the API
- Test happy path, errors, and edge cases
- Use dependency injection with mocks
- Naming: test_methodName_condition_expectedResult

Create files in: mixbridgeTests/Services/

IMPORTANT: Actually create the test files. Read the source code first.

When ALL service tests are created, end with: <promise>COMPLETE</promise>"

VIEWMODELS_PROMPT="You are writing unit tests for ViewModels in mixbridge-ios.

TASK: Write unit tests for all ViewModels.

Target ViewModels:
1. HomeViewModel.swift
2. LibraryViewModel.swift
3. PlaylistDetailViewModel.swift
4. CreatePlaylistViewModel.swift
5. EditPlaylistViewModel.swift
6. LikedViewModel.swift

For each:
- READ the source first
- Test @Published property updates
- Test async loading states
- Mock all dependencies

Create files in: mixbridgeTests/ViewModels/

When ALL ViewModel tests are created, end with: <promise>COMPLETE</promise>"

MODELS_PROMPT="You are writing unit tests for Models in mixbridge-ios.

TASK: Write unit tests for data models.

Target Models:
1. Track.swift
2. Playlist.swift
3. PlayerState.swift
4. PlaybackQueue.swift
5. MixSettings.swift
6. SoundCloudModels.swift
7. ConvexDataModels.swift

Test:
- Codable encoding/decoding roundtrips
- Equatable/Hashable correctness
- Edge cases (nil values, empty arrays)

Create files in: mixbridgeTests/Models/

When ALL model tests are created, end with: <promise>COMPLETE</promise>"

UTILS_PROMPT="You are writing unit tests for Utilities in mixbridge-ios.

TASK: Write unit tests for utility classes.

Target:
1. ImageCacheManager.swift
2. HapticManager.swift
3. LogManager.swift
4. BackgroundExecutor.swift
5. KeychainManager.swift

Create files in: mixbridgeTests/Utilities/

When ALL utility tests are created, end with: <promise>COMPLETE</promise>"

AUTH_PROMPT="You are writing unit tests for Authentication in mixbridge-ios.

TASK: Write unit tests for auth classes.

Target:
1. AuthManager.swift
2. SpotifyAuthManager.swift
3. SessionTokenDecoder.swift

Test auth state transitions, token handling, errors.

Create files in: mixbridgeTests/Auth/

When ALL auth tests are created, end with: <promise>COMPLETE</promise>"

SYNC_PROMPT="You are writing unit tests for Sync modules in mixbridge-ios.

TASK: Write unit tests for sync classes.

Target:
1. PlaylistSync.swift
2. LikedSync.swift
3. QueueSync.swift
4. HistorySync.swift
5. OperationQueue.swift

Test sync state machines, conflict resolution, retry logic.

Create files in: mixbridgeTests/Sync/

When ALL sync tests are created, end with: <promise>COMPLETE</promise>"

DB_PROMPT="You are writing unit tests for the MixBridgeDB package.

TASK: Write unit tests for database operations.

Target: Packages/MixBridgeDB/

Test CRUD operations, migrations, transactions for all models.

Create tests in: Packages/MixBridgeDB/Tests/MixBridgeDBTests/

When ALL database tests are created, end with: <promise>COMPLETE</promise>"

# Execute based on module
case $MODULE in
  setup)
    echo "=== Setting up test infrastructure ==="
    run_ralph "$SETUP_PROMPT" "$ITERATIONS"
    ;;
  services)
    echo "=== Writing service tests ==="
    run_ralph "$SERVICES_PROMPT" "$ITERATIONS"
    ;;
  viewmodels)
    echo "=== Writing ViewModel tests ==="
    run_ralph "$VIEWMODELS_PROMPT" "$ITERATIONS"
    ;;
  models)
    echo "=== Writing model tests ==="
    run_ralph "$MODELS_PROMPT" "$ITERATIONS"
    ;;
  utils)
    echo "=== Writing utility tests ==="
    run_ralph "$UTILS_PROMPT" "$ITERATIONS"
    ;;
  auth)
    echo "=== Writing auth tests ==="
    run_ralph "$AUTH_PROMPT" "$ITERATIONS"
    ;;
  sync)
    echo "=== Writing sync tests ==="
    run_ralph "$SYNC_PROMPT" "$ITERATIONS"
    ;;
  db)
    echo "=== Writing database tests ==="
    run_ralph "$DB_PROMPT" "$ITERATIONS"
    ;;
  all)
    echo "=== Running all test generation modules ==="
    for mod in setup services viewmodels models utils auth sync db; do
      echo ""
      echo "########################################"
      echo "### MODULE: $mod"
      echo "########################################"
      run_ralph "$(eval echo \$${mod^^}_PROMPT)" "$ITERATIONS"
    done
    echo ""
    echo "=== All test modules complete ==="
    ;;
  *)
    echo "Unknown module: $MODULE"
    echo "Available: setup, services, viewmodels, models, utils, auth, sync, db, all"
    exit 1
    ;;
esac
