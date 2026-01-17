# Mixbridge PostHog Events Schema

## Setup Nuances (iOS-specific)

### 1. SwiftUI Gotchas
- **Screen tracking doesn't auto-work in SwiftUI** — PostHog uses UIViewController swizzling, but SwiftUI views aren't UIViewControllers
- **Solution**: Use `.onAppear` with manual `PostHogSDK.shared.screen()` calls OR use the `postHogScreenView()` modifier

### 2. Configuration Recommendations
```swift
let config = PostHogConfig(apiKey: "phc_xxx")

// Core
config.host = "https://us.i.posthog.com"  // or eu.i.posthog.com
config.captureApplicationLifecycleEvents = true
config.captureScreenViews = false  // We'll do manual screen tracking for SwiftUI
config.captureElementInteractions = false  // SwiftUI doesn't use UIKit interactions

// Session Replay
config.sessionReplay = true
config.sessionReplayConfig.maskAllTextInputs = true  // Privacy: mask text
config.sessionReplayConfig.maskAllImages = false     // Show album art
config.sessionReplayConfig.screenshotMode = true     // Better for SwiftUI

// Performance
config.flushAt = 10  // Batch 10 events before sending (default 20)
config.flushIntervalSeconds = 30
config.maxQueueSize = 1000

// Privacy
config.personProfiles = .identifiedOnly  // Only create profiles for identified users

PostHogSDK.shared.setup(config)
```

### 3. Privacy Considerations
- **Mask sensitive data** in beforeSend:
```swift
config.setBeforeSend { event in
    // Redact any accidental PII
    if var props = event.properties {
        props.removeValue(forKey: "email")
        props.removeValue(forKey: "password")
        event.properties = props
    }
    return event
}
```

### 4. Offline Support
- PostHog iOS SDK queues events when offline
- Events flush when back online
- Set `maxQueueSize` to control memory usage

---

## Events Schema

### Authentication & Onboarding

| Event | Properties | When |
|-------|------------|------|
| `app_opened` | `is_first_open`, `version`, `build` | App launched (auto-captured) |
| `onboarding_started` | — | User sees ConnectSoundCloudScreen |
| `soundcloud_login_tapped` | — | User taps "Login with SoundCloud" |
| `soundcloud_login_success` | `user_id`, `username` | OAuth callback success |
| `soundcloud_login_failed` | `error` | OAuth callback error |
| `soundcloud_login_cancelled` | — | User dismissed OAuth sheet |

### Screen Views (manual for SwiftUI)

| Event | Properties |
|-------|------------|
| `screen_viewed` | `screen_name`: `home`, `search`, `library`, `liked`, `profile`, `settings`, `playlist_detail`, `artist_detail` |

### Core Actions — Tracks

| Event | Properties | When |
|-------|------------|------|
| `track_played` | `track_id`, `track_title`, `artist_id`, `artist_name`, `source`, `position_in_queue` | Play button tapped |
| `track_paused` | `track_id`, `playback_position_seconds`, `duration_seconds` | Pause tapped |
| `track_completed` | `track_id`, `duration_seconds`, `completion_percent` | Track finished naturally |
| `track_skipped` | `track_id`, `playback_position_seconds`, `skip_direction` (`next`/`prev`) | Skip tapped |
| `track_seeked` | `track_id`, `from_seconds`, `to_seconds` | Scrubber used |
| `track_liked` | `track_id`, `source` | Heart tapped |
| `track_unliked` | `track_id` | Heart untapped |
| `track_shared` | `track_id`, `share_method` (`copy_link`, `share_sheet`, `messages`, etc.) | Share action |
| `track_downloaded` | `track_id`, `file_size_mb` | Download completed |

**Source values**: `home`, `search`, `playlist`, `liked`, `library`, `queue`, `deep_link`, `shared_link`

### Core Actions — Playlists

| Event | Properties | When |
|-------|------------|------|
| `playlist_created` | `playlist_id`, `track_count` | New playlist created |
| `playlist_edited` | `playlist_id`, `changes` (`title`, `description`, `cover`) | Playlist updated |
| `playlist_deleted` | `playlist_id`, `track_count` | Playlist deleted |
| `playlist_track_added` | `playlist_id`, `track_id`, `position` | Track added to playlist |
| `playlist_track_removed` | `playlist_id`, `track_id` | Track removed |
| `playlist_played` | `playlist_id`, `track_count`, `source` | Playlist play tapped |
| `playlist_shuffled` | `playlist_id`, `track_count` | Shuffle enabled |
| `playlist_shared` | `playlist_id`, `share_method` | Playlist shared |
| `playlist_liked` | `playlist_id` | External playlist liked |

### Search

| Event | Properties | When |
|-------|------------|------|
| `search_started` | — | Search field focused |
| `search_performed` | `query`, `query_length`, `result_count` | Search submitted |
| `search_result_tapped` | `query`, `result_type` (`track`, `playlist`, `artist`), `result_position` | Result selected |
| `search_cleared` | — | Search cleared |

### Queue

