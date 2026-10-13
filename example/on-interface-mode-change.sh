#!/usr/bin/env bash
#
# Run a hook for the desktop's Interface Mode now, and again every time it
# changes. Put your own commands in on_dark and on_light.
#
# interface-mode exits 2 if it loses track of the mode (for instance when the
# desktop portal goes away); so does this script, which lets a supervisor such
# as the systemd unit next to it restart the pair.

set -euo pipefail

# Where interface-mode lives, if it isn't on PATH.
INTERFACE_MODE=${INTERFACE_MODE:-interface-mode}

on_dark() {
  echo "Interface Mode is now dark"
  # ---- your dark-mode commands here ----
  # e.g. swww img ~/wallpapers/dark.png
}

on_light() {
  echo "Interface Mode is now light"
  # ---- your light-mode commands here ----
  # e.g. swww img ~/wallpapers/light.png
}

# The first Report is the mode at startup, so the right hook runs straight
# away; after that each Report is a change.
"$INTERFACE_MODE" --watch --text | while read -r mode; do
  case $mode in
  dark) on_dark ;;
  light) on_light ;;
  esac
done
