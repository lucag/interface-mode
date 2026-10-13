# C and GIO with per-platform backends, not a cross-platform rewrite

The Linux port is written in C against GIO/GDBus, next to the existing Objective-C/AppKit code, and the makefile picks a platform's sources by `uname`. A single cross-platform rewrite (Rust, Go) was rejected as more work than a two-backend tool needs. The command-line contract (options, Report formats, exit statuses, deduplicating Reports) lives once, in plain C, so the platforms can't drift apart. Each platform supplies only a small backend behind `interface-mode.h`: read the Interface Mode, and watch it.

## Consequences

- A contract change is made in one place. macOS adopts the shared contract by implementing `interface-mode.h` in Objective-C instead of carrying its own option parsing.
- On Linux the makefile pins `pkg-config` to the system GLib, so a Linuxbrew GLib earlier on `PATH` can't leak into the build.
