#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
CLIENT=".build/release/magsafe-led-client"
[[ -x "$CLIENT" ]] || { print -u2 "Release client is missing"; exit 66; }

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-daemon-client.XXXXXX")"
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$TEMP_DIR"' EXIT
SOCKET="$TEMP_DIR/daemon.sock"

cat > "$TEMP_DIR/server.py" <<'PY'
import os
import socket
import sys

path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(8)
responses = {
    "ping": "0\tpong\n",
    "probe": "0\tsupported\n",
    "status": "0\t4\n",
    "off": "0\tok\n",
    "blink-fast": "69\tsimulated failure\n",
}
for _ in range(5):
    conn, _ = server.accept()
    data = conn.recv(256).decode().strip()
    conn.sendall(responses.get(data, "64\tunknown\n").encode())
    conn.close()
server.close()
PY

python3 "$TEMP_DIR/server.py" "$SOCKET" &
SERVER_PID=$!
for _ in {1..50}; do [[ -S "$SOCKET" ]] && break; sleep 0.02; done
[[ -S "$SOCKET" ]] || { print -u2 "Mock daemon did not start"; exit 1; }

[[ "$(MAGSAFE_DARK_SOCKET="$SOCKET" "$CLIENT" ping)" == pong ]]
[[ "$(MAGSAFE_DARK_SOCKET="$SOCKET" "$CLIENT" probe)" == supported ]]
[[ "$(MAGSAFE_DARK_SOCKET="$SOCKET" "$CLIENT" status)" == 4 ]]
[[ "$(MAGSAFE_DARK_SOCKET="$SOCKET" "$CLIENT" off)" == ok ]]

set +e
OUTPUT="$(MAGSAFE_DARK_SOCKET="$SOCKET" "$CLIENT" blink-fast 2>&1)"
CODE=$?
set -e
[[ "$CODE" == 69 ]]
[[ "$OUTPUT" == "simulated failure" ]]

wait "$SERVER_PID"
SERVER_PID=""
print "Daemon client transport tests passed"
