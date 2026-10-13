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
import signal
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
    watcher = None
    stopping = False

    def stop(signum, frame):
        # The signal may have reached only this script, so pass it on. The
        # Watcher exits 0 on SIGTERM, however often asked, and the loop
        # below ends with its output; a hook already running finishes first.
        # Pass it on once: Python runs a handler between any two bytecodes,
        # so under a burst of signals a handler that does more than return
        # nests inside itself until it hits the recursion limit.
        nonlocal stopping
        if stopping:
            return
        stopping = True
        if watcher is not None:
            watcher.terminate()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    watcher = subprocess.Popen(
        [INTERFACE_MODE, "--watch"], stdout=subprocess.PIPE, text=True
    )
    if stopping:
        # Asked to stop while the Watcher was starting.
        watcher.terminate()
    with watcher:
        # The first Report is the mode at startup, so the right hook runs
        # straight away; after that each Report is a change.
        for line in watcher.stdout:
            HOOKS[json.loads(line)["mode"]]()
    # Nothing is left to stop. Python puts its own handlers back to the
    # default on the way out, which a late request would die by.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    # A Watcher stopped this early may not have caught the signal yet.
    return 0 if stopping else watcher.returncode


if __name__ == "__main__":
    raise SystemExit(main())
