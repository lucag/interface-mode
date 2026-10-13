# Interface Mode

Command-line tools that report, and watch for changes to, the desktop's light/dark setting on macOS and Linux.

## Language

**Interface Mode**:
The desktop-wide choice between a light and a dark look, as set by the user or the system. Always exactly one of **Light** or **Dark**; a platform's "no preference" counts as **Light**.
_Avoid_: Theme, Appearance, Color Scheme (these are platform names for where it is read from, not the concept itself)

**Query**:
A one-shot check of the current Interface Mode, answered through the exit status.
_Avoid_: Check, Probe

**Watcher**:
The long-running form of the tool, which issues a Report on startup and another each time the Interface Mode changes.
_Avoid_: Server, Listener, Monitor

**Report**:
A single line from the Watcher stating what the Interface Mode is now. Consecutive Reports always state different modes.
_Avoid_: Event, Change, Notification
