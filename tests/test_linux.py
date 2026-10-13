"""Black-box tests for interface-mode on Linux.

Each test class runs on a private session bus with a fake XDG Desktop Portal,
so the real desktop is never read or changed.
"""

import os
import re
import selectors
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

import dbus
import dbusmock

from contract import BINARY, ContractAssertions, UsageContract, keep_asking_to_stop

EXAMPLE = os.path.join(
    os.path.dirname(__file__), "..", "example", "on-interface-mode-change.py"
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


class PortalTestCase(ContractAssertions, dbusmock.DBusTestCase):
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


class OptionsTest(UsageContract, PortalTestCase):
    def test_repeating_a_format_is_fine(self):
        self.start_portal(PREFER_LIGHT)
        result = self.run_tool("-t", "--verbose")
        self.assertEqual((result.returncode, result.stdout), (0, "light\n"))


class WatcherTest(PortalTestCase):
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
        watcher.process.send_signal(signal.SIGINT)
        self.assertEqual(keep_asking_to_stop(watcher.process), 0)

    def test_stops_cleanly_while_connecting(self):
        # A session bus that takes the connection but never answers holds the
        # Watcher in its connect, so the stop request lands there every time.
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "bus")
            env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=" + path)
            with socket.socket(socket.AF_UNIX) as bus:
                bus.bind(path)
                bus.listen()
                bus.settimeout(5)
                for signum in (signal.SIGINT, signal.SIGTERM):
                    with self.subTest(signal=signum.name):
                        watcher = self.watch(env=env)
                        connection, _ = bus.accept()
                        with connection:
                            watcher.process.send_signal(signum)
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


class ExampleTest(PortalTestCase):
    """The Python hook example, run against the Watcher under test."""

    def start_example(self):
        """Start the example in its own process group; wait for its first hook."""
        example = subprocess.Popen(
            [sys.executable, EXAMPLE],
            stdout=subprocess.PIPE,
            text=True,
            env=dict(os.environ, INTERFACE_MODE=BINARY),
            start_new_session=True,
        )
        self.addCleanup(self.kill_group, example)
        selector = selectors.DefaultSelector()
        selector.register(example.stdout, selectors.EVENT_READ)
        self.assertTrue(selector.select(5), "the example runs a hook")
        self.assertEqual(example.stdout.readline(), "Interface Mode is now light\n")
        return example

    def kill_group(self, example):
        try:
            os.killpg(example.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        example.wait()
        example.stdout.close()

    def assertStoppedWithItsWatcher(self, example, status):
        self.assertEqual(status, 0)
        # The Watcher was its only child: nothing of the group is left.
        with self.assertRaises(ProcessLookupError):
            os.killpg(example.pid, 0)

    def test_stops_its_watcher_when_only_it_is_asked(self):
        self.start_portal(PREFER_LIGHT)
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum.name):
                example = self.start_example()
                example.send_signal(signum)
                self.assertStoppedWithItsWatcher(example, example.wait(timeout=5))

    def test_stops_on_ctrl_c_to_the_process_group(self):
        self.start_portal(PREFER_LIGHT)
        example = self.start_example()
        os.killpg(example.pid, signal.SIGINT)
        self.assertStoppedWithItsWatcher(example, example.wait(timeout=5))

    def test_further_stop_requests_are_still_clean(self):
        # e.g. Ctrl+C reaching the whole process group, then a supervisor.
        self.start_portal(PREFER_LIGHT)
        example = self.start_example()
        os.killpg(example.pid, signal.SIGINT)
        self.assertStoppedWithItsWatcher(example, keep_asking_to_stop(example))


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
