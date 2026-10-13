"""Black-box tests for interface-mode on Linux.

Each test class runs on a private session bus with a fake XDG Desktop Portal,
so the real desktop is never read or changed.
"""

import datetime
import json
import os
import re
import selectors
import signal
import subprocess
import time
import unittest

import dbus
import dbusmock

BINARY = os.environ.get(
    "INTERFACE_MODE",
    os.path.join(os.path.dirname(__file__), "..", "target", "interface-mode"),
)

PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SETTINGS = "org.freedesktop.portal.Settings"
APPEARANCE = "org.freedesktop.appearance"
COLOR_SCHEME = "color-scheme"

NO_PREFERENCE, PREFER_DARK, PREFER_LIGHT = 0, 1, 2

# Each portal color-scheme, with the mode and Query exit status it stands for.
SCHEMES = [
    (PREFER_DARK, "dark", 1),
    (PREFER_LIGHT, "light", 0),
    (NO_PREFERENCE, "light", 0),
]

TIMESTAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z")


class PortalTestCase(dbusmock.DBusTestCase):
    @classmethod
    def setUpClass(cls):
        cls.start_session_bus()

    def start_portal(self, scheme, read_one=True):
        """Start a fake portal whose color-scheme is `scheme`."""
        self.portal = self.spawn_server(PORTAL_NAME, PORTAL_PATH, SETTINGS)
        self.addCleanup(self.stop_portal)
        self.mock = dbus.Interface(
            self.get_dbus().get_object(PORTAL_NAME, PORTAL_PATH), dbusmock.MOCK_IFACE
        )
        self.set_scheme(scheme, read_one)

    def stop_portal(self):
        if self.portal.poll() is None:
            self.portal.terminate()
            self.portal.wait()

    def set_scheme(self, scheme, read_one=True):
        """Make the fake portal answer `scheme` for color-scheme.

        Portals before version 2 only have Settings.Read, which wraps the
        value in one more variant; pass read_one=False to fake one of those.
        """
        method, level = ("ReadOne", 1) if read_one else ("Read", 2)
        self.mock.AddMethod(
            SETTINGS,
            method,
            "ss",
            "v",
            "ret = dbus.UInt32(%d, variant_level=%d) "
            "if (args[0], args[1]) == (%r, %r) "
            "else None" % (scheme, level, APPEARANCE, COLOR_SCHEME),
        )

    def assertJsonReport(self, line, mode):
        """`line` is one JSON object stating `mode`, stamped about now in UTC."""
        report = json.loads(line)
        self.assertEqual(sorted(report), ["mode", "timestamp"])
        self.assertEqual(report["mode"], mode)
        self.assertRegex(report["timestamp"], TIMESTAMP)
        stamped = datetime.datetime.fromisoformat(report["timestamp"])
        now = datetime.datetime.now(datetime.timezone.utc)
        self.assertLess(abs((now - stamped).total_seconds()), 60)

    def emit_setting(self, namespace, key, value):
        self.mock.EmitSignal(
            SETTINGS, "SettingChanged", "ssv", [namespace, key, value]
        )

    def change_scheme(self, scheme):
        """Switch the fake portal to `scheme` and announce it as a portal does."""
        self.set_scheme(scheme)
        self.emit_setting(
            APPEARANCE, COLOR_SCHEME, dbus.UInt32(scheme, variant_level=1)
        )

    def assertError(self, result, message="interface-mode:"):
        """`result` failed with exit 2, nothing on stdout, `message` on stderr."""
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn(message, result.stderr)

    def run_tool(self, *args, env=None):
        return subprocess.run(
            [BINARY, *args], capture_output=True, text=True, timeout=10, env=env
        )


