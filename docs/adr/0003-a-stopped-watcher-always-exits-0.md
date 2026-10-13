# A stopped Watcher always exits 0, however and whenever it is stopped

SIGINT and SIGTERM stop the Watcher with exit status 0 at every point in its life, not only while its main loop runs. A stop request can arrive before setup has finished, while it is shutting down, and more than once: Ctrl+C reaches a whole process group, then a supervisor asks again. Each case is a clean stop, so a supervisor or hook script can tell "stopped" (0) from "lost track of the mode" (2) by status alone. The same bug turned up twice, in the C Watcher and again in the Python example. Both used a stop handler that was put back to the default action during shutdown, so a late request killed the process with -15.

## Consequences

- Stop handlers are installed before anything that can block and stay installed until the process exits. Shutdown never restores the default action.
- One handler, in `stop.c`, serves every backend and does async-signal-safe work only: `_exit` before the loop is up, otherwise a hook the backend supplies. Linux's hook writes to a self-pipe its main loop watches; macOS needs none, because dispatch signal sources on the main queue stop its run loop.
- Anything that runs the Watcher keeps the rule: the Python example ignores stop requests once its Watcher has exited, because Python resets its own handlers on the way out.
- Before `main` reaches the stop setup, a signal still gets the default action; code can't close that.
- The rule is part of the contract in `interface-mode.h`, so every backend meets it, macOS included.
