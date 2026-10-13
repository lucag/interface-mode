# interface-mode

Report, and watch for changes to, the desktop's **Interface Mode**: the desktop-wide choice between a Light and a Dark look. One command works the same on Linux and macOS:

- a **Query** answers through its exit status, so `if interface-mode; then …` means "light";
- the **Watcher** (`interface-mode --watch`) issues a **Report** on startup and another each time the Interface Mode changes.

A platform's "no preference" setting counts as **Light**.

## Usage

```
interface-mode [ -t | --text | -j | --json ] [ -w | --watch ]
```

| Option | Meaning |
|---|---|
| *(none)* | Query: answer through the exit status only, print nothing |
| `-t`, `--text` | also print `light` or `dark` (`-v`, `--verbose` is an alias) |
| `-j`, `--json` | also print one JSON object: `{"timestamp":…,"mode":"light\|dark"}` |
| `-w`, `--watch` | run the Watcher: one Report now and one per change, as JSON unless `--text` is given |
| `-h`, `--help` | show usage and exit 0 |

### Exit status

| Status | Query | Watcher |
|---|---|---|
| `0` | Light | stopped by SIGINT or SIGTERM |
| `1` | Dark | — |
| `2` | error: unknown or conflicting option, or the Interface Mode can't be determined | error, including the desktop portal going away mid-run (Linux) |

Errors go to stderr as `interface-mode: <message>`; stdout only ever carries the answer. A usage error also prints the usage to stderr.

### Reports

Each Report is one line, flushed as soon as it is written. As JSON (the default):

```json
{"timestamp":"2026-10-12T14:30:25.123Z","mode":"dark"}
```

The timestamp is UTC, ISO 8601, with milliseconds. With `--watch --text`, a Report is just `light` or `dark`.

The first Report states the mode at startup; it is not a change. After that, consecutive Reports always state different modes. Unrelated desktop settings and duplicate change signals produce no Report.

## Examples

```bash
# Branch on the mode
if interface-mode; then
    echo "light"
else
    case $? in
        1) echo "dark" ;;
        *) echo "couldn't tell" >&2 ;;
    esac
fi

# Capture it as a string
mode=$(interface-mode --text)

# Follow changes in shell
interface-mode --watch --text | while read -r mode; do
    echo "Interface Mode is now $mode"
done

# Follow changes as JSON
interface-mode --watch | jq -r .mode
```

Ready-to-adapt hook scripts are in [`example/`](example/):

- [`on-interface-mode-change.sh`](example/on-interface-mode-change.sh) and [`on-interface-mode-change.py`](example/on-interface-mode-change.py) run an `on_dark` or `on_light` hook at startup and on every change.
- [`interface-mode-hooks.service`](example/interface-mode-hooks.service) is a systemd user unit that runs a hook script for the whole graphical session and restarts it if the Watcher exits with an error. Install steps are in the file.

## Linux

The Interface Mode is read from the **XDG Desktop Portal**: `org.freedesktop.portal.Settings`, key `org.freedesktop.appearance` / `color-scheme`. That is the source desktop apps use, so the answer is right on GNOME, KDE and wlroots compositors such as niri. The Watcher follows the portal's `SettingChanged` signal.

You need `xdg-desktop-portal` running with a backend that provides the Settings interface, such as `xdg-desktop-portal-gnome` or `xdg-desktop-portal-kde`. There is no fallback ([ADR 0001](docs/adr/0001-linux-reads-the-desktop-portal-only.md)). With no session bus or no portal answering, both forms exit 2 rather than guess, and the Watcher exits 2 if the portal goes away while it runs. Restarting it is a supervisor's job, which the systemd unit above does.

### Build prerequisites

- `clang` and `make`
- GIO development headers: `libglib2.0-dev` on Debian and Ubuntu, `glib2-devel` on Fedora
- the system `pkg-config` at `/usr/bin/pkg-config`

### Linuxbrew and other GLibs on `PATH`