| Event | Properties | When |
|-------|------------|------|
| `queue_opened` | `queue_length` | Queue sheet opened |
| `queue_track_added` | `track_id`, `add_method` (`play_next`, `add_to_queue`) | Track added to queue |
| `queue_track_removed` | `track_id` | Track removed from queue |
| `queue_reordered` | `from_position`, `to_position` | Track dragged in queue |
| `queue_cleared` | `track_count` | Queue cleared |

### Library

| Event | Properties | When |
|-------|------------|------|
| `library_tab_viewed` | `tab` (`songs`, `playlists`, `artists`, `downloads`) | Tab switched |
| `artist_viewed` | `artist_id`, `artist_name`, `source` | Artist detail opened |

### Player UI

| Event | Properties | When |
|-------|------------|------|
| `player_expanded` | `track_id` | Mini player tapped, expanded |
| `player_collapsed` | `track_id` | Expanded player dismissed |
| `repeat_mode_changed` | `mode` (`off`, `all`, `one`) | Repeat tapped |
| `shuffle_toggled` | `enabled` | Shuffle tapped |

### Deep Links / Sharing

| Event | Properties | When |
|-------|------------|------|
| `deep_link_opened` | `link_type` (`track`, `playlist`), `content_id` | App opened via deep link |
| `shared_content_viewed` | `content_type`, `content_id`, `referrer` | Shared content sheet shown |
| `shared_content_played` | `content_type`, `content_id` | Play from shared content |

### Errors

| Event | Properties | When |
|-------|------------|------|
| `playback_error` | `track_id`, `error_code`, `error_message` | Playback failed |
| `api_error` | `endpoint`, `status_code`, `error_message` | API call failed |
| `download_error` | `track_id`, `error_message` | Download failed |

---

## User Properties (set on identify)

```swift
PostHogSDK.shared.identify("soundcloud_user_id", userProperties: [
    "username": "dj_hari",
    "soundcloud_id": "12345",
    "account_created_at": "2024-01-15",
    "followers_count": 150,
    "tracks_count": 45,
    "app_version": "1.2.0",
    "ios_version": "18.2",
    "device_model": "iPhone 15 Pro"
])
```

---

## Key Funnels to Build

### 1. Onboarding Funnel
```
app_opened (first_open=true)
  → onboarding_started
  → soundcloud_login_tapped
  → soundcloud_login_success
  → screen_viewed (home)
  → track_played (first)
```

### 2. Activation Funnel
```
soundcloud_login_success
  → track_played
  → track_liked OR playlist_created
  → track_shared OR playlist_shared
```

### 3. Core Loop Funnel
```
app_opened
  → track_played
  → track_completed (completion_percent > 80%)
  → second track_played (same session)
```

---

## Key Retention Metrics

| Metric | Definition |
|--------|------------|
| **D1 Retention** | Users who return day after first use |
| **D7 Retention** | Users who return within 7 days |
| **Weekly Active Listeners** | Users who played 1+ track in past 7 days |
| **Power Users** | Users who played 20+ tracks in past 7 days |

---

## Cohorts to Create

| Cohort | Definition |
|--------|------------|
| `new_users` | First seen in last 7 days |
| `activated_users` | Played 5+ tracks AND (liked 1 track OR created 1 playlist) |
| `power_listeners` | 50+ track_played events in last 30 days |
| `playlist_creators` | Created 3+ playlists |
| `sharers` | 5+ share events in last 30 days |
| `churned` | No track_played in last 14 days, was active before |

---

## Implementation Checklist

- [ ] Add PostHog SDK via SPM
- [ ] Configure in `mixbridgeApp.swift` (before any views)
- [ ] Add `identify()` call in `AuthManager` on login success
- [ ] Add `reset()` call on logout
- [ ] Add screen tracking `.onAppear` modifiers
- [ ] Instrument `PlayerState` for playback events
- [ ] Instrument `QueueManager` for queue events
- [ ] Instrument search in `SearchView`
- [ ] Instrument playlist actions
- [ ] Create funnels in PostHog dashboard
- [ ] Create retention insights
- [ ] Create cohorts
- [ ] Test with debug mode enabled

---

## Sample Implementation

### Analytics Manager
```swift
import PostHog

@Observable
final class Analytics {
    static let shared = Analytics()
    
    func configure() {
        let config = PostHogConfig(apiKey: "phc_xxx")
        config.host = "https://us.i.posthog.com"
        config.sessionReplay = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }
    
    func identify(userId: String, properties: [String: Any]) {
        PostHogSDK.shared.identify(userId, userProperties: properties)
    }
    
    func track(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
    
    func screen(_ name: String) {
        PostHogSDK.shared.screen(name)
    }
    
    func reset() {
        PostHogSDK.shared.reset()
    }
}
```

### Usage in PlayerState
```swift
func play(track: Track, source: String) {
    // ... existing play logic ...
    
    Analytics.shared.track("track_played", properties: [
        "track_id": track.id,
        "track_title": track.title,
        "artist_id": track.artistId,
        "artist_name": track.artistName,
        "source": source,
        "position_in_queue": currentIndex
    ])
}
```
