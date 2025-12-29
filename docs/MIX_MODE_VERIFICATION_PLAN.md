# Mix Mode (Live Automatic Crossfade) — Verification Plan (iOS)

This document is written for an automated coding agent (Claude/Codex) to implement **Mix Mode** on `mixbridge-ios` with a tight **build → verify → build** loop.

Verification is the bottleneck. This plan makes correctness checkable, even in a brownfield SwiftUI + AVFoundation codebase.

## Scope

- Repo: `mixbridge-ios`
- Target area: playback (`mixbridge/Services/PlaybackCoordinator.swift`, `mixbridge/Models/PlayerState.swift`)
- Goal: Automatic **live** crossfade between current track and the iteratively next track.
- Non-goals (MVP): exporting/storing a rendered mix, beatmatching, offline predownload.

## Constraints (important)

- `AVQueuePlayer` cannot truly crossfade (no overlap). Mix Mode requires **two concurrent players**.
- SoundCloud stream URLs expire quickly; for mixing you need **just-in-time** refresh for the next track near the fade window.

## Deliverables (MVP)

1. Settings:
   - `mixEnabled` (default: `false`)
   - `crossfadeSeconds` (default: `6`, range `0..12`)
   - `prewarmSeconds` (default: `15`, range `0..60`)
2. A small pure Swift “mix core” (no AVFoundation) that:
   - Implements curve math + scheduler + state machine
3. A Mix playback engine that:
   - Runs **two `AVPlayer`s** during crossfade (current + next)
   - Uses your existing stream resolution and headers (`AVURLAssetHTTPHeaderFieldsKey`)
   - Falls back to your current non-overlap transition if next cannot be prepared
4. Observability:
   - Compact log events for prewarm/fade/abort reasons

## Verifiable Behavior Spec

### A. Gain curve contract (equal-power)

Let `p ∈ [0, 1]` be crossfade progress.

- `currentGain(p) = cos(p * π/2)`
- `nextGain(p) = sin(p * π/2)`

**Invariants (unit-testable):**
- `currentGain(0) = 1`, `nextGain(0) = 0`
- `currentGain(1) = 0`, `nextGain(1) = 1`
- Equal-power: `abs(currentGain(p)^2 + nextGain(p)^2 - 1) <= 0.01`

### B. Scheduler contract

Given:
- `durationSeconds` (finite, > 0)
- `currentTimeSeconds` (>= 0)
- `crossfadeSeconds`
- `prewarmSeconds`

Define:
- `effectiveCrossfade = clamp(crossfadeSeconds, 0, floor(durationSeconds / 2))`
- `fadeStartTime = max(0, durationSeconds - effectiveCrossfade)`
- `prewarmStartTime = max(0, durationSeconds - max(prewarmSeconds, effectiveCrossfade))`

Rules:
- If no next track exists: never prewarm, never crossfade.
- If `effectiveCrossfade == 0`: do not overlap; use current advance behavior.

### C. State machine contract

States:
- `SinglePlaying`
- `PrewarmingNext`
- `Crossfading`

Transitions:
- `SinglePlaying → PrewarmingNext` when eligible and next exists.
- `PrewarmingNext → Crossfading` when eligible AND next is "ready".
- Abort to `SinglePlaying` if next fails to load or queue changes.

Ready definition (iOS, conservative):
- next `AVPlayerItem.status == .readyToPlay`
- AND next `isPlaybackLikelyToKeepUp == true` (or equivalent readiness signal)

### D. Just-in-time stream refresh

Because SoundCloud URLs expire, Mix Mode must ensure:
- The next stream URL/token is fetched/refreshed when `timeRemaining <= prewarmSeconds`.
- If cached stream could expire before `now + crossfadeSeconds + 15s`, force refresh for the next track.

### E. User actions

- Pause/resume affects both players during crossfade.
- Seek earlier than `prewarmStartTime` cancels prewarm/crossfade.
- Skip next during fade snaps to next (next volume=1, current volume=0, stop current).

### F. Observability (required)

Emit compact logs/events:
- `mix_prewarm_start`
- `mix_prewarm_ready`
- `mix_fade_start`
- `mix_fade_complete`
- `mix_fade_abort(reason)`

Each includes:
- `trackId`, `nextTrackId`, `crossfadeSeconds`, and an abort `reason` enum.

## Verification Steps (Agent Loop)

### Step 0 — Baseline

- Build succeeds before any changes.

### Step 1 — Pure Swift mix core + unit tests

Create a pure Swift module (prefer SwiftPM package in-repo) that contains:
- Curve math
- Scheduler
- State machine

Verification:
- `swift test` (fast, no simulator/device)

Gate:
- Tests pass.

### Step 2 — Integrate into playback behind flag

Implementation constraints:
- Mix Mode off: no behavior changes.
- At most two players active.
- If next cannot be prepared in time: abort fade and continue playback normally.

Verification:
- `swift test` (still green)
- `xcodebuild build` for the app target

**Harness note (for sandboxed environments):**
- Force temp + derived data into a repo-local directory to avoid permission issues:
  - set `TMPDIR="$PWD/.tmp"`
  - use `-derivedDataPath "$PWD/.derived-data"`

### Step 3 — Manual QA (device)

1. Mix Mode off: regression check queue advance, pause/resume, seek.
2. Mix Mode on: crossfade at track boundary (6s), verify smooth ramp.
3. Network hiccup: verify abort reason logged and playback continues.
4. Background/foreground: verify no stuck crossfade state.

## “Done” Definition

- Mix Mode off: identical behavior to current production behavior.
- Mix Mode on: automatic crossfade when next is ready; safe fallback otherwise.
- No crashes, no leaked players/items, and clear abort reasons.
- Pure logic is unit-tested; app builds cleanly.
