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
