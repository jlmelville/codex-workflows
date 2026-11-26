"""Regression tests for the case names and replay command in benchmark evidence."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "skills/r-performance-workflow/scripts/benchmark-evidence.R"


class BenchmarkEvidenceTests(unittest.TestCase):
    def test_duplicate_case_names_fail_before_either_case_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cases.R").write_text(
                'benchmark_cases <- list(\n'
                '  trial = function() { writeLines("first", "called"); Sys.sleep(0.02) },\n'
                '  trial = function() { writeLines("second", "called"); Sys.sleep(0.02) }\n'
                ')\n'
            )
            result = subprocess.run(
                ["Rscript", "--vanilla", HELPER, "cases.R", "--reps", "1"],
                cwd=root, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate case name: trial", result.stderr)
            self.assertFalse((root / "called").exists())

    def test_command_from_report_replays_with_quoted_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = "benchmark helper.R"
            cases = "two cases.R"
            prefix = "user's results"
            shutil.copyfile(HELPER, root / script)
            (root / cases).write_text(
                'benchmark_cases <- list(base = function() Sys.sleep(0.02),\n'
                '                        candidate = function() Sys.sleep(0.02))\n'
            )
            command = ["Rscript", "--vanilla", script, cases, "--reps", "1",
                       "--baseline", "candidate", "--out", prefix]
            subprocess.run(command, cwd=root, check=True, stdout=subprocess.DEVNULL)

            report = root / (prefix + ".md")
            csv = root / (prefix + ".csv")
            block = report.read_text().split("```sh\n", 1)[1].split("\n```", 1)[0]
            report.unlink()
            csv.unlink()
            replay = subprocess.run(["sh", "-c", block], cwd=root, capture_output=True, text=True)
            self.assertEqual(replay.returncode, 0, replay.stderr)
            self.assertIn("- baseline: candidate\n", report.read_text())
            self.assertEqual(len(csv.read_text().splitlines()), 3)


if __name__ == "__main__":
    unittest.main()
