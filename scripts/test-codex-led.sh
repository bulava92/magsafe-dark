#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-codex-led-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/magsafe-dark" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf '%s\n' "$*" >> "$MAGSAFE_TEST_LOG"
EOF
chmod 755 "$TEMP_DIR/magsafe-dark"

cat > "$TEMP_DIR/codex-ok" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEX_TEST_OUTPUT"
[[ -n "${CODEX_TEST_SLEEP:-}" ]] && sleep "$CODEX_TEST_SLEEP"
exit 0
EOF
chmod 755 "$TEMP_DIR/codex-ok"

cat > "$TEMP_DIR/codex-fail" <<'EOF'
#!/bin/zsh
[[ -n "${CODEX_TEST_SLEEP:-}" ]] && sleep "$CODEX_TEST_SLEEP"
exit 23
EOF
chmod 755 "$TEMP_DIR/codex-fail"

export MAGSAFE_TEST_LOG="$TEMP_DIR/magsafe.log"
export CODEX_TEST_OUTPUT="$TEMP_DIR/args.txt"
export MAGSAFE_DARK_TASK_ROOT="$TEMP_DIR/tasks"

MAGSAFE_DARK_BIN="$TEMP_DIR/magsafe-dark" CODEX_BIN="$TEMP_DIR/codex-ok" zsh scripts/codex-led "one two" 'three"four'

EXPECTED=$'one two\nthree"four'
ACTUAL="$(cat "$CODEX_TEST_OUTPUT")"
[[ "$ACTUAL" == "$EXPECTED" ]] || {
  print -u2 "codex-led changed command arguments"
  print -u2 "expected:"
  print -r -- "$EXPECTED" >&2
  print -u2 "actual:"
  print -r -- "$ACTUAL" >&2
  exit 1
}

[[ "$(cat "$MAGSAFE_TEST_LOG")" == $'working\nsuccess' ]] || {
  print -u2 "single successful task produced unexpected LED sequence"
  cat "$MAGSAFE_TEST_LOG" >&2
  exit 1
}

: > "$MAGSAFE_TEST_LOG"
set +e
MAGSAFE_DARK_BIN="$TEMP_DIR/magsafe-dark" CODEX_BIN="$TEMP_DIR/codex-fail" zsh scripts/codex-led
CODE=$?
set -e
[[ "$CODE" == 23 ]] || {
  print -u2 "codex-led did not preserve exit code: $CODE"
  exit 1
}
[[ "$(cat "$MAGSAFE_TEST_LOG")" == $'working\nerror' ]] || {
  print -u2 "single failed task produced unexpected LED sequence"
  cat "$MAGSAFE_TEST_LOG" >&2
  exit 1
}

: > "$MAGSAFE_TEST_LOG"
CODEX_TEST_SLEEP=0.4 MAGSAFE_DARK_BIN="$TEMP_DIR/magsafe-dark" CODEX_BIN="$TEMP_DIR/codex-ok" zsh scripts/codex-led first &
PID1=$!
sleep 0.1
CODEX_TEST_SLEEP=0.1 MAGSAFE_DARK_BIN="$TEMP_DIR/magsafe-dark" CODEX_BIN="$TEMP_DIR/codex-fail" zsh scripts/codex-led second &
PID2=$!
set +e
wait "$PID2"
CODE2=$?
wait "$PID1"
CODE1=$?
set -e
[[ "$CODE1" == 0 && "$CODE2" == 23 ]] || {
  print -u2 "parallel task exit codes were not preserved: $CODE1 $CODE2"
  exit 1
}

PARALLEL_LOG="$(cat "$MAGSAFE_TEST_LOG")"
[[ "$PARALLEL_LOG" == $'working\nsuccess' ]] || {
  print -u2 "parallel tasks produced unexpected LED sequence"
  cat "$MAGSAFE_TEST_LOG" >&2
  exit 1
}

TASK_FILES=("$MAGSAFE_DARK_TASK_ROOT"/*.task(N))
(( ${#TASK_FILES[@]} == 0 )) || {
  print -u2 "parallel task registry was not cleaned"
  exit 1
}

print "codex-led tests passed"