class QueryTest(PortalTestCase):
    def test_exit_status_states_the_mode(self):
        # No preference counts as Light.
        for scheme, mode, status in SCHEMES:
            with self.subTest(mode=mode, scheme=scheme):
                self.start_portal(scheme)
                result = self.run_tool()
                self.assertEqual((result.returncode, result.stdout), (status, ""))
                self.stop_portal()

    def test_reads_portals_without_read_one(self):
        for scheme, mode, status in SCHEMES:
            with self.subTest(mode=mode, scheme=scheme):
                self.start_portal(scheme, read_one=False)
                self.assertEqual(self.run_tool().returncode, status)
                self.stop_portal()

    def test_no_portal_is_an_error(self):
        self.assertError(self.run_tool())

    def test_no_session_bus_is_an_error(self):
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent")
        self.assertError(self.run_tool(env=env))


class QueryFormatTest(PortalTestCase):
    def test_text_prints_the_mode(self):
        for scheme, mode, status in SCHEMES:
            with self.subTest(mode=mode, scheme=scheme):
                self.start_portal(scheme)
                result = self.run_tool("--text")
                self.assertEqual((result.returncode, result.stdout), (status, mode + "\n"))
                self.stop_portal()

    def test_text_aliases(self):
        self.start_portal(PREFER_DARK)
        for flag in ("-t", "-v", "--verbose"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual((result.returncode, result.stdout), (1, "dark\n"))

    def test_json_prints_one_report(self):
        for scheme, mode, status in SCHEMES:
            self.start_portal(scheme)
            for flag in ("--json", "-j"):
                with self.subTest(mode=mode, scheme=scheme, flag=flag):
                    result = self.run_tool(flag)
                    self.assertEqual(result.returncode, status)
                    self.assertTrue(result.stdout.endswith("\n"))
                    self.assertEqual(len(result.stdout.splitlines()), 1)
                    self.assertJsonReport(result.stdout, mode)
            self.stop_portal()

    def test_no_output_when_the_mode_is_unknown(self):
        for flag in ("--text", "--json"):
            with self.subTest(flag=flag):
                self.assertError(self.run_tool(flag))


class OptionsTest(PortalTestCase):
    def test_help_describes_the_contract(self):
        for flag in ("-h", "--help"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, "")
                for word in ("--text", "--json", "--watch", "0", "1", "2"):
                    self.assertIn(word, result.stdout)

    def assertUsageError(self, *args):
        self.assertError(self.run_tool(*args), "Usage:")

    def test_unknown_option_is_an_error(self):
        self.start_portal(PREFER_LIGHT)
        self.assertUsageError("--bogus")

    def test_text_and_json_together_is_an_error(self):
        self.start_portal(PREFER_LIGHT)
        self.assertUsageError("--text", "--json")
        self.assertUsageError("-j", "-v")
        self.assertUsageError("--watch", "--text", "--json")

    def test_repeating_a_format_is_fine(self):
        self.start_portal(PREFER_LIGHT)
        result = self.run_tool("-t", "--verbose")
        self.assertEqual((result.returncode, result.stdout), (0, "light\n"))


class Watcher:
    """A running `interface-mode --watch`, read one Report at a time."""

    def __init__(self, *args, flag="--watch"):
        self.process = subprocess.Popen(
            [BINARY, flag, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)

    def next_line(self, timeout=5):
        """The next line, or None if nothing arrives within `timeout`."""
        if not self.selector.select(timeout):
            return None
        return self.process.stdout.readline()

    def stop(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()
        self.process.stdout.close()
        self.process.stderr.close()


class WatcherTest(PortalTestCase):
    def watch(self, *args, flag="--watch"):
        watcher = Watcher(*args, flag=flag)
        self.addCleanup(watcher.stop)
        return watcher

    def test_reports_the_mode_on_startup(self):
        self.start_portal(PREFER_DARK)
        watcher = self.watch()
        self.assertJsonReport(watcher.next_line(), "dark")
        self.assertIsNone(watcher.process.poll(), "the Watcher keeps running")

    def test_short_flag_and_explicit_json(self):
        self.start_portal(PREFER_LIGHT)
        for flag, args in (("-w", ()), ("--watch", ("--json",)), ("-w", ("-j",))):
            with self.subTest(flag=flag, args=args):
                watcher = self.watch(*args, flag=flag)
                self.assertJsonReport(watcher.next_line(), "light")
                self.change_scheme(PREFER_DARK)
                self.assertJsonReport(watcher.next_line(), "dark")
                self.change_scheme(PREFER_LIGHT)
                self.assertJsonReport(watcher.next_line(), "light")

    def test_reports_each_change(self):
        self.start_portal(PREFER_DARK)
        watcher = self.watch()
        self.assertJsonReport(watcher.next_line(), "dark")
        self.change_scheme(PREFER_LIGHT)
        self.assertJsonReport(watcher.next_line(), "light")
        self.change_scheme(PREFER_DARK)
        self.assertJsonReport(watcher.next_line(), "dark")

    def test_ignores_everything_but_a_new_mode(self):
        self.start_portal(PREFER_DARK)
        watcher = self.watch()
        self.assertJsonReport(watcher.next_line(), "dark")

        self.change_scheme(PREFER_DARK)  # duplicate signal, same mode
        self.emit_setting(
            APPEARANCE,
            "accent-color",
            dbus.Struct((0.1, 0.2, 0.3), signature="ddd", variant_level=1),
        )
        self.emit_setting(
            "org.gnome.desktop.interface",
            COLOR_SCHEME,
            dbus.String("prefer-light", variant_level=1),
        )
        self.change_scheme(PREFER_LIGHT)

        self.assertJsonReport(watcher.next_line(), "light")
        self.assertIsNone(watcher.next_line(timeout=0.5))

    def test_text_reports(self):
        self.start_portal(PREFER_LIGHT)
        watcher = self.watch("--text")
        self.assertEqual(watcher.next_line(), "light\n")
        self.change_scheme(PREFER_DARK)
        self.assertEqual(watcher.next_line(), "dark\n")

    def test_stops_cleanly_on_sigint_and_sigterm(self):
        self.start_portal(PREFER_LIGHT)
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum.name):
                watcher = self.watch()
                self.assertJsonReport(watcher.next_line(), "light")
                watcher.process.send_signal(signum)
                self.assertEqual(watcher.process.wait(timeout=5), 0)

    def test_further_stop_requests_are_still_clean(self):
        # e.g. Ctrl+C reaching the whole process group, then a parent script
        # or supervisor also asking the Watcher to stop.
        self.start_portal(PREFER_LIGHT)
        watcher = self.watch()
        self.assertJsonReport(watcher.next_line(), "light")
        pid = watcher.process.pid
        os.kill(pid, signal.SIGINT)
        # Keep asking until it has exited, so requests land all through its
        # shutdown, right up to the end. WNOWAIT leaves it to be reaped below,
        # so its pid can't be reused while it is still being signalled.
        deadline = time.monotonic() + 5
        while os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None:
            self.assertLess(time.monotonic(), deadline, "the Watcher stops")
            os.kill(pid, signal.SIGTERM)
        self.assertEqual(watcher.process.wait(timeout=5), 0)

    def test_exits_when_the_portal_goes_away(self):
        self.start_portal(PREFER_DARK)
        watcher = self.watch()
        self.assertJsonReport(watcher.next_line(), "dark")
        self.stop_portal()
        self.assertEqual(watcher.process.wait(timeout=5), 2)
        self.assertIn("interface-mode:", watcher.process.stderr.read())

    def test_no_portal_at_startup_is_an_error(self):
        watcher = self.watch()
        self.assertEqual(watcher.process.wait(timeout=5), 2)
        self.assertEqual(watcher.process.stdout.read(), "")


class BuildTest(unittest.TestCase):
    def test_links_the_system_glib(self):
        # A GLib from Linuxbrew (or anywhere else on PATH) must not leak in.
        libraries = subprocess.run(
            ["ldd", BINARY], capture_output=True, text=True, check=True
        ).stdout
        glib = re.findall(r"lib(?:gio|gobject|glib)-2\.0\.so\S* => (\S+)", libraries)
        self.assertEqual(len(glib), 3, libraries)
        for path in glib:
            self.assertRegex(path, r"^(/usr)?/lib", path)


if __name__ == "__main__":
    unittest.main()
