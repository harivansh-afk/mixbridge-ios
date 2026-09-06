#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
binary="$(mktemp -t mixbridge-download-tests.XXXXXX)"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
  mixbridge/Services/DownloadFailure.swift \
  mixbridge/Services/DownloadScheduler.swift \
  mixbridge/Services/DownloadFileWriter.swift \
  Tests/DownloadReliabilityTests.swift -o "$binary"
"$binary"
