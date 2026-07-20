#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
LEGACY_HELPER=".build/release/magsafe-led-helper"
DAEMON=".build/release/magsafe-led-daemon"
CLIENT=".build/release/magsafe-led-client"

for binary in "$LEGACY_HELPER" "$DAEMON" "$CLIENT"; do
  [[ -x "$binary" ]] || {
    print -u2 "Release binary is missing: $binary"
    exit 66
  }
done

set +e
OUTPUT="$("$LEGACY_HELPER" probe 2>&1)"
CODE=$?
set -e
if (( EUID == 0 )); then
  [[ "$CODE" == 0 || "$CODE" == 69 ]]
else
  [[ "$CODE" == 77 ]]
  [[ "$OUTPUT" == *"Run as root."* ]]
fi

if (( EUID != 0 )); then
  set +e
  OUTPUT="$("$DAEMON" 2>&1)"
  CODE=$?
  set -e
  [[ "$CODE" == 77 ]]
  [[ "$OUTPUT" == *"must run as root"* ]]
fi

set +e
OUTPUT="$("$CLIENT" invalid-command 2>&1)"
CODE=$?
set -e
[[ "$CODE" == 64 ]]
[[ "$OUTPUT" == *"Usage: magsafe-led-client"* ]]

print "Helper, daemon and client interface tests passed"
