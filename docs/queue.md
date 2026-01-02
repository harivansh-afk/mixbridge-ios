• Yes — rewriting the iOS queue as an explicit queue wrapper makes sense, but only if we use
  it to enforce real invariants and we also fix a key Convex/iOS mismatch that’s currently
  breaking removals.

  ### The biggest nuance you have right now (Convex + iOS mismatch)

  In convex/queues.ts, addTracksBatch intentionally returns null:

  - mixbridge-web/convex/queues.ts: addTracksBatch returns null (“iOS mutation expects String?
    not [String] not [String]”).

  On iOS, that means after:

  - QueueManager.setQueue(...) and QueueManager.appendTracks(...)

  you do not get back queueTrackIds, and your iOS QueueManager.queueTrackIds mapping is
  missing for those tracks. So later:

  - QueueManager.removeTrack(...) fails because it requires queueTrackIds[track.id].
  - Therefore “remove current track when playback starts” silently fails often.
  - So your queue still contains the currently playing track at index 0 sometimes.
  - Then any “avoid replay current” logic will select index 1 → feels like “skipping one”, or
    you get loops/backtracking.

  This is why a queue rewrite alone won’t solve it unless we also solve “IDs + atomic local
  mutation”.

  ———

  ## Does a dedicated Queue structure wrapper make sense?

  ### Why it makes sense

  - Lets you enforce the invariant you actually want for UX:
      - Queue contains only upcoming tracks. Current track is not inside queue.
      - Therefore Next is always queue.peek() (index 0).
  - Centralizes all operations that currently happen in 3 places (UI reorder, QueueManager,
    PlaybackCoordinator) into one place:
      - enqueue, insertNext, remove, move, replaceAll, peek, pop.
  - Lets you make queue changes synchronous locally (for deterministic “Next”), while backend
    sync happens async (Convex).

  ### Why it might not help (unless we do it right)

  - If the wrapper still depends on async removals and missing Convex IDs, you get the same
    race/bugs with nicer method names.
  - Convex rollback / optimistic updates need to be modeled, or you’ll make playback “snap
    back” unpredictably.

  ———

  ## Implementation plan (staged, minimal breakage)

  ### 0) Define the invariants up front (design contract)

  - queue holds upcoming items only.
  - current track is tracked separately (PlaybackCoordinator/PlayerState).
  - nextToPlay = queue.peek() always.
  - On track start (autoplay or manual play), if that track came from the queue:
      - remove it from queue immediately locally
      - then sync backend removal async.

  This is the only way “Next = top of cue” becomes 100% true.

  ———

  ## 1) Convex changes (recommended)

  Right now addTracksBatch returning null is a core blocker.

  ### Option A (best): return inserted IDs (or documents)

  Change mixbridge-web/convex/queues.ts:addTracksBatch to return either:

  - string[] of inserted queueTracks ids, OR better
  - array of { _id, trackId, position } (or the full queueTracks docs)

  Then iOS can maintain queueTrackIds immediately, without needing a reload.

  ### Option B (fallback): reload after batch

  Keep returning null, but iOS must call getQueueTracks after setQueue / addTracksToQueueBatch
  and rebuild its local state + id mapping.
  This is slower and adds latency but is simpler if you don’t want to touch Convex.

  I strongly recommend Option A because it fixes a correctness issue, not just performance.

  ———

  ## 2) iOS Convex client fix (needed for Option A)

  Your iOS ConvexService.mutation(...) is hard-coded to decode String? only.

  Add:

  - mutation<T: Codable>(...) async throws -> T?

  So we can decode [String] or [ConvexQueueTrack] from batch calls.

  ———

  ## 3) iOS Queue rewrite (wrapper)

  Introduce a new type (example shape):

  - QueueItem
      - queueTrackId: String (Convex queueTracks._id)
      - trackId: String
      - track: Track
      - soundCloudTrack: SoundCloudTrack?
      - position: Int (optional local convenience)
  - PlaybackQueue (or UpNextQueue)
      - @MainActor, @Observable
      - holds [QueueItem]
      - operations:
          - peek() -> QueueItem?
          - popNext() -> QueueItem? (local mutation only)
          - remove(trackId:) / remove(queueTrackId:)
          - insertNext(item:)
          - append(items:)
          - move(from:to:)
          - replaceAll(items:)

  Then refactor current QueueManager into:

  - a thin “repository” that:
      - loads from Convex,
      - performs optimistic local edits via PlaybackQueue,
      - syncs Convex and rolls back if needed.

  Critically: UI must stop mutating queueTracks directly (like .move(...) on the array) and
  must call queue methods instead.

  ———

  ## 4) Playback integration (this is where UX becomes deterministic)

  - PlaybackCoordinator.playNext() becomes trivial:
      - if queue.peek exists → play it
      - else → stop / ready
  - On “track started playing”:
      - synchronously queue.popIfMatches(trackId) (or remove(trackId))
      - async call backend remove using stored queueTrackId

  Do the same for mix mode:

  - mix prewarm chooses queue.peek() (not “after current index”)
  - queue changes call mixEngine.handleQueueChanged() + refresh prewarm

  ———

  ## 5) Migration approach (Graphite-friendly stack)

  1. PR: Convex addTracksBatch returns ids/docs (optional if you pick reload approach)
  2. PR: iOS generic Convex mutation decoder + update setQueue/addTracksToQueueBatch to
     populate id mapping (or reload)
  3. PR: introduce PlaybackQueue + adapt QueueManager internally (keep same public API
     initially)
  4. PR: migrate PlaybackCoordinator to use peek() for Next/autoplay + synchronous consume-on-
     start
  5. PR: migrate UI reorder/delete to call queue APIs (no direct array mutation)

  ———

  If you tell me which backend direction you prefer:

  - A) modify Convex to return IDs/docs (recommended), or
  - B) keep Convex as-is and force reload after batch,
    I’ll write the concrete PR stack plan (exact files/functions to change, plus ordering so
    nothing breaks mid-migration).
