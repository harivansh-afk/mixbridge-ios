# Offline download reliability checks

Run on macOS with Swift installed:

```sh
bash Tests/run-download-tests.sh
```

On NixOS (Swift's Foundation module needs development shell hooks; `nix shell`
alone is insufficient):

```sh
nix develop --impure --expr 'let p = import <nixpkgs> {}; in p.mkShell { nativeBuildInputs = [ p.swift ]; buildInputs = [ p.swiftPackages.Foundation ]; }' -c bash Tests/run-download-tests.sh
```

The harness compiles the production error policy, direct-transfer retry loop,
file writer and global scheduler with complete concurrency diagnostics and
warnings as errors. It exercises injected byte interruption, partial cleanup,
truncated content, retry exhaustion, permanent failures, Retry-After seconds and
HTTP dates, backoff/write/pre-start cancellation, and global/queued cancellation
ownership. No provider, backend, credentials or media are accessed. Fixtures are
synthetic bytes and example.invalid URLs.

Retries restart direct GET transfers only, at most three attempts (two retries),
with exponential backoff and jitter. A Retry-After over 30 seconds stops automatic
retry rather than shortening the hint. No automatic replay of token exchange,
/stream, or the expensive /download POST. Signed URL expiry/auth errors do not
retry; a later manual attempt resolves a fresh URL. The global three-job slot is
held through retries and cleanup. Background/resumable jobs are not implemented.

These are portable component tests, not a complete iOS build or XCTest UI/DB
integration suite. Linux cannot validate SwiftUI, the app's Xcode actor-isolation
settings, Apple URLSession's byte transport, GRDB cancellation races or a real
device. Run an Xcode build and device/network-fault checks before release.