A GLib from Linuxbrew (or anywhere else on `PATH`) is a trap on Linux desktops. A `gsettings` built against a GLib without the dconf module falls back to a private keyfile and always answers `'default'`, so it can report Light on a Dark desktop. That's one reason this tool reads the portal instead. For the same reason the makefile asks the system `pkg-config` for GIO, with its search path pinned, so the binary always links the system GLib whatever is first on `PATH`. The test suite checks this.

## macOS

The Interface Mode is read from AppKit: an `NSApplication.effectiveAppearance` whose name contains "dark" is Dark, anything else is Light. The Watcher observes that appearance for changes. Building needs the Xcode Command Line Tools.

## Building and installing

```bash
make                                # build target/interface-mode for this platform
make install                        # install to /usr/local/bin (may need sudo)
make install PREFIX=$HOME/.local    # or anywhere else
make uninstall PREFIX=$HOME/.local  # remove it from the same PREFIX
make help                           # all targets
```

The makefile picks the platform's sources by `uname`, and everything is built in `target/`.

## Testing

```bash
make test         # on Linux
make test-linux   # from any host, in Docker
make hooks        # once per clone: commit messages must name an issue (#<n>)
```

CI runs both platforms' suites, with warnings as errors, on every push.

On Linux, `make test` runs [`tests/test_linux.py`](tests/test_linux.py) with the system `python3`. It drives the built binary as a black box against a fake desktop portal on a private session bus, so your real desktop settings are never read or changed. It needs:

- `python3-dbusmock`
- `dbus` (for `dbus-daemon`)

`make test-linux` builds [`tests/Dockerfile`](tests/Dockerfile), a Debian image with every prerequisite, and runs `make test` inside it on a copy of the repo. It needs Docker running.

On macOS, `make test` runs [`tests/test_macos.py`](tests/test_macos.py) with the system `python3`. The Interface Mode can't be set without changing it for you, so it checks only the contract around it: options, output shapes, the exit status agreeing with `--text`, and the Watcher's startup Report and clean stop. Both suites share the platform-neutral checks in [`tests/contract.py`](tests/contract.py).

To check the macOS Watcher against real changes, run [`tests/live_macos.sh`](tests/live_macos.sh) at your Mac. It switches your Mac to the other Interface Mode and back (restoring yours however it ends), expects a Report for each switch, and expects exit 0 on SIGTERM.

## Breaking changes

The unified command changes the old macOS contract on purpose, all at once, so scripts need updating only once:

| Before | Now |
|---|---|
| Dark exits 255 (the old README said -1) | Dark exits **1** |
| A bad option exited 1, like a real answer | Errors exit **2** |
| `-v` prints `Light` / `Dark` | Output is lowercase: `light` / `dark` |
| `interface-mode-server` | `interface-mode --watch` |
| `interface-mode-server --simple` | `interface-mode --watch --text` |
| JSON Reports had a `change` field, including a made-up transition at startup | Reports carry `timestamp` and `mode` only |

`-v` / `--verbose` keeps working, as an alias for `--text`.

## Project structure

```
interface-mode/
├── cli.c                     # the shared command-line contract: options, Reports, exit statuses
├── interface-mode.h          # the seam between the contract and a platform backend
├── stop.c, stop.h            # SIGINT/SIGTERM handling every backend's Watcher shares
├── portal.c                  # Linux backend: the XDG Desktop Portal over GIO/GDBus
├── macos.m                   # macOS backend: AppKit's effective appearance
├── makefile                  # build, install and test, by platform
├── example/                  # hook scripts and a systemd user unit
├── tests/
│   ├── contract.py           # checks every platform shares
│   ├── test_linux.py         # black-box tests against a fake portal
│   ├── test_macos.py         # contract-only tests on macOS
│   ├── live_macos.sh         # live check against real appearance changes, run by hand
│   └── Dockerfile            # Linux test environment for make test-linux
├── docs/
│   ├── adr/                  # architecture decision records
│   └── agents/               # configuration for coding agents
├── CONTEXT.md                # glossary: Interface Mode, Query, Watcher, Report
├── CODING_STANDARDS.md       # rules for code, tests and commits
├── AGENTS.md, CLAUDE.md      # instructions for coding agents
└── target/                   # build output (created by make)
```

## License

This project is open source. Feel free to use and modify as needed.
