"""Contract tests for interface-mode on macOS.

The Interface Mode can't be set without changing it for the user, so these
check only what doesn't depend on it: option handling, output shapes, the
exit status agreeing with the printed mode, and the Watcher's startup Report
and clean stop.

There is no macOS counterpart to the Linux test that stops the Watcher while
it connects: nothing outside the process can hold it before its first read
(Linux uses a session bus that never answers), so that path is unforced here.
"""

import signal
import unittest

from contract import ContractAssertions, UsageContract, keep_asking_to_stop

# The Query exit status for each mode.
STATUS = {"light": 0, "dark": 1}


class MacTestCase(ContractAssertions, unittest.TestCase):
    def current_mode(self):
        """The Interface Mode, as `--text` prints it."""
        result = self.run_tool("--text")
        self.assertIn(result.stdout, ("light\n", "dark\n"))
        return result.stdout.strip()


class QueryTest(MacTestCase):
    def test_exit_status_states_the_mode(self):
        result = self.run_tool()
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.returncode, STATUS[self.current_mode()])

    def test_text_prints_the_mode(self):
        for flag in ("-t", "--text", "-v", "--verbose"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertIn(result.stdout, ("light\n", "dark\n"))
                self.assertEqual(result.returncode, STATUS[result.stdout.strip()])
                self.assertEqual(result.stderr, "")

    def test_json_prints_one_report(self):
        mode = self.current_mode()
        for flag in ("--json", "-j"):
            with self.subTest(flag=flag):
                result = self.run_tool(flag)
                self.assertEqual(result.returncode, STATUS[mode])
                self.assertEqual(len(result.stdout.splitlines()), 1)
                self.assertJsonReport(result.stdout, mode)


class OptionsTest(UsageContract, MacTestCase):
    def test_repeating_a_format_is_fine(self):
        result = self.run_tool("-t", "--verbose")
        self.assertEqual(result.stdout, self.current_mode() + "\n")


class WatcherTest(MacTestCase):
    def test_reports_the_mode_on_startup(self):
        mode = self.current_mode()
        for flag, args in (("--watch", ()), ("-w", ()), ("--watch", ("--json",))):
            with self.subTest(flag=flag, args=args):
                watcher = self.watch(*args, flag=flag)
                self.assertJsonReport(watcher.next_line(), mode)
                self.assertIsNone(watcher.process.poll(), "the Watcher keeps running")

    def test_text_reports(self):
        watcher = self.watch("--text")
        self.assertEqual(watcher.next_line(), self.current_mode() + "\n")

    def test_stops_cleanly_on_sigint_and_sigterm(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum.name):
                watcher = self.watch()
                self.assertIsNotNone(watcher.next_line(), "a startup Report")
                watcher.process.send_signal(signum)
                self.assertEqual(watcher.process.wait(timeout=5), 0)
                self.assertEqual(watcher.process.stdout.read(), "")

    def test_further_stop_requests_are_still_clean(self):
        # e.g. Ctrl+C reaching the whole process group, then a parent script
        # or supervisor also asking the Watcher to stop.
        watcher = self.watch()
        self.assertIsNotNone(watcher.next_line(), "a startup Report")
        watcher.process.send_signal(signal.SIGINT)
        self.assertEqual(keep_asking_to_stop(watcher.process), 0)


if __name__ == "__main__":
    unittest.main()
