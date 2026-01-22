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

    # Check if all work is done (alternate signal)
    if grep -q "<promise>ALL_DONE</promise>" "$output_file"; then
      echo ""
      echo "=============================================="
      echo "ALL WORK COMPLETE after $i iteration(s)"
      echo "=============================================="
      rm -f "$output_file"
      return 0
    fi

    rm -f "$output_file"

    if [ $i -lt $max_iterations ]; then
      echo ""
      echo "--- Iteration $i done, continuing to next ---"
      sleep 2
    fi
  done

  echo ""
  echo "=============================================="
  echo "Reached max iterations ($max_iterations)"
  echo "=============================================="
}

# ============================================
# MODULE PROMPTS - Incremental approach
# Each iteration handles ONE file/component
# ============================================

SETUP_PROMPT="You are setting up test infrastructure for mixbridge-ios.

TASK: Create test infrastructure incrementally.

1. First, check what already exists in mixbridgeTests/
2. Create the NEXT missing item from this list:
   - mixbridgeTests/TestHelpers/MockConvexService.swift
   - mixbridgeTests/TestHelpers/MockAuthManager.swift
   - mixbridgeTests/TestHelpers/TestFixtures.swift
   - mixbridgeTests/TestHelpers/XCTestCase+Async.swift
   - mixbridgeTests/SampleTests.swift

3. Read the relevant source files to understand what to mock
4. Create ONE file with complete, working code

OUTPUT RULES:
- If you created a file, end with: <promise>COMPLETE</promise>
- If ALL files already exist, end with: <promise>ALL_DONE</promise>"

SERVICES_PROMPT="You are writing unit tests for Services in mixbridge-ios.

TASK: Write tests for ONE service per session.

Services to test (in order):
1. mixbridge/Services/QueueManager.swift
2. mixbridge/Services/StreamURLCache.swift
3. mixbridge/Services/DownloadManager.swift
4. mixbridge/Services/PlaybackPositionTracker.swift
5. mixbridge/Services/TrackPrefetcher.swift
6. mixbridge/Models/RecentSearchManager.swift

PROCESS:
1. Check mixbridgeTests/Services/ for existing test files
2. Find the FIRST service that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/Services/{ServiceName}Tests.swift
5. Write comprehensive tests: happy path, errors, edge cases

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL services have tests, end with: <promise>ALL_DONE</promise>"

VIEWMODELS_PROMPT="You are writing unit tests for ViewModels in mixbridge-ios.

TASK: Write tests for ONE ViewModel per session.

ViewModels to test (in order):
1. mixbridge/ViewModels/HomeViewModel.swift
2. mixbridge/ViewModels/LibraryViewModel.swift
3. mixbridge/ViewModels/PlaylistDetailViewModel.swift
4. mixbridge/ViewModels/CreatePlaylistViewModel.swift
5. mixbridge/ViewModels/EditPlaylistViewModel.swift
6. mixbridge/ViewModels/LikedViewModel.swift

PROCESS:
1. Check mixbridgeTests/ViewModels/ for existing test files
2. Find the FIRST ViewModel that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/ViewModels/{Name}Tests.swift
5. Test @Published properties, async loading, user actions

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL ViewModels have tests, end with: <promise>ALL_DONE</promise>"

MODELS_PROMPT="You are writing unit tests for Models in mixbridge-ios.

TASK: Write tests for ONE model per session.

Models to test (in order):
1. mixbridge/Models/Track.swift
2. mixbridge/Models/Playlist.swift
3. mixbridge/Models/PlayerState.swift
4. mixbridge/Models/PlaybackQueue.swift
5. mixbridge/Models/MixSettings.swift
6. mixbridge/Models/SoundCloudModels.swift
7. mixbridge/Models/ConvexDataModels.swift

PROCESS:
1. Check mixbridgeTests/Models/ for existing test files
2. Find the FIRST model that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/Models/{Name}Tests.swift
5. Test Codable roundtrips, Equatable, edge cases

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL models have tests, end with: <promise>ALL_DONE</promise>"

UTILS_PROMPT="You are writing unit tests for Utilities in mixbridge-ios.

TASK: Write tests for ONE utility per session.

Utilities to test (in order):
1. mixbridge/Utilities/ImageCacheManager.swift
2. mixbridge/Utilities/HapticManager.swift
3. mixbridge/Utilities/LogManager.swift
4. mixbridge/Utilities/BackgroundExecutor.swift
5. mixbridge/Auth/KeychainManager.swift

PROCESS:
1. Check mixbridgeTests/Utilities/ for existing test files
2. Find the FIRST utility that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/Utilities/{Name}Tests.swift

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL utilities have tests, end with: <promise>ALL_DONE</promise>"

