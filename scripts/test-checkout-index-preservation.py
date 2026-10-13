#!/usr/bin/env python3
"""Exercise the maintenance template's Git wrapper against disposable indexes."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


TEMPLATE = Path(__file__).resolve().parents[1] / 'prompts/weekly-r-ci-updates.md'
INSPECTIONS = (
    ('rev-parse', '--git-path', 'index'),
    ('status', '--porcelain=v1', '--untracked-files=all'),
    ('remote', '-v'),
    ('ls-files', '--stage', '-z'),
    ('diff', '--no-ext-diff', '--no-textconv', '--binary', 'HEAD', '--'),
    ('diff', '--cached', '--no-ext-diff', '--no-textconv', '--binary', '--'),
    ('stash', 'list'),
)


class IndexPreservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        blocks = re.findall(
            r'<!-- checkout-index-inspection:start -->\s*```sh\n(.*?)\n```\s*'
            r'<!-- checkout-index-inspection:end -->',
            TEMPLATE.read_text(encoding='utf-8'), re.DOTALL,
        )
        if len(blocks) != 1:
            raise AssertionError(f'{TEMPLATE}: expected one marked inspection wrapper')
        cls.wrapper = blocks[0]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='checkout-index-preservation-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Never inherit a caller's Git directory, index, or configuration overrides.
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith('GIT_')}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        LC_ALL='C')

    def run_fixture_command(self, command, env):
        result = subprocess.run(command, cwd=self.root, env=env,
                                capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0,
                         f'{command!r}\n{result.stdout!r}\n{result.stderr!r}')
        return result.stdout

    def git(self, repo, *args):
        # Fixture construction and observation use their own protected commands.
        return self.run_fixture_command(
            ['git', '-c', 'diff.autoRefreshIndex=false',
             '-c', f'core.hooksPath={os.devnull}', '-c', 'commit.gpgsign=false',
             '-C', str(repo), *args],
            dict(self.env, GIT_OPTIONAL_LOCKS='0'),
        )

    def inspect_checkout(self, repo, args, wrapper):
        # Execute source from the prompt, rather than copying its safe flags here.
        return self.run_fixture_command(
            ['sh', '-eu', '-c', wrapper + '\ninspect_git "$@"\n',
             'inspect-git', *args],
            dict(self.env, checkout=str(repo)),
        )

    def checkout(self, linked):
        base = self.root / 'main checkout'
        base.mkdir()
        self.git(base, 'init', '--quiet')
        self.git(base, 'config', 'diff.autoRefreshIndex', 'true')
        for name in ('clean.txt', 'dirty.txt', 'staged.txt'):
            (base / name).write_text('committed\n', encoding='utf-8')
        self.git(base, 'add', '--all')
        self.git(base, '-c', 'user.name=Fixture',
                 '-c', 'user.email=fixture@example.invalid',
                 'commit', '--quiet', '-m', 'fixture')
        repo = base
        if linked:
            repo = self.root / 'linked checkout'
            self.git(base, 'worktree', 'add', '--detach', '--quiet', str(repo), 'HEAD')
            self.assertTrue((repo / '.git').is_file())
        (repo / 'staged.txt').write_text('staged change\n', encoding='utf-8')
        self.git(repo, 'add', 'staged.txt')
        (repo / 'staged.txt').write_text('additional unstaged change\n', encoding='utf-8')
        (repo / 'dirty.txt').write_text('unstaged change\n', encoding='utf-8')
        (repo / 'untracked.txt').write_text('untracked work\n', encoding='utf-8')
        # A content-clean file with stale stat data makes diff refresh the index.
        clean = repo / 'clean.txt'
        stat = clean.stat()
        os.utime(clean, ns=(stat.st_atime_ns, stat.st_mtime_ns - 5_000_000_000))
        index = Path(os.fsdecode(self.git(repo, 'rev-parse', '--git-path', 'index')).strip())
        if not index.is_absolute():
            index = repo / index
        if linked:
            self.assertNotEqual(index.parent, repo / '.git')
        return repo, index

    def state(self, repo):
        return {
            'staged': self.git(repo, 'ls-files', '--stage', '-z'),
            'status': self.git(repo, 'status', '--porcelain=v1', '--untracked-files=all'),
            'head': self.git(repo, 'rev-parse', 'HEAD'),
            'refs': self.git(repo, 'for-each-ref', '--format=%(refname) %(objectname)'),
            'stashes': self.git(repo, 'stash', 'list'),
            'config': self.git(repo, 'config', '--local', '--list'),
            'files': {path.name: path.read_bytes() for path in repo.iterdir()
                      if path.is_file() and path.name != '.git'},
        }

    def assert_preserved(self, linked):
        repo, index = self.checkout(linked)
        before = self.state(repo)
        self.assertEqual(before['status'],
                         b' M dirty.txt\nMM staged.txt\n?? untracked.txt\n')
        index_before = index.read_bytes()
        for args in INSPECTIONS:
            self.inspect_checkout(repo, args, self.wrapper)
            self.assertTrue(index.read_bytes() == index_before,
                            f'Index bytes changed after {args!r}')
        self.assertEqual(self.state(repo), before)
        self.assertEqual(index.read_bytes(), index_before)

    def assert_old_refresh_detected(self, linked):
        protection = '-c diff.autoRefreshIndex=false '
        self.assertEqual(self.wrapper.count(protection), 1,
                         'Update the control when changing the template wrapper')
        old_wrapper = self.wrapper.replace(protection, '', 1)
        repo, index = self.checkout(linked)
        before = self.state(repo)
        index_before = index.read_bytes()
        for args in INSPECTIONS:
            self.inspect_checkout(repo, args, old_wrapper)
        self.assertNotEqual(index.read_bytes(), index_before,
                            'Control did not reproduce the old index refresh')
        self.assertEqual(self.state(repo), before,
                         'Control must change only cached index metadata')

    def test_normal_checkout_preserved(self):
        self.assert_preserved(linked=False)

    def test_linked_worktree_preserved(self):
        self.assert_preserved(linked=True)

    def test_normal_checkout_detects_old_refresh(self):
        self.assert_old_refresh_detected(linked=False)

    def test_linked_worktree_detects_old_refresh(self):
        self.assert_old_refresh_detected(linked=True)


if __name__ == '__main__':
    unittest.main()
