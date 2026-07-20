#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-core-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp scripts/test-core.swift "$TEMP_DIR/main.swift"
swiftc \
  Sources/MagSafeCore/LEDState.swift \
  "$TEMP_DIR/main.swift" \
  -o "$TEMP_DIR/magsafe-core-tests"

"$TEMP_DIR/magsafe-core-tests"
