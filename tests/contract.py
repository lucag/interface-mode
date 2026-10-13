"""The command-line contract every platform's interface-mode keeps.

Helpers and tests shared by test_linux.py and test_macos.py. Everything here
drives the binary as a black box and needs only the standard library.
"""

import datetime
import json
import os
import re
import selectors
import signal
import subprocess
import time

BINARY = os.environ.get(
    "INTERFACE_MODE",
    os.path.join(os.path.dirname(__file__), "..", "target", "interface-mode"),
)

TIMESTAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z")


def keep_asking_to_stop(process, timeout=5):
    """Send SIGTERM to `process` until it has exited, then return its status.

    Requests land all through its shutdown, right up to the end. Only poll()
    reaps it, so its pid can't be reused while it is still being signalled.
    """
    deadline = time.monotonic() + timeout
    while process.poll() is None:
        if time.monotonic() > deadline:
            raise AssertionError("still running after %ss of stop requests" % timeout)
        os.kill(process.pid, signal.SIGTERM)
    return process.returncode


class Watcher:
    """A running `interface-mode --watch`, read one Report at a time."""

    def __init__(self, *args, flag="--watch", env=None):
        self.process = subprocess.Popen(
            [BINARY, flag, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
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


class ContractAssertions:
    """Assertions on the binary's output, mixed into a TestCase."""

    def run_tool(self, *args, env=None):
        return subprocess.run(
            [BINARY, *args], capture_output=True, text=True, timeout=10, env=env
        )

    def watch(self, *args, flag="--watch", env=None):
        watcher = Watcher(*args, flag=flag, env=env)
        self.addCleanup(watcher.stop)
        return watcher

    def assertJsonReport(self, line, mode):
        """`line` is one JSON object stating `mode`, stamped about now in UTC."""
        report = json.loads(line)
        self.assertEqual(sorted(report), ["mode", "timestamp"])
        self.assertEqual(report["mode"], mode)
        self.assertRegex(report["timestamp"], TIMESTAMP)
        # Python before 3.11 doesn't read a "Z" suffix.
        stamped = datetime.datetime.fromisoformat(
            report["timestamp"].replace("Z", "+00:00")
        )
        now = datetime.datetime.now(datetime.timezone.utc)
        self.assertLess(abs((now - stamped).total_seconds()), 60)

    def assertError(self, result, message="interface-mode:"):
        """`result` failed with exit 2, nothing on stdout, `message` on stderr."""
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn(message, result.stderr)

    def assertUsageError(self, *args):
        self.assertError(self.run_tool(*args), "Usage:")


class UsageContract(ContractAssertions):
    """Option handling that answers before the Interface Mode is read."""

    def test_help_describes_the_contract(self):
        for flag in ("-h", "--help"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stderr, "")
                for word in ("--text", "--json", "--watch", "0", "1", "2"):
                    self.assertIn(word, result.stdout)

    def test_unknown_option_is_an_error(self):
        self.assertUsageError("--bogus")
        self.assertUsageError("-s")

    def test_text_and_json_together_is_an_error(self):
        self.assertUsageError("--text", "--json")
        self.assertUsageError("-j", "-v")
        self.assertUsageError("--watch", "--text", "--json")
