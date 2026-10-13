"""Black-box tests for interface-mode on Linux.

Each test class runs on a private session bus with a fake XDG Desktop Portal,
so the real desktop is never read or changed.
"""

import datetime
import json
import os
import re
import subprocess
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

NO_PREFERENCE, PREFER_DARK, PREFER_LIGHT = 0, 1, 2


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
            "if (args[0], args[1]) == ('org.freedesktop.appearance', 'color-scheme') "
            "else None" % (scheme, level),
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

    def run_tool(self, *args, env=None):
        return subprocess.run(
            [BINARY, *args], capture_output=True, text=True, timeout=10, env=env
        )


class QueryTest(PortalTestCase):
    def test_dark_exits_1(self):
        self.start_portal(PREFER_DARK)
        self.assertEqual(self.run_tool().returncode, 1)

    def test_light_exits_0(self):
        self.start_portal(PREFER_LIGHT)
        self.assertEqual(self.run_tool().returncode, 0)

    def test_no_preference_counts_as_light(self):
        self.start_portal(NO_PREFERENCE)
        self.assertEqual(self.run_tool().returncode, 0)

    def test_reads_portals_without_read_one(self):
        self.start_portal(PREFER_DARK, read_one=False)
        self.assertEqual(self.run_tool().returncode, 1)

    def test_no_portal_is_an_error(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("interface-mode:", result.stderr)

    def test_no_session_bus_is_an_error(self):
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent")
        result = self.run_tool(env=env)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("interface-mode:", result.stderr)


class QueryFormatTest(PortalTestCase):
    def test_text_prints_the_mode(self):
        self.start_portal(PREFER_DARK)
        result = self.run_tool("--text")
        self.assertEqual((result.returncode, result.stdout), (1, "dark\n"))

    def test_text_prints_light(self):
        self.start_portal(PREFER_LIGHT)
        result = self.run_tool("--text")
        self.assertEqual((result.returncode, result.stdout), (0, "light\n"))

    def test_text_aliases(self):
        self.start_portal(PREFER_DARK)
        for flag in ("-t", "-v", "--verbose"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual((result.returncode, result.stdout), (1, "dark\n"))

    def test_json_prints_one_report(self):
        self.start_portal(PREFER_DARK)
        for flag in ("--json", "-j"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual(result.returncode, 1)
                self.assertTrue(result.stdout.endswith("\n"))
                self.assertEqual(len(result.stdout.splitlines()), 1)
                self.assertJsonReport(result.stdout, "dark")

    def test_no_output_when_the_mode_is_unknown(self):
        for flag in ("--text", "--json"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual((result.returncode, result.stdout), (2, ""))


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
        result = self.run_tool(*args)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("Usage:", result.stderr)

    def test_unknown_option_is_an_error(self):
        self.start_portal(PREFER_LIGHT)
        self.assertUsageError("--bogus")

    def test_text_and_json_together_is_an_error(self):
        self.start_portal(PREFER_LIGHT)
        self.assertUsageError("--text", "--json")
        self.assertUsageError("-j", "-v")

    def test_repeating_a_format_is_fine(self):
        self.start_portal(PREFER_LIGHT)
        result = self.run_tool("-t", "--verbose")
        self.assertEqual((result.returncode, result.stdout), (0, "light\n"))


if __name__ == "__main__":
    unittest.main()
