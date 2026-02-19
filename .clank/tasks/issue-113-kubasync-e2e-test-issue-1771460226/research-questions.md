# Research Questions

Task: kubasync e2e test issue 1771460226
Branch: clanker/issue-113-kubasync-e2e-test-issue-1771460226

---

## 1. Kubasync Pipeline Architecture

- What is the kubasync remote pipeline and where does its configuration live (outside this repo)?
- What Kubernetes namespace, service account, and RBAC permissions are required to run jobs in the `kubasync` namespace?
- What is the expected job manifest format (CronJob, Job, or custom CRD)?
- How does kubasync trigger e2e runs -- webhook on PR, manual dispatch, or scheduled?
- What container image(s) are available or need to be built to run iOS-related e2e validation in a K8s pod?

## 2. E2E Test Scope & Strategy

- Given that all unit tests were deliberately removed from the repo, what does "e2e validation" mean in this context -- build verification, UI automation (XCUITest), API contract tests, or integration smoke tests?
- Is the e2e scope limited to verifying the Convex backend sync pipeline (playlists, liked tracks, history), or does it include audio playback and UI flows?
- Should the e2e tests run against a staging Convex deployment (`avid-falcon-471.convex.cloud`) or a dedicated test environment?
- Are there SoundCloud/Spotify API sandbox credentials available for e2e tests, or should external services be mocked?

## 3. iOS Build & Test Infrastructure in K8s

- How will Xcode builds run inside Kubernetes? Options: macOS self-hosted runners, cross-compilation, or build-only validation (SwiftLint/SwiftFormat/SPM resolve)?
- Is there a macOS node pool or Orka/Anka virtualization layer in the kubasync cluster for native iOS compilation?
- If full Xcode builds aren't feasible in K8s, should e2e validation be scoped to the Swift packages (`MixBridgeDomain`, `MixBridgeDB`) which can build on Linux with swift:latest images?
- What Swift toolchain version is required (currently Swift 5, targeting iOS 17+)?

## 4. .clank Artifact Requirements

- What is the full expected artifact set beyond `ticket.md`? Specifically, does the acceptance criteria ("generate .clank ticket/research/design artifacts") require:
  - `research-questions.md` (this file)
  - `research.md` (answers to research questions)
  - `design.md` (implementation design / architecture decision)
  - `verification_spec.md` (for the verifier skill)
  - Kubernetes manifests or Helm charts?
- Is there a `.clank` artifact schema or template to follow from other completed tasks?
- Should artifacts reference or link to external kubasync documentation?

## 5. PR & CI Integration

- What branch protection rules exist on `main` -- are there required status checks that kubasync must report?
- Should the PR include a GitHub Actions workflow that triggers the kubasync job, or is kubasync independently watching for PRs?
- What labels, annotations, or PR body conventions does kubasync look for to pick up e2e jobs?
- Is there an existing GitHub Actions workflow (`.github/workflows/`) to integrate with, or does one need to be created?

## 6. Test Data & Environment

- What test data seeding is required for e2e runs (test user accounts, playlists, tracks)?
- How are secrets (Convex deploy key, Spotify/SoundCloud API keys, Firebase config) injected into K8s jobs -- K8s Secrets, Vault, or sealed-secrets?
- Is there a test Convex deployment separate from production, or do e2e tests run against the same backend?
- What cleanup/teardown is expected after e2e runs to avoid data pollution?

## 7. Observability & Reporting

- Where should e2e test results be reported -- GitHub commit status, PR comment, Slack, or a dashboard?
- What logging/tracing is available from kubasync jobs for debugging failures?
- Should test artifacts (screenshots, logs, coverage reports) be uploaded to an artifact store?
- What is the expected SLA for e2e run duration (timeout configuration for K8s jobs)?

## 8. Sync Engine Validation

- The app has a sophisticated local-first sync engine (PlaylistSync, HistorySync, LikedSync, etc.) with actor-based operation queues. Should e2e tests validate sync correctness (write locally -> verify cloud state)?
- Are there existing Convex functions or HTTP endpoints that can be called from a test harness to verify backend state?
- Should conflict resolution scenarios (concurrent edits from multiple devices) be part of e2e scope?

## 9. Risk & Dependencies

- What are the external dependencies that could cause flaky e2e tests (Convex availability, SoundCloud rate limits, network policies in K8s)?
- Is there a retry/backoff strategy for transient failures in the kubasync pipeline?
- What is the rollback plan if kubasync e2e tests block the PR merge pipeline?
- Are there cost implications for running macOS VMs or specialized hardware in K8s for iOS builds?
