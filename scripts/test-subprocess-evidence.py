#!/usr/bin/env python3
"""Regress failed process observation and the validator's early failure boundary."""

import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "skills/r-performance-workflow/scripts/subprocess-evidence.py"
FUNCTIONS = runpy.run_path(str(HELPER))


class ProcessInspectionTests(unittest.TestCase):
    def state(self, status, stdout, stderr=""):
        result = subprocess.CompletedProcess(["ps"], status, stdout, stderr)
        with patch("subprocess.run", return_value=result):
            return FUNCTIONS["process_state"](123)

    def test_live_and_zombie_states(self):
        self.assertEqual(self.state(0, " S+\n"), "S+")
        self.assertEqual(self.state(0, " Z\n"), "Z")

    def test_no_matching_process(self):
        self.assertEqual(self.state(1, ""), "")

    def test_failed_observation_is_not_a_missing_process(self):
        for status, stdout, stderr in ((1, "", "permission denied"),
                                       (2, "", ""), (1, "S", ""), (0, "", "")):
            with self.subTest(status=status, stdout=stdout, stderr=stderr):
                with self.assertRaisesRegex(ValueError, "ps failed"):
                    self.state(status, stdout, stderr)

    def test_preflight_requires_the_current_process(self):
        for effect in (PermissionError("ps denied"),
                       subprocess.TimeoutExpired("ps", 5)):
            with self.subTest(effect=type(effect).__name__):
                with patch("subprocess.run", side_effect=effect):
                    with self.assertRaisesRegex(ValueError, "requires process inspection"):
                        FUNCTIONS["check_process_inspection"]()
        result = subprocess.CompletedProcess(["ps"], 1, "", "")
        with patch("subprocess.run", return_value=result):
            with self.assertRaisesRegex(ValueError, "current process"):
                FUNCTIONS["check_process_inspection"]()

    def test_validator_fails_before_later_checks(self):
        with tempfile.TemporaryDirectory(prefix="process-inspection-test.") as directory:
            temporary = Path(directory)
            for diagnostic in ("echo 'process inspection denied' >&2\n", ""):
                with self.subTest(diagnostic=bool(diagnostic)):
                    fake_ps = temporary / "ps"
                    fake_ps.write_text("#!/bin/sh\n" + diagnostic + "exit 1\n")
                    fake_ps.chmod(0o755)
                    marker = temporary / "later-check"
                    fake_ruby = temporary / "ruby"
                    fake_ruby.write_text("#!/bin/sh\ntouch '" + str(marker) + "'\nexit 99\n")
                    fake_ruby.chmod(0o755)
                    environment = dict(os.environ, PATH=str(temporary) + os.pathsep + os.environ["PATH"])
                    result = subprocess.run(["/bin/bash", str(ROOT / "scripts/validate-skills.sh")],
                                            env=environment, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertIn("requires process inspection", result.stderr)
                    self.assertFalse(marker.exists(), "validator continued after failed preflight")


if __name__ == "__main__":
    unittest.main()
