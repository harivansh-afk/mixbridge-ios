# Research Findings

Task: kubasync e2e test issue 1771460226
Branch: clanker/issue-113-kubasync-e2e-test-issue-1771460226

---

## 1. Kubasync Pipeline Architecture

**What is the kubasync remote pipeline and where does its configuration live?**
No kubasync configuration exists within this repository. The kubasync pipeline is external infrastructure — its manifests, Helm charts, and operator config live outside `mixbridge-ios`. This repo contains zero Kubernetes manifests, CRDs, or Helm charts.

**Kubernetes namespace, service account, and RBAC?**
Not determinable from this repo. The `kubasync` namespace, RBAC, and service account must be defined in the external infrastructure repository or cluster configuration. This is an open dependency that must be resolved with the platform/infra team.

**Expected job manifest format?**
Unknown from repo contents. The research questions suggest Job, CronJob, or custom CRD — this must be answered by the kubasync pipeline owners.

**How does kubasync trigger e2e runs?**
No webhook, GitHub Actions workflow, or dispatch configuration exists in this repo (`.github/workflows/` directory does not exist). The trigger mechanism is entirely external.

**Container images for iOS e2e validation?**
No Dockerfiles or container image references exist in this repo. Container images would need to be built or sourced externally (see Section 3 for feasibility analysis).

---

## 2. E2E Test Scope & Strategy

**What does "e2e validation" mean here?**
Given that all unit tests were deliberately removed, and the app is a local-first iOS music player with Convex cloud sync, e2e validation most likely means one or more of:

1. **Build verification** — Confirm the project compiles (SPM resolve + Xcode build)
2. **Sync engine integration tests** — Validate the 8 sync modules (PlaylistSync, HistorySync, LikedSync, LikedPlaylistSync, QueueSync, SearchSync, ArtistSync, UserProfileSync) against a real or test Convex deployment
3. **Swift package validation** — Build `MixBridgeDomain` (zero dependencies) and `MixBridgeDB` (depends on GRDB) on Linux with `swift:latest`

Full UI automation (XCUITest) is not feasible in K8s without macOS nodes (see Section 3).

**Sync engine scope:**
The sync engine is the most testable component. It consists of 10 files (~73KB) in `/mixbridge/Sync/` with clear API boundaries:
- All sync modules call `ConvexService` for backend communication
- All sync modules use `MixBridgeDB` (GRDB/SQLite) for local persistence
- An actor-based `OperationQueue` serializes operations

E2e tests could validate: write locally → sync to Convex → read back and verify state consistency.

**Target environment:**
The app is hardcoded to `https://avid-falcon-471.convex.cloud` in `ConvexService.swift`. A dedicated test deployment would require either:
- A separate Convex deployment URL injected via environment variable (currently hardcoded)
- Running against the existing deployment with test-scoped data

**External service mocking:**
SoundCloud and Spotify integrations are used for streaming (SpotifyStreamService, SpotifyAuthManager, SoundCloud URL parsing). For e2e tests focused on sync validation, these can be mocked or excluded from scope entirely.

---

## 3. iOS Build & Test Infrastructure in K8s

**Xcode builds in Kubernetes:**
Full Xcode builds require macOS. There is no evidence of macOS node pools, Orka, or Anka virtualization in the cluster (no config in this repo). Options:

| Approach | Feasibility | Notes |
|----------|-------------|-------|
| macOS self-hosted runners | External dependency | Requires macOS hardware or cloud VMs (AWS EC2 Mac, MacStadium) |
| Orka/Anka in K8s | Unknown | Requires specialized cluster setup |
| Linux Swift builds only | Feasible | `MixBridgeDomain` and `MixBridgeDB` packages can build on Linux with `swift:latest` |
| Build-only validation | Feasible | SwiftLint + SwiftFormat + SPM resolve using `swift:latest` or `mint`-based image |

**Recommended path for K8s:**
Scope e2e to what's buildable on Linux:
- `MixBridgeDomain` (pure Swift models, no iOS frameworks, iOS 17+ platform spec can be relaxed for test builds)
- `MixBridgeDB` (depends on GRDB which supports Linux)
- SwiftLint / SwiftFormat validation (defined in `Mintfile`: SwiftFormat 0.55.3, SwiftLint 0.58.2)

The main `mixbridge` app target imports UIKit/SwiftUI and cannot build on Linux.

**Swift toolchain:**
`.swift-version` specifies Swift 5. Packages target iOS 17+ / macOS 14+. The `swift:5.10` or `swift:latest` Docker image would work for package-level builds.

---

## 4. .clank Artifact Requirements

**Expected artifact set:**
Based on the acceptance criteria ("generate .clank ticket/research/design artifacts"), the required artifacts are:

| Artifact | Status | Location |
|----------|--------|----------|
| `ticket.md` | Complete | `.clank/tasks/.../ticket.md` |
| `research-questions.md` | Complete | `.clank/tasks/.../research-questions.md` |
| `research.md` | This file | `.clank/tasks/.../research.md` |
| `design.md` | Pending | `.clank/tasks/.../design.md` |

**Schema/template:**
No `.clank` artifact schema or template exists from other completed tasks — this is the first task in the `.clank/tasks/` directory. The `.clank/.claude/agents/README.md` only states "Repo-owned skill prompts live here."

A `verification_spec.md` may be useful for the verifier skill but is not explicitly required by the acceptance criteria.

---

## 5. PR & CI Integration

**Branch protection on `main`:**
Not determinable from repo contents. No `.github/` directory exists — there are no Actions workflows, CODEOWNERS, or branch protection configuration files.

