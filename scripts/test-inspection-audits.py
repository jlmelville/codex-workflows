#!/usr/bin/env python3
"""Command-level regressions for notebook inspection and audit evidence."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
NOTEBOOK = REPO / 'skills/notebook-inspection/scripts/notebook_inspect.py'
ACTIONS = REPO / 'skills/github-actions-hardening/scripts/audit-actions.sh'
COMMENTS = ACTIONS.with_name('check-action-tag-comments.sh')
ROXYGEN = REPO / 'skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh'
WORKFLOW = '''name: test
on: push
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
'''
DEPENDABOT = '''version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
'''


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='inspection-audits-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}{os.pathsep}{os.environ["PATH"]}',
                        ZIZMOR_OFFLINE='true', XDG_CACHE_HOME=str(self.root / 'cache'))

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def fake(self, name, body):
        path = self.write(f'bin/{name}', '#!/bin/bash\nset -eu\n' + body + '\n')
        path.chmod(0o755)

    def run_command(self, command, *args):
        return subprocess.run([str(command), *map(str, args)], cwd=self.root,
                              env=self.env, capture_output=True, text=True, timeout=30)

    def assert_status(self, result, expected):
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def notebook(self, name='good.ipynb', value=None):
        if value is None:
            value = {'cells': [{'cell_type': 'code', 'source': ['needle'],
                                'outputs': [{'output_type': 'display_data', 'data': {
                                    'text/plain': 'readable', 'image/png': 'SECRET_IMAGE_DATA',
                                    'text/html': 'SECRET_HTML_DATA'}}]}]}
        return self.write(name, json.dumps(value))

    def inspect(self, *args):
        return self.run_command(sys.executable, NOTEBOOK, *args)

    def test_notebook_bad_targets_and_batch_continuation(self):
        good = self.notebook()
        wrong = self.write('wrong.txt', '{}')
        for target in ['missing-directory', 'missing.ipynb', wrong, self.bin]:
            # Directory arguments are only supported by stats/search.
            commands = ['cells', 'outputs', 'validate'] if target == self.bin else ['stats', 'cells', 'outputs', 'validate', 'search']
            for command in commands:
                with self.subTest(command=command, target=target):
                    options = [command, 'needle'] if command == 'search' else [command]
                    result = self.inspect(*options, target, good)
                    self.assert_status(result, 2)
                    self.assertIn(str(good), result.stdout)
                    self.assertIn(str(target), result.stderr)
                    self.assertNotIn('Traceback (most recent call last)', result.stderr)

    def test_notebook_shape_and_parse_failures_are_controlled(self):
        good = self.notebook()
        invalid = [[], 42, {}, {'cells': {}}, {'cells': [None]},
                   {'cells': [{'cell_type': 'code', 'source': [42]}]},
                   {'cells': [{'cell_type': 'code', 'source': '', 'outputs': {}}]},
                   {'cells': [{'cell_type': 'code', 'source': '', 'outputs': [None]}]},
                   {'cells': [{'cell_type': 'code', 'source': '', 'outputs': [{'data': []}]}]},
                   {'cells': [{'cell_type': 'code', 'source': '', 'outputs': [{'data': {'text/plain': [3]}}]}]}]
        bad = self.root / 'bad.ipynb'
        for value in invalid + ['MALFORMED_JSON']:
            bad.write_text('{' if value == 'MALFORMED_JSON' else json.dumps(value))
            for command in ['stats', 'cells', 'outputs', 'search']:
                with self.subTest(value=value, command=command):
                    options = [command, 'needle'] if command == 'search' else [command]
                    result = self.inspect(*options, bad, good)
                    self.assert_status(result, 2)
                    self.assertIn(str(good), result.stdout)
                    self.assertIn(str(bad), result.stderr)
                    self.assertNotIn('Traceback (most recent call last)', result.stderr)
        result = self.inspect('validate', bad, good)
        self.assert_status(result, 2)
        self.assertIn(f'{good}: valid JSON', result.stdout)

    def test_json_validation_does_not_claim_notebook_schema(self):
        for value in [[], 42, {}]:
            result = self.inspect('validate', self.notebook(value=value))
            self.assert_status(result, 0)
            self.assertIn('valid JSON', result.stdout)

    def test_cell_types_stats_and_recursive_search(self):
        good = self.notebook('nested/good.ipynb', {'cells': [
            {'cell_type': 'markdown', 'source': ['alpha notes\n']},
            {'cell_type': 'code', 'source': 'needle', 'outputs': []},
        ]})
        result = self.inspect('stats', self.root / 'nested')
        self.assert_status(result, 0)
        self.assertIn('cells=2\tcode=1\tcode_with_outputs=0\toutputs=0', result.stdout)
        self.assert_status(self.inspect('search', 'alpha', good), 1)
        for command in [('cells', '--type', 'all'), ('search', '--type', 'all', 'alpha')]:
            result = self.inspect(*command, good)
            self.assert_status(result, 0)
            self.assertIn('alpha notes', result.stdout)
        self.write('nested/bad.ipynb', '{')
        result = self.inspect('search', '--type', 'all', 'alpha', self.root)
        self.assert_status(result, 2)
        self.assertIn('alpha notes', result.stdout)
        self.assertIn('bad.ipynb', result.stderr)

    def test_search_miss_empty_directory_and_partial_match_status(self):
        good = self.notebook()
        self.assert_status(self.inspect('search', 'absent', good), 1)
        self.assert_status(self.inspect('search', 'needle', good), 0)
        self.assert_status(self.inspect('search', 'needle', good, 'missing'), 2)
        empty = self.root / 'empty'
        empty.mkdir()
        for command, expected in [('stats', 0), ('search', 1)]:
            options = [command, 'needle'] if command == 'search' else [command]
            result = self.inspect(*options, empty)
            self.assert_status(result, expected)
            self.assertIn('no notebooks found', result.stderr)

    def test_notebook_help_and_invalid_limit(self):
        self.assert_status(self.inspect('--help'), 0)
        result = self.inspect('outputs', '--limit', '0', self.notebook())
        self.assert_status(result, 2)
        self.assertEqual(result.stdout, '')
        self.assertIn('must be a positive integer', result.stderr)

    def test_mixed_mime_output_discloses_omissions_without_payload(self):
        result = self.inspect('outputs', '--limit', '4', self.notebook())
        self.assert_status(result, 0)
        for expected in ['read', 'truncated to 4 characters', 'image/png', 'text/html']:
            self.assertIn(expected, result.stdout)
        self.assertNotIn('SECRET_', result.stdout)

    def test_roxygen_failed_discovery_and_legitimate_empty_population(self):
        (self.root / 'R').mkdir()
        result = self.run_command('/bin/bash', ROXYGEN, '--odd-backticks')
        self.assert_status(result, 0)
        self.assertIn('No R source files found', result.stdout)
        self.write('R/present.R', "#' A known-present source\nx <- 1\n")
        self.fake('find', 'printf "R/present.R\\0"\necho "injected find failure" >&2\nexit 37')
        result = self.run_command('/bin/bash', ROXYGEN, '--odd-backticks')
        self.assert_status(result, 1)
        self.assertIn('injected find failure', result.stderr)
        self.assertNotIn('No R source files found', result.stdout)
        self.assertNotIn('No odd roxygen backtick', result.stdout)

    def workflow(self):
        return self.write('.github/workflows/test.yml', WORKFLOW)

    def fake_scanners(self):
        self.fake('actionlint', 'exit 0')
        self.fake('zizmor', 'printf "%s\\n" "$@" > scanner-args')

    def test_actions_failed_discovery_reaches_complete_command_status(self):
        self.workflow()
        self.fake_scanners()
        self.fake('find', 'printf ".github/workflows/test.yml\\0"\necho "injected find failure" >&2\nexit 37')
        for script in [ACTIONS, COMMENTS]:
            with self.subTest(script=script):
                result = self.run_command('/bin/bash', script, '--quiet', '.github/workflows')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('injected find failure', result.stderr)
                self.assertIn('discovery failed', result.stderr)
                self.assertNotIn('completed', result.stdout)

    def test_each_actions_grep_producer_failure_is_not_a_clean_scan(self):
        self.workflow()
        self.fake_scanners()
        self.env['REAL_GREP'] = shutil.which('grep')
        for pattern in ['uses:[[:space:]]*[^#]+@', 'uses:[[:space:]]*actions/checkout@']:
            with self.subTest(pattern=pattern):
                self.env['FAIL_PATTERN'] = pattern
                self.fake('grep', 'if [[ "$*" == *"${FAIL_PATTERN}"* ]]; then\n'
                          '  echo "injected grep failure" >&2\n  exit 37\nfi\n'
                          'exec "${REAL_GREP}" "$@"')
                result = self.run_command('/bin/bash', ACTIONS, '--quiet')
                self.assert_status(result, 1)
                self.assertIn('injected grep failure', result.stderr)
                self.assertNotIn('completed', result.stdout)

    def test_actions_scanner_targets_include_dependabot_without_workflows(self):
        self.fake_scanners()
        self.workflow()
        for extension in ['yml', 'yaml']:
            config = self.write(f'.github/dependabot.{extension}', DEPENDABOT)
            for workflows in [True, False]:
                with self.subTest(extension=extension, workflows=workflows):
                    result = self.run_command('/bin/bash', ACTIONS, '--quiet')
                    self.assert_status(result, 0)
                    args = (self.root / 'scanner-args').read_text().splitlines()
                    self.assertIn('--collect=workflows,dependabot', args)
                    self.assertIn('--strict-collection', args)
                    self.assertIn(f'.github/dependabot.{extension}', args)
                    self.assertEqual('.github/workflows' in args, workflows)
                shutil.rmtree(self.root / '.github/workflows', ignore_errors=True)
            config.unlink()
            self.workflow()

    def test_real_zizmor_accepts_valid_targets_and_rejects_malformed_config(self):
        self.assertIsNotNone(shutil.which('zizmor'), 'installed zizmor required for boundary test')
        self.fake('actionlint', 'exit 0')
        self.workflow()
        self.assert_status(self.run_command('/bin/bash', ACTIONS, '--quiet'), 0)
        config = self.write('.github/dependabot.yml', DEPENDABOT)
        for workflows in [True, False]:
            with self.subTest(workflows=workflows):
                config.write_text(DEPENDABOT)
                self.assert_status(self.run_command('/bin/bash', ACTIONS, '--quiet', '.github/workflows'), 0)
                config.write_text('version: 2\nupdates: [\n')
                result = self.run_command('/bin/bash', ACTIONS, '--quiet', '.github/workflows')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('dependabot', result.stderr.lower())
                self.assertNotIn('completed', result.stdout)
            shutil.rmtree(self.root / '.github/workflows', ignore_errors=True)
        # The absent workflow directory can be supplied as an absolute target too.
        config.write_text(DEPENDABOT)
        self.assert_status(self.run_command('/bin/bash', ACTIONS, '--quiet', self.root / '.github/workflows'), 0)
        config.unlink()
        malformed_workflow = self.workflow()
        malformed_workflow.write_text('jobs: [')
        result = self.run_command('/bin/bash', ACTIONS, '--quiet')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('completed', result.stdout)

    def test_actions_empty_population_and_invalid_explicit_target(self):
        self.fake_scanners()
        result = self.run_command('/bin/bash', ACTIONS, '--quiet')
        self.assert_status(result, 0)
        self.assertIn('no workflow YAML or Dependabot configuration', result.stderr)
        self.assertFalse((self.root / 'scanner-args').exists())
        self.assert_status(self.run_command('/bin/bash', ACTIONS, 'misspelled-directory'), 2)
        (self.root / '.github/workflows').mkdir(parents=True)
        result = self.run_command('/bin/bash', ACTIONS, '--quiet')
        self.assert_status(result, 0)
        self.assertFalse((self.root / 'scanner-args').exists())


if __name__ == '__main__':
    unittest.main()
