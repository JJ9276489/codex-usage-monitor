#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/.build/test_swift_usage_reader"

mkdir -p "$ROOT_DIR/.build"

swiftc -parse-as-library \
  "$ROOT_DIR/Sources/CodexUsageMonitor/Support/UsageFormat.swift" \
  "$ROOT_DIR/Sources/CodexUsageMonitor/Models/CodexLimitStatus.swift" \
  "$ROOT_DIR/Sources/CodexUsageMonitor/Services/CodexSessionTokenUsageReader.swift" \
  "$ROOT_DIR/script/test_swift_usage_reader.swift" \
  -o "$OUTPUT"

"$OUTPUT"
