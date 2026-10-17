#!/usr/bin/env python3
"""Run the public shell helper with real R and controlled check results."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/r-package-workflow/scripts/check-r-package.sh'


class RPackageCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='r-package-check-test-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        library = cls.root / 'library'
        library.mkdir()
        fake_bin = cls.root / 'bin'
        fake_bin.mkdir()
        air = fake_bin / 'air'
        air.write_text('#!/bin/sh\nexit 0\n')
        air.chmod(0o755)
        cls.env = os.environ.copy()
        cls.env.update(R_LIBS=str(library), R_LIBS_USER=str(library), R_LIBS_SITE='NULL',
                       R_ENVIRON_USER=os.devnull, R_PROFILE_USER=os.devnull,
                       PATH=str(fake_bin) + os.pathsep + cls.env['PATH'])

        # Only dependency results are fixtures; R evaluates the helper's actual expression.
        sources = {
            'testthat': 'test_local <- function() invisible(NULL)\n',
            'lintr': 'lint_package <- function() list()\n',
            'devtools': '''check <- function(document, args, error_on) {
  stopifnot(identical(document, FALSE), identical(args, "--no-manual"),
            identical(error_on, "note"))
  cat("fixture raw check output\\n")
  case <- Sys.getenv("R_PACKAGE_CHECK_CASE")
  if (case == "diagnostic") stop("fixture check found a NOTE", call. = FALSE)
  list(status = switch(case, success = 0L, nonzero = 1L, missing = NULL,
                       unknown = NA_integer_),
       errors = character(), warnings = character(), notes = character())
}
''',
        }
        package_paths = []
        for name, source in sources.items():
            package = cls.root / name
            (package / 'R').mkdir(parents=True)
            (package / 'DESCRIPTION').write_text(
                f'Package: {name}\nVersion: 0.0.0\nTitle: Check Result Fixture\n'
                'Description: Controlled dependency results for helper regression tests.\n'
                'Authors@R: person("Test", "Fixture", email = "test@example.invalid", '
                'role = c("aut", "cre"))\nLicense: MIT\n')
            (package / 'NAMESPACE').write_text('exportPattern("^[[:alpha:]]+")\n')
            (package / 'R' / 'fixture.R').write_text(source)
            package_paths.append(str(package))
        r = shutil.which('R')
        if r is None:
            raise RuntimeError('R is required for package-check regression tests')
        installed = subprocess.run(
            [r, 'CMD', 'INSTALL', '--no-docs', '--no-byte-compile',
             '--library=' + str(library), *package_paths],
            env=cls.env, capture_output=True, text=True, timeout=90)
        if installed.returncode:
            raise RuntimeError(installed.stdout + installed.stderr)

    def invoke(self, case, mode):
        with tempfile.TemporaryDirectory(prefix='package-', dir=self.root) as tmp:
            package = Path(tmp)
            (package / 'DESCRIPTION').write_text('Package: fixture\nVersion: 0.0.0\n')
            return subprocess.run(
                [str(SCRIPT), mode], cwd=package,
                env=dict(self.env, R_PACKAGE_CHECK_CASE=case),
                capture_output=True, text=True, timeout=30)

    def test_successful_completion(self):
        for mode in ('full', 'ci'):
            with self.subTest(mode=mode):
                result = self.invoke('success', mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('fixture raw check output', result.stdout)

    def test_unsuccessful_completion_with_empty_diagnostics(self):
        for mode in ('full', 'ci'):
            for case in ('nonzero', 'missing', 'unknown'):
                with self.subTest(mode=mode, case=case):
                    result = self.invoke(case, mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('did not complete successfully', result.stderr)
                    self.assertIn('fixture raw check output', result.stdout)

    def test_diagnostic_failure_is_preserved(self):
        for mode in ('full', 'ci'):
            with self.subTest(mode=mode):
                result = self.invoke('diagnostic', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('fixture check found a NOTE', result.stderr)
                self.assertIn('fixture raw check output', result.stdout)


if __name__ == '__main__':
    unittest.main()
