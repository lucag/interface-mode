#!/usr/bin/env python3
"""Run a hook for the desktop's Interface Mode now, and every time it changes.

Python version of on-interface-mode-change.sh: put your own code in on_dark
and on_light. It reads the Watcher's JSON Reports, one per line.

interface-mode exits 2 if it loses track of the mode (for instance when the
desktop portal goes away); so does this script, which lets a supervisor such
as the systemd unit next to it restart the pair.
"""

import json
import os
import subprocess

# Where interface-mode lives, if it isn't on PATH.
INTERFACE_MODE = os.environ.get("INTERFACE_MODE", "interface-mode")


def on_dark():
    print("Interface Mode is now dark", flush=True)
    # ---- your dark-mode code here ----


def on_light():
    print("Interface Mode is now light", flush=True)
    # ---- your light-mode code here ----


HOOKS = {"dark": on_dark, "light": on_light}


def main():
    with subprocess.Popen(
        [INTERFACE_MODE, "--watch"], stdout=subprocess.PIPE, text=True
    ) as watcher:
        try:
            # The first Report is the mode at startup, so the right hook runs
            # straight away; after that each Report is a change.
            for line in watcher.stdout:
                HOOKS[json.loads(line)["mode"]]()
        except KeyboardInterrupt:
            pass  # Ctrl+C reaches the Watcher too, which then exits 0
    return watcher.returncode


if __name__ == "__main__":
    raise SystemExit(main())
