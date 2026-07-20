#!/bin/zsh
set -euo pipefail

CLIENT="/usr/local/libexec/magsafe-led-client"
CLI="/usr/local/bin/magsafe-dark"
LABEL="su.xyz.MagSafeDark.daemon"

[[ -x "$CLIENT" ]] || { print -u2 "Daemon client is not installed"; exit 66; }
[[ -x "$CLI" ]] || { print -u2 "magsafe-dark CLI is not installed"; exit 66; }
[[ ! -e /usr/local/libexec/magsafe-led-helper ]] || { print -u2 "Legacy helper is still installed"; exit 1; }
[[ ! -e /etc/sudoers.d/magsafe-dark ]] || { print -u2 "Legacy sudoers rule is still installed"; exit 1; }

sudo launchctl print "system/$LABEL" >/dev/null
[[ -S /var/run/magsafe-dark.sock ]] || { print -u2 "Daemon socket is missing"; exit 69; }
[[ "$($CLIENT ping)" == pong ]]
[[ "$($CLIENT probe)" == supported ]]

ORIGINAL="$($CLIENT status)"
case "$ORIGINAL" in 0|1|3|4|5|6|7|19) ;; *) print -u2 "Unexpected ACLC value: $ORIGINAL"; exit 1;; esac

restore() {
  case "$ORIGINAL" in
    0) "$CLI" system >/dev/null 2>&1 || true ;;
    1) "$CLI" off >/dev/null 2>&1 || true ;;
    3) "$CLI" green >/dev/null 2>&1 || true ;;
    4) "$CLI" orange >/dev/null 2>&1 || true ;;
    5) "$CLI" flash >/dev/null 2>&1 || true ;;
    6) "$CLI" blink-slow >/dev/null 2>&1 || true ;;
    7) "$CLI" blink-fast >/dev/null 2>&1 || true ;;
    19) "$CLI" blink-off >/dev/null 2>&1 || true ;;
  esac
}
trap restore EXIT INT TERM HUP

"$CLI" off
[[ "$($CLIENT status)" == 1 ]]
"$CLI" green
[[ "$($CLIENT status)" == 3 ]]
"$CLI" for 2 orange
[[ "$($CLIENT status)" == 4 ]]
sleep 3
[[ "$($CLIENT status)" == 3 ]]

restore
trap - EXIT INT TERM HUP
print "Installed LaunchDaemon integration tests passed"
