- Level 0 — Clean queueing (baseline)
      - Gapless-ish handoff + “next track ready” guarantee
      - Options (user-facing):
          - Transition: Off / Instant
      - Personalization:
          - None (just reliability)
  - Level 1 — Simple crossfade (low complexity, big win)
      - Fixed seconds, equal‑power curve, safe fallback
      - Options:
          - Transition: Crossfade
          - Crossfade length: 0–12s (or presets: 0 / 3 / 6 / 9 / 12)
      - Personalization:
          - Default length learned from “skip during transition” rate (if skips spike, shorten)
  - Level 2 — Smart crossfade length (“content aware”, still simple)
      - Same crossfade mechanism, but picks length per track pair using a few features
      - Inputs:
          - BPM confidence, energy, vocal presence, intro/outro length (even coarse)
      - Options:
          - Smart length: Off / On
          - Presets: Chill (longer) / Balanced / Punchy (shorter)
      - Personalization:
          - Per-user slider “Smooth ↔ Punchy” that just biases length + aggressiveness
          - Learn per-user baseline loudness/volume preference and keep perceived loudness stable
  - Level 3 — Beat-aligned start (BPM intelligent without full DJ complexity)
      - Start the incoming track on a beat grid boundary (or bar boundary) near fade start
      - If beat grid confidence is low, fall back to Level 1/2 behavior
      - Inputs:
          - BPM + beat phase/downbeat (you’ll need phase, not just BPM)
      - Options:
          - Beat sync: Off / On
          - Sync strength: Loose (beat) / Tight (bar)
      - Personalization:
          - If user tends to like EDM/house, default to Tight; if not, default to Loose or off
  - Level 4 — Key-aware transitions (note intelligent, minimal UX)
      - Don’t do harmonic “mixing” yet; just avoid obviously bad clashes
      - Inputs:
          - Key + confidence (Camelot wheel mapping is a nice UI layer but optional)
      - Behavior:
          - When building the next suggestions/queue ordering, prefer compatible keys
          - When transitioning, if keys are incompatible and vocals present, shorten overlap
      - Options:
          - Harmonic: Off / Prefer compatible
      - Personalization:
          - Track whether user skips more on “incompatible” transitions; adjust strictness
  - Level 5 — Phrase-aware transitions (structure intelligent, still not DSP-heavy)
      - Choose transition points where it’s musically “safe”:
          - outgoing track: outro / low‑vocal section
          - incoming track: intro / low‑vocal section
      - Inputs:
          - Section markers (intro/verse/chorus/outro) or at least “energy envelope” + vocal probability
      - Options:
          - Phrase-aware: Off / On
          - Vocal overlap: Avoid / Allow
      - Personalization:
          - Learn “vocal overlap tolerance” from skip + volume adjustments during transitions
  - Level 6 — Micro-DJ touches (keep it optional; complexity contained)
      - Still no time-stretch by default; add small enhancements that feel “pro”:
          - Auto-duck incoming track highs during first half of fade (simple EQ tilt)
          - Gentle low-pass on outgoing during last 20% (creates “handoff” feel)
          - Loudness normalization during crossfade (target LUFS-ish proxy)
      - Options:
          - DJ polish: Off / On
          - Advanced: Ducking: None / Light / Medium
      - Personalization:
          - Adapt ducking intensity based on device output (headphones vs speaker) and user “smooth/punchy”

  How to expose this without overwhelming users

  - One primary control: Transition Style
      - Instant, Crossfade, Smart, DJ
  - One secondary control: Smooth ↔ Punchy (single slider)
      - Internally maps to: crossfade length, beat alignment strictness, vocal overlap avoidance, ducking intensity
  - A single “Advanced” sheet (optional):
      - Crossfade seconds
      - Beat sync (loose/tight)
      - Harmonic prefer compatible
      - Vocal overlap avoid
      - DJ polish

  Personalization model (low complexity, high payoff)

  - Start with rules + lightweight learning, not ML:
      - Signals: skips within transition window, manual “next” during fade, volume changes during fade, “like” events after transitions
      - Maintain a per-user profile:
          - preferred crossfade length baseline
          - punchy/smooth bias
          - beat-sync preference confidence
          - vocal overlap tolerance
          - harmonic strictness
  - Keep it transparent:
      - “Auto” mode that can be toggled off
      - A “reset mixing preferences” button

  Keep the system simple architecturally

  - Make the “Mixer” produce a small TransitionPlan:
      - startNextAt, fadeDuration, curve, optional eqPreset, syncMode, confidence
  - The player only executes the plan; planning evolves over time without destabilizing playback.

  If you want, tell me what “note intelligent” means for you (key detection, Camelot, or actual pitch-class profile), and whether you already have key/energy/vocal features in the
  web repo, and I’ll map those inputs to a concrete TransitionPlan schema.
