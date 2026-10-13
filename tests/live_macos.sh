#!/usr/bin/env bash
#
# Live check of the macOS Watcher against real appearance changes, which the
# automated suite can't make without changing the desktop for the user.
#
# It runs `interface-mode --watch --text`, switches macOS to the other mode
# and back with System Events, and expects the Reports original, other,
# original; then it stops the Watcher with SIGTERM and expects exit 0. The
# original mode is restored however the script ends.
#
# Run it yourself, on a Mac you are sitting at:
#
#   make && tests/live_macos.sh
#
# macOS may ask once to let your terminal control System Events.

set -euo pipefail

INTERFACE_MODE=${INTERFACE_MODE:-$(dirname "$0")/../target/interface-mode}
TIMEOUT=10

original=$("$INTERFACE_MODE" --text) || true
case $original in
light) other=dark ;;
dark) other=light ;;
*) echo "FAIL: can't read the Interface Mode (got '$original')" >&2; exit 1 ;;
esac

set_mode() {
  local dark=false
  [ "$1" = dark ] && dark=true
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" >/dev/null
}

reports=$(mktemp)
watcher=
restore() {
  [ -n "$watcher" ] && kill -KILL "$watcher" 2>/dev/null || true
  [ "$("$INTERFACE_MODE" --text)" = "$original" ] || set_mode "$original"
  rm -f "$reports"
}
trap restore EXIT

# Wait until the Watcher has issued `count` Reports.
wait_for_reports() {
  local count=$1 deadline=$((SECONDS + TIMEOUT))
  while [ "$(wc -l <"$reports")" -lt "$count" ]; do
    if [ $SECONDS -ge $deadline ]; then
      echo "FAIL: no Report $count within ${TIMEOUT}s; got:" >&2
      cat "$reports" >&2
      exit 1
    fi
    sleep 0.2
  done
}

echo "Interface Mode is $original; switching to $other and back."
"$INTERFACE_MODE" --watch --text >"$reports" &
watcher=$!
wait_for_reports 1
set_mode "$other"
wait_for_reports 2
set_mode "$original"
wait_for_reports 3

kill -TERM "$watcher"
status=0
wait "$watcher" || status=$?
watcher=

expected=$(printf '%s\n' "$original" "$other" "$original")
if [ "$(cat "$reports")" != "$expected" ]; then
  echo "FAIL: expected Reports $original, $other, $original; got:" >&2
  cat "$reports" >&2
  exit 1
fi
if [ "$status" -ne 0 ]; then
  echo "FAIL: the Watcher exited $status on SIGTERM, not 0" >&2
  exit 1
fi
echo "OK: Reports $original, $other, $original; exit 0 on SIGTERM."
