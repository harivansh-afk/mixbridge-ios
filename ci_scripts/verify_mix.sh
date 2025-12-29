#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Ensure hermetic temp/output locations (helps in sandboxed CI environments).
mkdir -p .tmp .derived-data .home
export TMPDIR="$ROOT_DIR/.tmp"
export HOME="$ROOT_DIR/.home"

# Enforce presence of pure, unit-testable MixCore package.
if [[ ! -f "MixbridgeMixCore/Package.swift" ]]; then
  echo "[verify_mix:ios] Missing MixbridgeMixCore/Package.swift"
  echo "[verify_mix:ios] Expected: SwiftPM package containing MixCore + unit tests (swift test)"
  exit 1
fi

echo "[verify_mix:ios] swift test (MixbridgeMixCore)"
(
  cd MixbridgeMixCore
  swift test
)

echo "[verify_mix:ios] xcodebuild build (scheme: mixbridge)"
xcodebuild \
  -project mixbridge.xcodeproj \
  -scheme mixbridge \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ROOT_DIR/.derived-data" \
  build \
  -quiet
