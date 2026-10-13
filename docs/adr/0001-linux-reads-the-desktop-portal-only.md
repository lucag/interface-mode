# Linux reads Interface Mode from the desktop portal only

On Linux the tool reads Interface Mode from the XDG Desktop Portal (`org.freedesktop.appearance` / `color-scheme`) and watches its `SettingChanged` signal. There is deliberately no fallback to GNOME `gsettings`. The portal works on any desktop with a portal backend, including GNOME, KDE and wlroots compositors such as niri, while `gsettings` is tied to GNOME's schema. `gsettings` also fails silently in practice: a `gsettings` built against a GLib without the dconf module, such as the Linuxbrew one, falls back to a private keyfile backend and always answers `'default'`. That turned a dark desktop into a "light" answer while the portal reported correctly.

## Consequences

- With no reachable portal (no session bus, no backend), a Query or the Watcher exits with status 2 instead of guessing.
- On Linux the Watcher exits with status 2 if the portal goes away mid-run; restarting it is the supervisor's job.
