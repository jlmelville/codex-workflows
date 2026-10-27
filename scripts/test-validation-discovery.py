#!/usr/bin/env python3
"""Exercise validation entry points with failed or unusual file discovery."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class ValidationDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='validation-discovery-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.bin = self.root / 'bin'
        self.scratch = self.root / 'tmp'
        for directory in (self.repo / 'scripts', self.repo / 'skills', self.bin, self.scratch):
            directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / '.ruby-version', self.repo / '.ruby-version')
        self.version = (self.repo / '.ruby-version').read_text().strip()
        self.bash = '/bin/bash' if sys.platform == 'darwin' else shutil.which('bash')
        self.injection = self.root / 'injected'
        self.consumed = self.root / 'consumed'
        self.env = dict(os.environ, PATH=f'{self.bin}{os.pathsep}{os.environ["PATH"]}',
                        TMPDIR=str(self.scratch), DISCOVERY_INJECTION=str(self.injection),
                        DISCOVERY_CONSUMED=str(self.consumed),
                        DISCOVERY_REAL_FIND=shutil.which('find'))
        find = self.bin / 'find'
        find.write_text(f'#!{sys.executable}\n' + '''import os
from pathlib import Path
import sys

args = sys.argv[1:]
stage = 'runtime' if '-perm' in args else next(
    (label for pattern, label in [('*.sh', 'shell'), ('*/scripts/*.py', 'Python'),
                                  ('*/scripts/*.rb', 'Ruby'), ('*/scripts/*.R', 'R')]
     if pattern in args), '')
if stage and stage == os.environ.get('DISCOVERY_FAIL_STAGE'):
    Path(os.environ['DISCOVERY_INJECTION']).write_text(stage)
    if os.environ['DISCOVERY_FAIL_MODE'] == 'partial':
        sys.stdout.buffer.write(os.fsencode(os.environ['DISCOVERY_PARTIAL_PATH']) + b'\\0')
    sys.stderr.write('injected discovery failure\\n')
    sys.exit(7)
real = os.environ['DISCOVERY_REAL_FIND']
os.execv(real, [real, *args])
''')
        find.chmod(0o755)

    def write(self, relative, content, executable=False):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        if executable:
            path.chmod(0o755)
        return path

    def invoke(self, name, *args):
        return subprocess.run([self.bash, str(self.repo / 'scripts' / name), *args],
                              cwd=self.repo, env=self.env, capture_output=True,
                              text=True, timeout=30)

    def runtime_fixture(self):
        shutil.copy2(REPO / 'scripts/check-ruby-runtime.sh', self.repo / 'scripts')
        return self.write('scripts/good\nhelper.rb',
                          f'#!/usr/bin/env -S RBENV_VERSION={self.version} ruby\n'
                          'required_ruby_engine = "ruby"\n'
                          f'required_ruby_version = "{self.version}"\n'
                          'unless required_ruby_engine == RUBY_ENGINE && '
                          'required_ruby_version == RUBY_VERSION\nend\n', True)

    def validator_fixture(self):
        shutil.copy2(REPO / 'scripts/validate-skills.sh', self.repo / 'scripts')
        # These checks precede discovery and are outside this fixture's contract.
        for name in ('check-ruby-runtime.sh', 'check-ci-tool-parity.sh',
                     'validate-skill-metadata.rb', 'validate-markdown-references.rb'):
            self.write('scripts/' + name, '#!/bin/sh\nexit 0\n', True)
        self.write('skills/r-performance-workflow/scripts/subprocess-evidence.py',
                   'def check_process_inspection():\n    pass\n')
        paths = {'shell': self.write('scripts/space\nname.sh', '#!/bin/sh\nexit 0\n', True),
                 'Python': self.write('skills/example/scripts/example.py', 'pass\n'),
                 'Ruby': self.write('skills/example/scripts/example.rb', 'puts "ok"\n'),
                 'R': self.write('skills/example/scripts/example.R', 'invisible(NULL)\n')}
        consumer = self.bin / 'bash'
        consumer.write_text('#!/bin/sh\nprintf "%s\\0" "$@" >>"$DISCOVERY_CONSUMED"\n')
        consumer.chmod(0o755)
        return paths

    def inject(self, stage, mode, partial_path):
        self.injection.unlink(missing_ok=True)
        self.consumed.unlink(missing_ok=True)
        self.env.update(DISCOVERY_FAIL_STAGE=stage, DISCOVERY_FAIL_MODE=mode,
                        DISCOVERY_PARTIAL_PATH=str(partial_path))

    def test_runtime_accepts_complete_inventory_and_rejects_bad_helper(self):
        self.runtime_fixture()
        good = self.invoke('check-ruby-runtime.sh', '--quiet')
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertEqual(good.stdout, '')
        self.write('scripts/bad.rb', '#!/usr/bin/env ruby\nputs "unguarded"\n', True)
        bad = self.invoke('check-ruby-runtime.sh', '--quiet')
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn('expected shebang', bad.stderr)
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_runtime_rejects_empty_and_partial_failed_inventory(self):
        good = self.runtime_fixture()
        self.write('scripts/bad.rb', '#!/usr/bin/env ruby\nputs "unguarded"\n', True)
        for mode in ('empty', 'partial'):
            for args in ((), ('--quiet',)):
                with self.subTest(mode=mode, args=args):
                    self.inject('runtime', mode, good)
                    result = self.invoke('check-ruby-runtime.sh', *args)
                    self.assertEqual(self.injection.read_text(), 'runtime')
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('injected discovery failure', result.stderr)
                    self.assertIn('could not discover executable Ruby programs', result.stderr)
                    self.assertNotIn('Ruby runtime policy passed', result.stdout)
                    self.assertEqual(list(self.scratch.iterdir()), [])

    def test_validator_rejects_failed_inventory_before_consuming_any_list(self):
        paths = self.validator_fixture()
        for stage, path in paths.items():
            for mode in ('empty', 'partial'):
                with self.subTest(stage=stage, mode=mode):
                    self.inject(stage, mode, path)
                    result = self.invoke('validate-skills.sh')
                    self.assertEqual(self.injection.read_text(), stage)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('injected discovery failure', result.stderr)
                    self.assertIn(f'could not discover {stage} files', result.stderr)
                    self.assertFalse(self.consumed.exists(), result.stdout + result.stderr)
                    self.assertEqual(list(self.scratch.iterdir()), [])

    def test_validator_preserves_discovered_filename_boundaries(self):
        paths = self.validator_fixture()
        self.invoke('validate-skills.sh')
        # Later checks are absent from this fixture; inspect only the syntax consumer.
        arguments = self.consumed.read_bytes().split(b'\0')
        self.assertIn(os.fsencode(paths['shell']), arguments)


if __name__ == '__main__':
    unittest.main()