**GitHub Actions:**
None exist. The only CI configuration is `ci_scripts/ci_post_clone.sh` which is an Xcode Cloud script that increments the build number using `agvtool` and `$CI_BUILD_NUMBER`. This indicates the project uses **Xcode Cloud** (not GitHub Actions) for its primary CI.

**Kubasync integration:**
Since no GitHub Actions workflows exist and the trigger mechanism is external, the PR should either:
1. Include a new `.github/workflows/` workflow that triggers kubasync (if kubasync supports webhook triggers)
2. Rely on kubasync independently watching for PRs (if it has its own event loop)

This is an open question for the kubasync platform team.

**Labels/conventions:**
No label conventions or PR body templates are defined in this repo.

---

## 6. Test Data & Environment

**Test data seeding:**
The sync engine operates on these entity types (from `MixBridgeDomain` models):
- `PersistedPlaylist` / `PlaylistTrack`
- `LikedTrack` / `LikedPlaylist`
- `PlayHistory`
- `PersistedQueue` / `PersistedQueueTrack`
- `PersistedSearchCache`
- `PersistedArtistCache`
- `PersistedUserProfile`

Test data seeding would require creating test user accounts and populating these entities via Convex mutations.

**Secrets injection:**
No `.env` files exist in the repo. Configuration is hardcoded:
- Convex URL: hardcoded in `ConvexService.swift`
- Statsig: initialized in `FeatureFlags.swift`
- PostHog: initialized in `Analytics.swift`
- Spotify OAuth: managed by `SpotifyAuthManager.swift`

For K8s jobs, secrets would need to be injected via K8s Secrets, environment variables, or a secrets manager. The specific mechanism depends on the kubasync cluster setup.

**Separate test environment:**
No separate test Convex deployment is referenced. The single deployment `avid-falcon-471.convex.cloud` appears to be the only backend. A dedicated test deployment should be created to avoid data pollution.

**Cleanup/teardown:**
No cleanup utilities exist. Test runs should either:
- Use ephemeral test user accounts that are deleted post-run
- Use a dedicated Convex deployment that can be reset between runs

---

## 7. Observability & Reporting

**Test result reporting:**
No test reporting infrastructure exists in this repo. Options include:
- GitHub commit status checks (requires GitHub Actions or API integration)
- PR comments via `gh` CLI or GitHub API
- External dashboards (depends on kubasync platform)

**Logging:**
The app has a `LogManager.swift` utility and a `DevLogsView.swift` debug screen, but these are iOS app-level logging, not test infrastructure logging.

**Test artifacts:**
No artifact upload mechanism exists. For K8s jobs, artifacts could be written to a PersistentVolume, S3, or similar object store.

**SLA/timeout:**
Not defined. K8s job timeout configuration would live in the job manifest (external to this repo).

---

## 8. Sync Engine Validation

**Sync correctness testing:**
The sync engine is well-structured for e2e validation. Each module follows a consistent pattern:
1. Fetch from Convex (`ConvexService.query/action/mutation`)
2. Transform to domain models (`MixBridgeDomain`)
3. Persist to local DB (`MixBridgeDB` via GRDB)
4. Support optimistic updates with rollback

Testable scenarios:
- Write locally → sync to cloud → verify cloud state matches
- Fetch from cloud → verify local DB state matches
- Optimistic update → backend failure → verify rollback

**Backend verification:**
`ConvexService.swift` exposes query/action/mutation HTTP endpoints. Test harnesses can call these directly (they're standard HTTP POST to `avid-falcon-471.convex.cloud/api/{query,action,mutation}/{functionName}`).

**Conflict resolution:**
The current sync engine uses a last-write-wins approach with optimistic updates. The `OperationQueue` (actor-based) serializes operations per-device but there's no multi-device conflict resolution. Testing concurrent edits from multiple devices would require:
- Multiple concurrent test clients
- A way to simulate race conditions
- This is likely out of scope for initial e2e validation

---

## 9. Risk & Dependencies

**External dependencies causing flakiness:**
| Dependency | Risk | Mitigation |
|-----------|------|------------|
| Convex availability | Medium | Convex is a managed service; unlikely to be down but no SLA guarantee for test environments |
| SoundCloud API rate limits | High (if testing streaming) | Mock or exclude from sync-focused e2e scope |
| Spotify API rate limits | High (if testing streaming) | Mock or exclude from sync-focused e2e scope |
| K8s network policies | Medium | Ensure kubasync namespace has egress to Convex and package registries |
| Swift package registry (GitHub) | Low | SPM dependencies are pinned in Package.resolved |

**Retry/backoff:**
No retry strategy exists in the sync engine for backend failures (sync operations fail and surface errors to the caller). The kubasync pipeline would need its own retry logic.

**Rollback plan:**
If kubasync e2e tests block merges, the mitigation is to make the status check non-required (advisory only) until stability is proven.

**Cost implications:**
- Linux Swift builds: minimal cost (standard K8s pods)
- macOS VMs (if needed for full Xcode builds): significant cost ($1-2/hr for cloud Mac instances)
- Recommendation: start with Linux-buildable scope (Swift packages + linting) to validate the pipeline, then expand

---

## Key Recommendations

1. **Scope e2e to Linux-buildable targets first**: `MixBridgeDomain`, `MixBridgeDB`, SwiftLint, SwiftFormat
2. **Defer full Xcode builds**: Require macOS infrastructure that may not be available in the kubasync cluster
3. **Create a dedicated test Convex deployment**: Avoid polluting the production backend
4. **Make Convex URL configurable**: Currently hardcoded; needs environment variable injection for test environments
5. **Start with advisory status checks**: Don't block PRs on e2e until the pipeline is stable
6. **Sync engine is the primary e2e target**: 8 well-structured modules with clear API boundaries
