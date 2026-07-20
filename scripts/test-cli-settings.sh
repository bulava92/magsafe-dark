#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/magsafe-cli-settings.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/helper" <<'EOF'
#!/bin/zsh
set -euo pipefail
STATE_FILE="${MAGSAFE_TEST_HELPER_STATE:?}"
case "${1:-}" in
  status) [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || print 0 ;;
  system) print 0 > "$STATE_FILE" ;;
  off) print 1 > "$STATE_FILE" ;;
  green) print 3 > "$STATE_FILE" ;;
  orange) print 4 > "$STATE_FILE" ;;
  flash) print 5 > "$STATE_FILE" ;;
  blink-slow) print 6 > "$STATE_FILE" ;;
  blink-fast) print 7 > "$STATE_FILE" ;;
  blink-off) print 19 > "$STATE_FILE" ;;
  *) exit 64 ;;
esac
EOF
chmod 755 "$TEMP_DIR/helper"

export MAGSAFE_TEST_HELPER_STATE="$TEMP_DIR/helper.state"
export MAGSAFE_DARK_HELPER="$TEMP_DIR/helper"
export MAGSAFE_DARK_SUDO=none
export MAGSAFE_DARK_APP_SUPPORT="$TEMP_DIR/support"
export MAGSAFE_DARK_LOG_DIR="$TEMP_DIR/logs"
export MAGSAFE_DARK_WORKING_MODE=blink-slow
export MAGSAFE_DARK_SUCCESS_MODE=flash
export MAGSAFE_DARK_ERROR_MODE=blink-fast
export MAGSAFE_DARK_SUCCESS_SECONDS=0
export MAGSAFE_DARK_ERROR_SECONDS=0
export MAGSAFE_DARK_SUCCESS_NOTIFICATIONS=0
export MAGSAFE_DARK_ERROR_NOTIFICATIONS=0

CLI=(zsh scripts/magsafe-dark)

SETTINGS="$(${CLI[@]} settings)"
[[ "$SETTINGS" == *"working_mode=blink-slow"* ]]
[[ "$SETTINGS" == *"success_mode=flash"* ]]
[[ "$SETTINGS" == *"error_mode=blink-fast"* ]]
[[ "$SETTINGS" == *"success_seconds=0"* ]]
[[ "$SETTINGS" == *"error_seconds=0"* ]]

${CLI[@]} system
${CLI[@]} run -- /usr/bin/true
[[ "$(cat "$MAGSAFE_TEST_HELPER_STATE")" == "0" ]]

set +e
${CLI[@]} run -- /usr/bin/false
CODE=$?
set -e
[[ "$CODE" == "1" ]]
[[ "$(cat "$MAGSAFE_TEST_HELPER_STATE")" == "0" ]]

${CLI[@]} for 60 off
END="$(${CLI[@]} timer-end)"
[[ "$END" == <-> ]]
(( END > $(date +%s) ))
${CLI[@]} cancel-timer
[[ "$(cat "$MAGSAFE_TEST_HELPER_STATE")" == "0" ]]

mkdir -p "$MAGSAFE_DARK_APP_SUPPORT/State"
print 'broken state' > "$MAGSAFE_DARK_APP_SUPPORT/State/temporary.state"
${CLI[@]} state >/dev/null
[[ ! -f "$MAGSAFE_DARK_APP_SUPPORT/State/temporary.state" ]]

print "CLI settings tests passed"
