# Mix Mode (Live Automatic Crossfade) — Implementation Spec (iOS)

This spec is designed to be **decision-free** for an implementation agent.

## Target Files / Integration Points

- Playback owner today: `mixbridge/Services/PlaybackCoordinator.swift`
- UI/State owner today: `mixbridge/Models/PlayerState.swift`
- Stream resolution: `mixbridge/Services/StreamURLCache.swift` + `ConvexService.getDirectStreamURL()`

## Feature Flags + Settings

Add to `PlayerState` (persist using `UserDefaults`):

- `mixEnabled: Bool` (default `false`)
- `crossfadeSeconds: Double` (default `6`, clamp `0...12`)
- `prewarmSeconds: Double` (default `15`, clamp `0...60`)

Keys:
- `mixbridge.mixEnabled`
- `mixbridge.crossfadeSeconds`
- `mixbridge.prewarmSeconds`

Mix Mode off must keep current behavior unchanged.

## Architecture Choice (required)

- Keep the current `AVQueuePlayer` pipeline for **non-mix** playback.
- Implement Mix Mode with a new engine that uses **two `AVPlayer`s** (current + next) because `AVQueuePlayer` cannot overlap items.

### New types

Create:

- `mixbridge/Services/MixCore.swift` (pure Swift: curve + scheduler + state machine)
- `mixbridge/Services/MixPlaybackEngine.swift` (AVFoundation wiring)

`PlaybackCoordinator` becomes a thin router:
- if `mixEnabled == false` → use existing code paths
- if `mixEnabled == true` → delegate to `MixPlaybackEngine`

## Pure Mix Core (Swift)

`MixCore` must be AVFoundation-free and unit-testable.

Implement:

- Equal-power gains:
  - `currentGain(p) = cos(p * .pi / 2)`
  - `nextGain(p) = sin(p * .pi / 2)`

- Schedule:
  - `effectiveCrossfade = min(max(crossfadeSeconds, 0), floor(duration/2))`
  - `fadeStart = max(0, duration - effectiveCrossfade)`
  - `prewarmStart = max(0, duration - max(prewarmSeconds, effectiveCrossfade))`

## Mix Playback Engine

### Players

Maintain:
- `currentPlayer: AVPlayer`
- `nextPlayer: AVPlayer?`

Never allow more than two players active.

### Prewarm

When `timeRemaining <= prewarmSeconds`:

1. Resolve/refresh stream for next track.
2. Create `AVPlayerItem` for next with headers:
   - `AVURLAssetHTTPHeaderFieldsKey: ["Authorization": "OAuth <token>"]`
3. Assign to `nextPlayer`, set volume to `0`.

### Just-in-time stream refresh

Because SoundCloud URLs expire, Mix Mode must ensure the next stream is fresh near transition:

- If next stream was cached and could expire before `now + crossfadeSeconds + 15s`, force refresh for next.

Implementation requirement:
- Add a helper on `StreamURLCache` that can answer "is cached stream expiring before X" for a given track id, without exposing tokens.

### Crossfade

When `timeRemaining <= effectiveCrossfade` and next is ready:

- Start `nextPlayer.play()` (if not already playing)
- Ramp volumes over `effectiveCrossfade` seconds using the equal-power curve.

On completion:
- Stop current player
- Promote next player to current
- Clear next state
- Immediately begin prewarm for the new next track (best-effort)

### Abort + fallback

If next cannot be prepared/kept up:
- Abort fade and continue with normal next-track start (no overlap).

## Observability

Emit compact logs/events:
- `mix_prewarm_start`
- `mix_prewarm_ready`
- `mix_fade_start`
- `mix_fade_complete`
- `mix_fade_abort(reason)`

Abort reasons:
- `no_next`
- `disabled`
- `zero_crossfade`
- `not_ready`
- `stream_refresh_failed`
- `queue_changed`
- `seek_cancelled`

## UI Hookup

Add a Mix toggle + crossfade seconds control to an existing player UI surface (where volume is controlled).

UI must only mutate `PlayerState` settings; all mix logic stays in coordinator/engine.

## Golden Trace

With `mixEnabled=true` and `crossfadeSeconds=6`:

- `mix_prewarm_start` once
- `mix_prewarm_ready` once
- `mix_fade_start` once
- `mix_fade_complete` once

If prewarm fails:
- `mix_fade_abort(stream_refresh_failed)` and playback continues via normal next.
