# C and GIO with per-platform sources, not a cross-platform rewrite

The Linux port is written in C against GIO/GDBus, in its own source files next to the existing Objective-C/AppKit ones. The makefile selects a platform's sources by `uname`. Both platforms keep one shared command-line contract, and the tool stays a tiny native binary with no new toolchain. A single cross-platform rewrite (Rust, Go) was rejected as more work than a two-backend tool needs.

## Consequences

- Each platform carries its own copy of option parsing and output formatting. Changes to the command-line contract have to be made on both sides.
- On Linux the makefile pins `pkg-config` to the system GLib, so a Linuxbrew GLib earlier on `PATH` can't leak into the build.