AUTH_PROMPT="You are writing unit tests for Auth in mixbridge-ios.

TASK: Write tests for ONE auth class per session.

Auth classes to test (in order):
1. mixbridge/Auth/AuthManager.swift
2. mixbridge/Auth/SpotifyAuthManager.swift
3. mixbridge/Auth/SessionTokenDecoder.swift

PROCESS:
1. Check mixbridgeTests/Auth/ for existing test files
2. Find the FIRST auth class that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/Auth/{Name}Tests.swift
5. Test state transitions, token handling, errors

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL auth classes have tests, end with: <promise>ALL_DONE</promise>"

SYNC_PROMPT="You are writing unit tests for Sync modules in mixbridge-ios.

TASK: Write tests for ONE sync class per session.

Sync classes to test (in order):
1. mixbridge/Sync/PlaylistSync.swift
2. mixbridge/Sync/LikedSync.swift
3. mixbridge/Sync/QueueSync.swift
4. mixbridge/Sync/HistorySync.swift
5. mixbridge/Sync/OperationQueue.swift

PROCESS:
1. Check mixbridgeTests/Sync/ for existing test files
2. Find the FIRST sync class that doesn't have tests yet
3. READ the source file thoroughly
4. Create mixbridgeTests/Sync/{Name}Tests.swift
5. Test sync states, conflict resolution, retries

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL sync classes have tests, end with: <promise>ALL_DONE</promise>"

DB_PROMPT="You are writing unit tests for MixBridgeDB package.

TASK: Write tests for ONE database model per session.

Models to test (in order):
1. PersistedTrack
2. PersistedPlaylist
3. PersistedQueue + PersistedQueueTrack
4. PlaylistTrack
5. LikedTrack + LikedPlaylist
6. DownloadedTrack
7. PlayHistory
8. PersistedUserProfile

PROCESS:
1. Check Packages/MixBridgeDB/Tests/ for existing test files
2. Find the FIRST model that doesn't have tests yet
3. READ the GRDB model file thoroughly
4. Create test file in Packages/MixBridgeDB/Tests/MixBridgeDBTests/
5. Test CRUD operations, queries, relationships

OUTPUT RULES:
- After creating ONE test file, end with: <promise>COMPLETE</promise>
- If ALL models have tests, end with: <promise>ALL_DONE</promise>"

# Execute based on module
case $MODULE in
  setup)
    echo "=== Setting up test infrastructure ==="
    echo "=== (up to 5 files, 1 per iteration) ==="
    run_ralph "$SETUP_PROMPT" "$ITERATIONS"
    ;;
  services)
    echo "=== Writing service tests ==="
    echo "=== (6 services, 1 per iteration) ==="
    run_ralph "$SERVICES_PROMPT" "$ITERATIONS"
    ;;
  viewmodels)
    echo "=== Writing ViewModel tests ==="
    echo "=== (6 ViewModels, 1 per iteration) ==="
    run_ralph "$VIEWMODELS_PROMPT" "$ITERATIONS"
    ;;
  models)
    echo "=== Writing model tests ==="
    echo "=== (7 models, 1 per iteration) ==="
    run_ralph "$MODELS_PROMPT" "$ITERATIONS"
    ;;
  utils)
    echo "=== Writing utility tests ==="
    echo "=== (5 utilities, 1 per iteration) ==="
    run_ralph "$UTILS_PROMPT" "$ITERATIONS"
    ;;
  auth)
    echo "=== Writing auth tests ==="
    echo "=== (3 auth classes, 1 per iteration) ==="
    run_ralph "$AUTH_PROMPT" "$ITERATIONS"
    ;;
  sync)
    echo "=== Writing sync tests ==="
    echo "=== (5 sync classes, 1 per iteration) ==="
    run_ralph "$SYNC_PROMPT" "$ITERATIONS"
    ;;
  db)
    echo "=== Writing database tests ==="
    echo "=== (8 models, 1 per iteration) ==="
    run_ralph "$DB_PROMPT" "$ITERATIONS"
    ;;
  all)
    echo "=== Running all test generation modules ==="
    echo ""
    # Run each module with appropriate iteration counts
    MODULES=("setup:5" "services:6" "viewmodels:6" "models:7" "utils:5" "auth:3" "sync:5" "db:8")
    for entry in "${MODULES[@]}"; do
      mod="${entry%%:*}"
      count="${entry##*:}"
      echo ""
      echo "########################################"
      echo "### MODULE: $mod ($count iterations)"
      echo "########################################"
      $0 "$count" "$mod"
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
