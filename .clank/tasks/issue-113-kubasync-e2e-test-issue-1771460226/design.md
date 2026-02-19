# Design: kubasync E2E Test Pipeline

Task: kubasync e2e test issue 1771460226
Branch: clanker/issue-113-kubasync-e2e-test-issue-1771460226

---

## Overview

This design defines the e2e validation pipeline for the mixbridge-ios project, scoped to what is feasible within a Kubernetes environment without macOS nodes. The pipeline validates Swift package builds, code quality, and sync engine contracts.

---

## Architecture

```
PR opened/updated on main
        │
        ▼
  GitHub Actions workflow
  (.github/workflows/kubasync-e2e.yml)
        │
        ▼
  Trigger kubasync job
  (HTTP webhook or gh CLI)
        │
        ▼
  ┌─────────────────────────────────┐
  │  kubasync namespace (K8s)       │
  │                                 │
  │  Job: mixbridge-e2e             │
  │  Image: swift:5.10-jammy        │
  │                                 │
  │  Steps:                         │
  │  1. Checkout repo               │
  │  2. SPM resolve & build pkgs    │
  │  3. SwiftLint validation        │
  │  4. SwiftFormat --lint check    │
  │  5. Report results              │
  └─────────────────────────────────┘
        │
        ▼
  GitHub commit status updated
```

---

## Phase 1: Swift Package Validation (Linux-compatible)

### Scope
Validate the two Swift packages that can build on Linux:

| Package | Dependencies | Linux-buildable |
|---------|-------------|-----------------|
| `MixBridgeDomain` | None | Yes |
| `MixBridgeDB` | GRDB.swift 7.x | Yes (GRDB supports Linux via SQLite) |

### Job Manifest

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: mixbridge-e2e-${SHA:0:8}
  namespace: kubasync
  labels:
    app: mixbridge-e2e
    pr: "${PR_NUMBER}"
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: swift-build
        image: swift:5.10-jammy
        command: ["/bin/bash", "-c"]
        args:
        - |
          set -euo pipefail

          # Clone and checkout
          git clone --depth=1 --branch=${BRANCH} ${REPO_URL} /workspace
          cd /workspace

          # Build MixBridgeDomain
          echo "::group::Build MixBridgeDomain"
          cd Packages/MixBridgeDomain
          swift package resolve
          swift build
          cd /workspace
          echo "::endgroup::"

          # Build MixBridgeDB
          echo "::group::Build MixBridgeDB"
          cd Packages/MixBridgeDB
          swift package resolve
          swift build
          cd /workspace
          echo "::endgroup::"

          # Lint (install mint + tools)
          echo "::group::SwiftLint"
          apt-get update && apt-get install -y mint || true
          mint bootstrap
          mint run swiftlint --strict
          echo "::endgroup::"

          echo "::group::SwiftFormat"
          mint run swiftformat --lint .
          echo "::endgroup::"

          echo "All checks passed"
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
```

### Platform Override for Linux Builds

The Package.swift files specify `platforms: [.iOS(.v17), .macOS(.v14)]`. For Linux builds, SPM ignores platform constraints, so this is not a blocker. However, if any source files import `UIKit` or `SwiftUI`, those files must be conditionally compiled:

- `MixBridgeDomain`: Pure domain models with no iOS framework imports — builds on Linux as-is.
- `MixBridgeDB`: Uses GRDB only — builds on Linux as-is.

---

## Phase 2: GitHub Actions Workflow

Since no GitHub Actions workflows exist in this repo, create one:

### File: `.github/workflows/kubasync-e2e.yml`

```yaml
name: kubasync-e2e

on:
  pull_request:
    branches: [main]

jobs:
  swift-packages:
    runs-on: ubuntu-latest
    container:
      image: swift:5.10-jammy
    steps:
      - uses: actions/checkout@v4

      - name: Build MixBridgeDomain
        run: |
          cd Packages/MixBridgeDomain
          swift package resolve
          swift build

      - name: Build MixBridgeDB
        run: |
          cd Packages/MixBridgeDB
          swift package resolve
          swift build

  lint:
    runs-on: ubuntu-latest
    container:
      image: swift:5.10-jammy
    steps:
      - uses: actions/checkout@v4

      - name: Install Mint
        run: |
          git clone https://github.com/yonaskolb/Mint.git /tmp/mint
          cd /tmp/mint
          swift build -c release
          cp .build/release/mint /usr/local/bin/

      - name: SwiftLint
        run: mint run swiftlint --strict

      - name: SwiftFormat
        run: mint run swiftformat --lint .
```

This workflow serves dual purpose:
1. Runs directly as a GitHub Actions check on PRs
2. Can be triggered by kubasync as a dispatch event if the kubasync pipeline watches for workflows

---

## Phase 3: Sync Engine Contract Tests (Future)

Once the pipeline is stable, extend to validate sync engine contracts:

### Prerequisites
- Dedicated test Convex deployment (separate from `avid-falcon-471.convex.cloud`)
- Convex URL made configurable via environment variable in `ConvexService.swift`
- Test user credentials stored as K8s Secrets
- Convex HTTP API accessible from kubasync namespace (network egress policy)

### Test Strategy
```
Test harness (Swift CLI or script)
    │
    ├── Create test user via Convex mutation
    ├── Seed test data (playlists, tracks, history)
    ├── Call sync endpoints via HTTP
    ├── Verify round-trip: write → read → compare
    ├── Verify optimistic update → failure → rollback
    └── Cleanup: delete test user and data
```

### Required Code Changes for Phase 3
1. **Make Convex URL configurable**: Extract the hardcoded URL in `ConvexService.swift` to read from `ProcessInfo.processInfo.environment["CONVEX_URL"]` with fallback to current value
2. **Create test harness**: A Swift executable target that imports `MixBridgeDB` and `MixBridgeDomain` and exercises sync operations via HTTP
3. **Add test Convex functions**: Backend functions for test data seeding and cleanup (in the separate `mixbridge-web` repo)

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Initial scope | Swift package builds + linting | Only these are Linux-buildable; validates code quality without macOS |
| Container image | `swift:5.10-jammy` | Matches `.swift-version` (Swift 5), Ubuntu-based for K8s compatibility |
| CI platform | GitHub Actions + kubasync Job | GitHub Actions for PR checks; K8s Job manifest for kubasync namespace |
| Status checks | Advisory (non-blocking) initially | Don't block merges until pipeline stability is proven |
| Sync engine tests | Deferred to Phase 3 | Requires test Convex deployment and code changes |
| Full Xcode builds | Out of scope | Requires macOS nodes not available in kubasync cluster |

---

## Artifacts to Deliver

| Artifact | Description |
|----------|-------------|
| `.github/workflows/kubasync-e2e.yml` | GitHub Actions workflow for PR checks |
| K8s Job manifest (documentation) | Reference manifest for kubasync pipeline operators |
| `.clank/tasks/.../ticket.md` | Issue tracking (exists) |
| `.clank/tasks/.../research-questions.md` | Research questions (exists) |
| `.clank/tasks/.../research.md` | Research findings (exists) |
| `.clank/tasks/.../design.md` | This document |

---

## Open Questions for Platform Team

1. Does kubasync trigger jobs via webhook, watch GitHub events, or require manual dispatch?
2. Is there a macOS node pool in the kubasync cluster for future full Xcode builds?
3. What secrets injection mechanism does kubasync use (K8s Secrets, Vault, sealed-secrets)?
4. Should the GitHub Actions workflow also trigger the kubasync job, or are they independent?
5. What is the artifact/log retrieval mechanism for completed kubasync jobs?
