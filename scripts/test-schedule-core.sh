#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-schedule-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp scripts/test-schedule-core.swift "$TEMP_DIR/main.swift"
swiftc \
  Sources/MagSafeCore/LEDState.swift \
  Sources/MagSafeCore/Schedule.swift \
  "$TEMP_DIR/main.swift" \
  -o "$TEMP_DIR/magsafe-schedule-tests"

"$TEMP_DIR/magsafe-schedule-tests"
