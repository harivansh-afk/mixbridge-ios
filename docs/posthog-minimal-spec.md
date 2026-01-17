# Mixbridge iOS PostHog Minimal Analytics Spec

## Goals (minimal, <15 events)
- Verify onboarding conversion (SoundCloud login success rate).
- Confirm activation (first track played).
- Measure retention (returning users).
- Understand content preferences (tracks, playlists, search, sharing).

## Key user flows (from codebase)
- Onboarding/auth: `mixbridge/Onboarding/ConnectSoundCloudScreen.swift`, `mixbridge/Auth/AuthManager.swift`
- Main navigation: `mixbridge/ContentView.swift` (Home/Library/Search tabs + player)
- Player: `mixbridge/Models/PlayerState.swift`, `mixbridge/Services/PlaybackCoordinator.swift`
- Playlists: `mixbridge/Views/Playlist/PlaylistDetailView.swift`
- Search: `mixbridge/Views/Search/SearchView.swift`
- Sharing/deep links: `mixbridge/Components/TrackRow.swift`, `mixbridge/Views/Sharing/SharedTrackView.swift`, `mixbridge/Views/Sharing/SharedPlaylistView.swift`, `mixbridge/Navigation/DeepLinkRouter.swift`

## Event list (12 total)
Use `captureApplicationLifecycleEvents = true` so PostHog auto-captures `$app_opened`.

### 1) `$app_opened` (auto)
- When: App enters foreground (PostHog auto event).
- Properties: standard PostHog device/session properties.

### 2) `onboarding_viewed`
- When: `ConnectSoundCloudScreen` appears.
- Properties: `entry_point` (`splash_complete`, `logout`), `is_authenticated` (bool).

### 3) `soundcloud_login_tapped`
- When: user taps "Login with SoundCloud".
- Properties: `entry_point` (same as above).

### 4) `soundcloud_login_result`
- When: OAuth finishes (success/failure/cancel).
- Properties:
  - `result` (`success`, `failed`, `cancelled`)
  - `error_message` (only when failed)
  - `latency_ms` (time from tap to result)

### 5) `track_played`
- When: playback actually starts (not just a tap).
- Properties:
  - `track_id`, `track_title`, `artist_name`
  - `source` (`home`, `library`, `search`, `playlist`, `liked`, `queue`, `shared`, `deep_link`)
  - `queue_index` (nullable)
  - `is_first_play` (true for the user’s first-ever track play)
  - `genre` (if available from `SoundCloudTrack`)

### 6) `track_completed`
- When: track finishes (`AVPlayerItemDidPlayToEndTime`) or >=80% listened.
- Properties:
  - `track_id`
  - `completion_percent`
  - `duration_seconds`
  - `source`

### 7) `search_performed`
- When: a search request is sent (`performSearch`).
- Properties:
  - `query` (optional; consider hashing if needed)
  - `query_length`
  - `source` (`soundcloud`, `library`)
  - `tab` (`tracks`, `playlists`, `artists`)
  - `result_count`

### 8) `playlist_opened`
- When: `PlaylistDetailView` is presented.
- Properties:
  - `playlist_id`, `playlist_name`
  - `source` (`home`, `library`, `search`, `shared`)
  - `is_user_created` (bool)

### 9) `playlist_played`
- When: user taps Play/Shuffle in playlist detail.
- Properties:
  - `playlist_id`
  - `track_count`
  - `play_mode` (`play`, `shuffle`)
  - `source`

### 10) `playlist_created`
- When: User creates a new playlist.
- Properties:
  - `playlist_id`
  - `initial_track_count`
  - `source` (`library`, `track_row`, `add_to_playlist_sheet`)

### 11) `content_shared`
- When: share link is generated (track or playlist).
- Properties:
  - `content_type` (`track`, `playlist`)
  - `content_id`
  - `share_surface` (`context_menu`, `playlist_menu`)

### 12) `shared_content_viewed`
- When: shared content screen is shown from a deep link.
- Properties:
  - `content_type` (`track`, `playlist`)
  - `share_id`
  - `is_authenticated` (bool)

## Funnels to build in PostHog

### Onboarding funnel (critical)
1. `$app_opened` (first time)
2. `onboarding_viewed`
3. `soundcloud_login_tapped`
4. `soundcloud_login_result` (result = `success`)
5. `track_played` (is_first_play = true)

### Activation funnel
1. `soundcloud_login_result` (result = `success`)
2. `track_played` (is_first_play = true)
3. `track_completed` (completion_percent >= 80)

### Retention loop
1. `$app_opened`
2. `track_played`

### Engagement preferences
1. `search_performed`
2. `track_played` (by `genre`, `source`)
3. `playlist_played` (by `source`)

## Implementation plan (files to change)

### 1) Create a tiny analytics wrapper (optional but recommended)
- Add `mixbridge/Services/Analytics.swift` to centralize `PostHogSDK.shared.capture(...)`.
- Include helpers for `track_played`, `track_completed`, `content_shared`.

### 2) Onboarding/auth
- `mixbridge/Onboarding/ConnectSoundCloudScreen.swift`
  - Fire `onboarding_viewed` in `.onAppear`.
  - Fire `soundcloud_login_tapped` in the login button tap.
  - Measure latency and emit `soundcloud_login_result` on callback (success/fail/cancel).
- `mixbridge/Auth/AuthManager.swift`
  - On success inside `handleCallback`, call `identify` with `currentUserId`.

### 3) Player (activation + retention)
- `mixbridge/Services/PlaybackCoordinator.swift`
  - Emit `track_played` when playback actually starts (after `player.play()` or mix engine start).
  - Emit `track_completed` in `handleItemDidFinish`.
- `mixbridge/Models/PlayerState.swift`
  - Provide playback source (e.g., set a `playbackSource` before calling `playFromList`).

### 4) Search
- `mixbridge/Views/Search/SearchView.swift`
  - Emit `search_performed` at the end of `performSearch(...)` (include result_count + tab/source).

### 5) Playlists
- `mixbridge/Views/Playlist/PlaylistDetailView.swift`
  - Emit `playlist_opened` in `.task` or `.onAppear`.
  - Emit `playlist_played` in `PlaylistActionButtons` callbacks.
- `mixbridge/Views/Playlist/CreatePlaylistSheet.swift`
  - Emit `playlist_created` when playlist is successfully created.

### 6) Sharing / deep links
- `mixbridge/Components/TrackRow.swift`
  - Emit `content_shared` when share link is successfully generated.
- `mixbridge/Views/Playlist/PlaylistDetailView.swift`
  - Emit `content_shared` when share link is generated.
- `mixbridge/Views/Sharing/SharedTrackView.swift` and `mixbridge/Views/Sharing/SharedPlaylistView.swift`
  - Emit `shared_content_viewed` on appear.

