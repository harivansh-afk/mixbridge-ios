# Services Tests PRD

## Tasks (Priority Order)

- [x] mixbridgeTests/Services/QueueManagerTests.swift
      CRITICAL: Core queue logic. Test add/remove/reorder, shuffle, repeat modes.
      Source: mixbridge/Services/QueueManager.swift
      COMPLETED: 45 tests, tests REAL PlaybackQueue class

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
