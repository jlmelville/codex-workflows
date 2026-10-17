#!/usr/bin/env python3
"""Exercise whole-worktree compatibility and scoped review completeness."""

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/planning-workflow/scripts/patch-identity.rb'
DIFF_OPTIONS = ['--binary', '--no-ext-diff', '--no-textconv', '--full-index', '--no-color',
                '--src-prefix=a/', '--dst-prefix=b/']


class PatchIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='patch-identity-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        for path, text in [('.gitignore', 'R/cache/\nscratch/cache/\n'),
                           ('R/code.R', 'original\n'), ('tests/existing.R', 'existing\n'),
                           ('README.md', 'readme\n')]:
            self.write(path, text)
        self.git('add', '.')
        self.git('-c', 'core.hooksPath=' + os.devnull, '-c', 'commit.gpgsign=false',
                 'commit', '--quiet', '-m', 'fixture')
        self.write('R/code.R', 'modified\n')
        self.write('tests/new.R', 'new test\n')
        for i in range(32):
            self.write(f'scratch/note-{i}.txt', 'unrelated\n')
        self.scopes = ['--scope', 'R', '--scope', 'tests']
        self.whole = ['--include-untracked', 'tests/new.R']
        self.whole += [arg for i in range(32)
                       for arg in ('--exclude-untracked', f'scratch/note-{i}.txt')]

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content if isinstance(content, bytes) else content.encode())

    def git(self, *args, accepted=(0,)):
        result = subprocess.run(['git', *args], cwd=self.root, env=self.env,
                                capture_output=True, timeout=15)
        self.assertIn(result.returncode, accepted, result.stderr)
        return result.stdout

    def snapshot(self):
        files = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*')
                 if p.is_file() and '.git' not in p.relative_to(self.root).parts}
        return files, self.git('ls-files', '--stage', '-z'), self.git('rev-parse', 'HEAD')

    def invoke(self, args):
        before = self.snapshot()
        result = subprocess.run([str(SCRIPT), *args], cwd=self.root, env=self.env,
                                capture_output=True, timeout=15)
        self.assertEqual(self.snapshot(), before, 'helper changed files, staged entries, or HEAD')
        return result

    def digest(self, args):
        result = self.invoke(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, rb'\A[0-9a-f]{64}\n\Z')
        return result.stdout

    def refuses(self, args, message, status=1):
        result = self.invoke(args)
        self.assertEqual(result.returncode, status, result.stderr)
        self.assertEqual(result.stdout, b'')
        self.assertIn(message.encode(), result.stderr)

    def test_whole_worktree_digest_and_classification_are_unchanged(self):
        self.refuses([], 'uncategorized untracked path')
        expected = hashlib.sha256(self.git('diff', *DIFF_OPTIONS))
        expected.update(self.git('diff', '--no-index', *DIFF_OPTIONS, '--', os.devnull,
                                 'tests/new.R', accepted=(0, 1)))
        original = self.digest(self.whole)
        self.assertEqual(original.strip().decode(), expected.hexdigest())
        self.write('scratch/cache/ignored.txt', 'ignored\n')
        self.assertEqual(self.digest(self.whole), original)
        self.refuses(self.whole + ['--include-untracked', 'scratch/cache/ignored.txt'],
                     'included path is not an untracked file')
        self.write('scratch/new.txt', 'unrelated addition\n')
        self.refuses(self.whole, 'uncategorized untracked path')
        self.assertEqual(self.digest(self.whole + ['--exclude-untracked', 'scratch/new.txt']), original)

    def test_scoped_new_files_and_unrelated_changes(self):
        original = self.digest(self.scopes)
        self.assertEqual(self.digest(self.scopes), original)
        self.write('scratch/another.txt', 'unrelated\n')
        self.write('R-other/outside.R', 'outside prefix\n')
        self.write('README.md', 'unrelated tracked edit\n')
        self.assertEqual(self.digest(self.scopes), original)
        known_files = ['--scope', 'R/code.R', '--scope', 'tests/new.R']
        known_identity = self.digest(known_files)
        for path, content in [('tests/unanticipated.R', 'new sibling\n'),
                              ('R/new.R', 'new source\n'), ('tests/binary.bin', bytes(range(256))),
                              ('tests/a space\n[case].R', 'unusual filename\n'),
                              ('tests/empty.R', b'')]:
            with self.subTest(path=path):
                self.write(path, content)
                self.assertNotEqual(self.digest(self.scopes), original)
                self.assertEqual(self.digest(known_files), known_identity)
                (self.root / path).unlink()
                self.assertEqual(self.digest(self.scopes), original)
        for path in ('R/code.R', 'tests/new.R'):
            saved = (self.root / path).read_bytes()
            self.write(path, b'changed content\n')
            self.assertNotEqual(self.digest(self.scopes), original)
            self.write(path, saved)
        (self.root / 'R/code.R').unlink()
        deleted = self.digest(self.scopes)
        self.assertNotEqual(deleted, original)
        self.write('R/renamed.R', 'modified\n')
        self.assertNotIn(self.digest(self.scopes), (original, deleted))

    def test_textconv_cannot_hide_tracked_or_untracked_bytes(self):
        self.write('.gitattributes', '*.bin diff=mask\n')
        self.write('tests/tracked.bin', b'\x00baseline')
        self.git('add', '.gitattributes', 'tests/tracked.bin')
        self.git('-c', 'core.hooksPath=' + os.devnull, '-c', 'commit.gpgsign=false',
                 'commit', '--quiet', '-m', 'textconv fixture')
        self.git('config', 'diff.mask.textconv',
                 "sh -c 'printf invoked >> .git/textconv-marker; printf masked'")
        self.write('tests/tracked.bin', b'\x00first')
        self.write('tests/new.bin', b'\x00first')

        # Prove that the converter hides this change before testing the helper.
        self.assertEqual(self.git('diff', '--no-ext-diff', '--', 'tests/tracked.bin'), b'')
        marker = self.root / '.git/textconv-marker'
        self.assertTrue(marker.exists())
        marker.unlink()
        modes = {'whole': self.whole + ['--include-untracked', 'tests/new.bin'],
                 'scoped': self.scopes}
        for mode, args in modes.items():
            with self.subTest(mode=mode):
                original = self.digest(args)
                self.assertEqual(self.digest(args), original)
                for path in ('tests/tracked.bin', 'tests/new.bin'):
                    with self.subTest(path=path):
                        self.write(path, b'\x00second')
                        self.assertNotEqual(self.digest(args), original)
                        self.write(path, b'\x00first')
                        self.assertEqual(self.digest(args), original)
                self.write('scratch/note-0.txt', 'changed excluded content\n')
                self.assertEqual(self.digest(args), original)
                self.assertFalse(marker.exists(), 'helper invoked a text converter')

    def test_ignored_files_need_explicit_decisions(self):
        original = self.digest(self.scopes)
        self.write('R/cache/evidence.R', 'ignored evidence\n')
        self.write('R/cache/log.txt', 'ignored log\n')
        self.refuses(self.scopes, 'unclassified ignored path inside scope')
        included = ['--include-ignored', 'R/cache/evidence.R']
        excluded = ['--exclude-ignored', 'R/cache/log.txt']
        self.refuses(self.scopes + included, 'unclassified ignored path inside scope')
        result = self.invoke(self.scopes + included + excluded)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'included ignored: "R/cache/evidence.R"', result.stderr)
        self.assertIn(b'excluded ignored: "R/cache/log.txt"', result.stderr)
        identity = result.stdout
        self.assertNotEqual(identity, original)
        self.write('R/cache/log.txt', 'different excluded log\n')
        self.assertEqual(self.digest(self.scopes + included + excluded), identity)
        self.write('R/cache/evidence.R', 'changed included evidence\n')
        self.assertNotEqual(self.digest(self.scopes + included + excluded), identity)
        excluded_only = ['--exclude-ignored', 'R/cache/evidence.R', *excluded]
        excluded_identity = self.digest(self.scopes + excluded_only)
        self.write('R/cache/another-log.txt', 'another ignored log\n')
        self.assertNotEqual(self.digest(self.scopes + excluded_only +
                                       ['--exclude-ignored', 'R/cache/another-log.txt']), excluded_identity)
        (self.root / 'R/cache/another-log.txt').unlink()
        self.assertRegex(self.digest(['--scope', 'R/cache/evidence.R', *included]), rb'[0-9a-f]{64}')
        self.refuses(self.scopes + included + excluded + included, 'duplicate included ignored path')
        self.refuses(self.scopes + included + excluded + ['--exclude-ignored', 'R/cache/evidence.R'],
                     'ignored path is both included and excluded')
        self.write('scratch/cache/other.R', 'outside ignored\n')
        for path in ('scratch/cache/other.R', 'tests/new.R', 'R/cache/missing.R'):
            self.refuses(self.scopes + included + excluded + ['--include-ignored', path],
                         'not an ignored file inside scope')

    def test_scope_manifest_baseline_and_literal_paths(self):
        original = self.digest(self.scopes)
        self.assertEqual(self.digest(['--scope', 'tests', '--scope', 'R/.', '--scope', 'R']), original)
        self.assertNotEqual(self.digest(self.scopes + ['--scope', 'README.md']), original)
        self.git('-c', 'core.hooksPath=' + os.devnull, '-c', 'commit.gpgsign=false',
                 'commit', '--quiet', '--allow-empty', '-m', 'different baseline')
        self.assertNotEqual(self.digest(self.scopes), original)
        special = 'review [a]\n'
        self.write(special + '/new.R', 'literal scoped content\n')
        literal = self.digest(['--scope', special])
        self.write('review a\n/outside.R', 'glob-shaped sibling\n')
        self.assertEqual(self.digest(['--scope', special]), literal)
        self.write(special + '/new.R', 'modified literal content\n')
        self.assertNotEqual(self.digest(['--scope', special]), literal)

    def test_invalid_scope_arguments_and_index(self):
        for path, message in [('../escape', 'scope path escapes'), ('.', 'scope path escapes'),
                              (str(self.root), 'scope path must be repository-relative'),
                              ('missing', 'scope matches no files'),
                              ('tests/existing.R', 'working patch is empty')]:
            self.refuses(['--scope', path], message)
        self.refuses(['--include-ignored', 'R/cache/log.txt'], 'ignored-file flags require --scope', 2)
        for flag in ('--include-untracked', '--exclude-untracked'):
            self.refuses(self.scopes + [flag, 'tests/new.R'], '--scope cannot mix', 2)
        self.write('README.md', 'staged outside-scope change\n')
        self.git('add', 'README.md')
        self.refuses(self.scopes, 'the index is not clean')
        self.refuses(self.whole, 'the index is not clean')


if __name__ == '__main__':
    unittest.main()
