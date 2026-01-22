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
