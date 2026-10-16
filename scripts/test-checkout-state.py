#!/usr/bin/env python3
"""Exercise filesystem discovery, checkout state, and inspection preservation."""

import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/dependabot-pr-maintenance/scripts/checkout-state.py'


class CheckoutStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='checkout-state-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / 'checkout with spaces'
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1', GIT_OPTIONAL_LOCKS='0')
        self.git('init', '--quiet')
        self.git('config', 'core.hooksPath', os.devnull)
        self.git('config', 'diff.autoRefreshIndex', 'true')
        for name in ('clean', 'dirty', 'staged', 'deleted'):
            (self.repo / name).write_text('committed\n')
        (self.repo / '.gitignore').write_text('ignored\n')
        self.git('add', '--all')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'fixture')
        (self.repo / 'staged').write_text('staged change\n')
        self.git('add', 'staged')
        (self.repo / 'staged').write_text('additional unstaged change\n')
        (self.repo / 'dirty').write_text('unstaged change\n')
        (self.repo / 'deleted').unlink()
        (self.repo / 'untracked').write_text('untracked work\n')
        (self.repo / 'ignored').write_text('ignored work\n')
        (self.repo / 'outside-link').symlink_to(self.root / 'absent-target')
        clean = self.repo / 'clean'
        info = clean.stat()
        os.utime(clean, ns=(info.st_atime_ns, info.st_mtime_ns - 5_000_000_000))

    def git(self, *args, repo=None):
        result = subprocess.run(
            ['git', '-c', 'diff.autoRefreshIndex=false', '-c', 'core.fsmonitor=false',
             '-C', str(repo or self.repo), *args], env=self.env, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def tree(self):
        # Include Git internals and ignored files; exclude only the helper's output (held in memory).
        return {str(path.relative_to(self.root)): ('link', os.readlink(path)) if path.is_symlink()
                else ('file', path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns)
                for path in self.root.rglob('*') if path.is_symlink() or path.is_file()}

    def invoke(self, *args, input_text=None, env=None, status=0):
        before = self.tree()
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                                input=input_text, text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, status, result.stderr or result.stdout)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(self.tree(), before, 'inspection changed checkout or Git bytes')
        if status != 2:
            self.assertEqual(result.stderr, '')
        return result

    def take(self, *paths, **kwargs):
        return json.loads(self.invoke('snapshot', *(paths or [self.repo]), **kwargs).stdout)

    def compare(self, saved, status=0):
        return json.loads(self.invoke('compare', '--file', '-', input_text=json.dumps(saved), status=status).stdout)

    def test_discover_nested_gitfiles_overlaps_and_aliases_without_git(self):
        nested = self.repo / 'nested checkout\n'
        nested.mkdir()
        self.git('init', '--quiet', repo=nested)
        linked = self.root / 'linked checkout'
        self.git('worktree', 'add', '--quiet', '--detach', str(linked), 'HEAD')
        alias = self.root / 'alias'
        alias.symlink_to(self.repo, target_is_directory=True)
        hidden = self.repo / '.git/hidden/.git'
        hidden.mkdir(parents=True)
        (hidden / 'HEAD').write_text('ref: refs/heads/hidden\n')
        saved = json.loads(self.invoke('discover', self.root, alias, self.repo, self.root,
                                       env=dict(os.environ, PATH='')).stdout)
        self.assertEqual(saved, {
            'schema_version': 1, 'operation': 'discover', 'status': 'complete', 'errors': [],
            'roots': sorted(map(str, (self.root, self.repo))), 'rejected_markers': [],
            'candidates': sorted([
                {'path': str(self.repo), 'marker': 'directory'},
                {'path': str(nested), 'marker': 'directory'},
                {'path': str(linked), 'marker': 'gitfile'},
            ], key=lambda entry: entry['path']),
        })

    def test_discover_skips_descendant_symlinks_but_accepts_explicit_alias_root(self):
        scope = self.root / 'scope'
        scope.mkdir()
        alias = scope / 'alias'
        alias.symlink_to(self.repo, target_is_directory=True)
        (scope / 'loop').symlink_to(scope, target_is_directory=True)
        (scope / 'broken').symlink_to(self.root / 'absent', target_is_directory=True)
        empty = json.loads(self.invoke('discover', scope).stdout)
        self.assertEqual(empty['candidates'], [])
        self.assertEqual(empty['errors'], [])
        self.assertEqual(empty['status'], 'complete')
        found = json.loads(self.invoke('discover', alias).stdout)
        self.assertEqual(found['candidates'], [{'path': str(self.repo), 'marker': 'directory'}])

    def test_discover_relative_gitfile_and_rejected_markers(self):
        scope = self.root / 'scope'
        scope.mkdir()
        valid = scope / 'relative gitfile'
        valid.mkdir()
        # The Git directory is outside the discovery root; only its HEAD metadata is checked.
        (valid / '.git').write_text('gitdir: ../../checkout with spaces/.git\r\n')
        markers = {
            'header': b'not a gitfile\n', 'empty': b'gitdir: \n',
            'missing': b'gitdir: absent\n', 'nul': b'gitdir: bad\0target\n',
            'large': b'gitdir: ' + b'x' * 65536,
        }
        for name, content in markers.items():
            directory = scope / name
            directory.mkdir()
            (directory / '.git').write_bytes(content)
        no_head = scope / 'no-head/.git'
        no_head.mkdir(parents=True)
        symlink = scope / 'symlink'
        symlink.mkdir()
        (symlink / '.git').symlink_to(self.repo / '.git', target_is_directory=True)
        special = scope / 'special'
        special.mkdir()
        os.mkfifo(special / '.git')
        saved = json.loads(self.invoke('discover', scope).stdout)
        self.assertEqual(saved['candidates'], [{'path': str(valid), 'marker': 'gitfile'}])
        self.assertEqual(saved['status'], 'complete')
        self.assertEqual(saved['errors'], [])
        expected = sorted(str(scope / name / '.git')
                          for name in (*markers, 'no-head', 'symlink', 'special'))
        self.assertEqual([entry['path'] for entry in saved['rejected_markers']], expected)
        self.assertTrue(all(entry['reason'] for entry in saved['rejected_markers']))

    def test_discover_root_errors_are_incomplete_and_keep_candidates(self):
        missing = self.root / 'missing'
        file_root = self.repo / 'clean'
        saved = json.loads(self.invoke('discover', missing, file_root, self.repo, status=1).stdout)
        self.assertEqual(saved['status'], 'incomplete')
        self.assertEqual(saved['roots'], [str(self.repo)])
        self.assertEqual(saved['candidates'], [{'path': str(self.repo), 'marker': 'directory'}])
        self.assertEqual([entry['path'] for entry in saved['errors']], sorted(map(str, (missing, file_root))))

    def test_discover_traversal_and_marker_read_errors_are_reported(self):
        blocked = self.root / 'blocked'
        blocked.mkdir()
        unreadable = self.root / 'unreadable'
        unreadable.mkdir()
        (unreadable / '.git').write_text('gitdir: absent\n')
        namespace = runpy.run_path(str(SCRIPT))
        scan = namespace['discover']
        original_scandir, original_open = os.scandir, Path.open
        def scandir(path):
            if Path(path) == blocked:
                raise PermissionError('fixture traversal denied')
            return original_scandir(path)
        def open_file(path, *args, **kwargs):
            if path == unreadable / '.git':
                raise PermissionError('fixture marker read denied')
            return original_open(path, *args, **kwargs)
        before = self.tree()
        with patch('os.scandir', side_effect=scandir), patch.object(Path, 'open', open_file), \
                patch('subprocess.run', side_effect=AssertionError('discovery must not execute commands')):
            saved = scan([str(self.root)])
        self.assertEqual(self.tree(), before)
        self.assertEqual(saved['candidates'], [{'path': str(self.repo), 'marker': 'directory'}])
        self.assertEqual(saved['rejected_markers'], [])
        self.assertEqual(saved['errors'], [
            {'path': str(blocked), 'reason': 'fixture traversal denied'},
            {'path': str(unreadable / '.git'), 'reason': 'fixture marker read denied'},
        ])

    def test_snapshot_roundtrip_and_deduplication(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.repo, target_is_directory=True)
        saved = self.take(self.repo, self.repo, alias)
        self.assertEqual(saved['status'], 'complete')
        self.assertEqual(saved['errors'], [])
        self.assertEqual(len(saved['checkouts']), 1)
        entry = saved['checkouts'][0]
        self.assertEqual(entry['path'], str(self.repo))
        self.assertEqual(entry['tracked']['files'], 5)
        self.assertEqual(entry['untracked']['files'], 2)
        self.assertRegex(entry['head'], r'^[0-9a-f]{40}$')
        self.assertTrue(entry['branch'].startswith('refs/heads/'))
        result = self.compare(saved)
        self.assertTrue(result['matches'])
        self.assertEqual(result['changes'], [])
        self.assertEqual(self.take(self.repo), saved)

    def test_changes_have_field_names_and_nonzero_exit(self):
        saved = self.take()
        (self.repo / 'dirty').write_text('different unstaged bytes\n')
        (self.repo / 'untracked').write_text('different untracked bytes\n')
        result = self.compare(saved, status=1)
        self.assertEqual(result['changes'], [{'path': str(self.repo), 'fields': ['tracked', 'untracked']}])
        self.assertFalse(result['matches'])
        self.assertEqual(result['status'], 'complete')

    def test_snapshot_file_and_multiple_checkouts(self):
        other = self.root / 'other checkout\n'
        other.mkdir()
        self.git('init', '--quiet', repo=other)
        (other / 'odd\nname').write_text('literal filename\n')
        saved = self.take(other, self.repo)
        baseline = self.root / 'before.json'
        baseline.write_text(json.dumps(saved))
        result = json.loads(self.invoke('compare', '--file', baseline).stdout)
        self.assertTrue(result['matches'])
        missing = json.loads(self.invoke('compare', '--file', self.root / 'absent.json', status=1).stdout)
        self.assertEqual(missing['status'], 'incomplete')
        self.assertIsNone(missing['matches'])

    def test_index_and_branch_changes(self):
        saved = self.take()
        self.git('add', 'staged')
        self.git('symbolic-ref', 'HEAD', 'refs/heads/another-branch')
        fields = self.compare(saved, status=1)['changes'][0]['fields']
        self.assertEqual(fields, ['branch', 'head', 'indexes'])

    def test_ignored_files_are_excluded_and_modes_are_observed(self):
        saved = self.take()
        (self.repo / 'ignored').write_text('different ignored bytes')
        self.assertTrue(self.compare(saved)['matches'])
        (self.repo / 'dirty').chmod(0o755)
        self.assertEqual(self.compare(saved, status=1)['changes'][0]['fields'], ['tracked'])

    def test_symlink_targets_are_observed_without_reading_targets(self):
        saved = self.take()
        link = self.repo / 'outside-link'
        link.unlink()
        link.symlink_to(self.root / 'other-absent-target')
        self.assertEqual(self.compare(saved, status=1)['changes'][0]['fields'], ['untracked'])

    def test_linked_worktree(self):
        linked = self.root / 'linked checkout'
        self.git('worktree', 'add', '--quiet', '--detach', str(linked), 'HEAD')
        saved = self.take(linked)
        entry = saved['checkouts'][0]
        self.assertIsNone(entry['branch'])
        self.assertEqual(len(entry['indexes']), 1)
        self.assertTrue(all(Path(path).is_absolute() for path in entry['indexes']))
        self.assertNotIn(str(linked / '.git/index'), entry['indexes'])
        self.assertTrue(self.compare(saved)['matches'])

    def test_split_index_refused_without_touching_metadata(self):
        linked = self.root / 'linked checkout'
        self.git('worktree', 'add', '--quiet', '--detach', str(linked), 'HEAD')
        for repo in (self.repo, linked):
            with self.subTest(linked=repo == linked):
                baseline = self.take(repo)
                self.git('update-index', '--split-index', repo=repo)
                index = Path(self.git('rev-parse', '--git-path', 'index', repo=repo)
                             .decode().removesuffix('\n'))
                index = repo / index
                shared = list(index.parent.glob('sharedindex.*'))
                self.assertTrue(shared)
                # Age the shared index so Git's freshness write is observable on every filesystem.
                for path in shared:
                    os.utime(path, ns=(946684800000000000, 946684800000000000))
                saved = self.take(repo, status=1)
                self.assertEqual(saved['status'], 'incomplete')
                self.assertEqual(saved['checkouts'], [])
                self.assertIn('shared-index', saved['errors'][0]['reason'])
                result = self.compare(baseline, status=1)
                self.assertEqual(result['status'], 'incomplete')
                self.assertIsNone(result['matches'])

    def test_leftover_shared_indexes_are_conservatively_refused(self):
        (self.repo / '.git/sharedindex.leftover').write_bytes(b'leftover fixture')
        saved = self.take(status=1)
        self.assertEqual(saved['status'], 'incomplete')
        self.assertIn('shared-index', saved['errors'][0]['reason'])

    def test_unborn_checkout(self):
        unborn = self.root / 'unborn'
        unborn.mkdir()
        self.git('init', '--quiet', repo=unborn)
        saved = self.take(unborn)
        self.assertIsNone(saved['checkouts'][0]['head'])
        self.assertEqual(list(saved['checkouts'][0]['indexes'].values()), [None])
        self.assertTrue(self.compare(saved)['matches'])

    def test_ref_and_stash_history(self):
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'stash', 'push', '--quiet')
        saved = self.take()
        self.assertEqual(len(saved['checkouts'][0]['stashes']), 1)
        self.git('tag', 'fixture-tag')
        self.assertEqual(self.compare(saved, status=1)['changes'][0]['fields'], ['refs'])
        self.git('symbolic-ref', 'HEAD', 'refs/tags/fixture-tag')
        self.assertTrue(self.compare(self.take())['matches'])

    def test_inherited_git_overrides_and_configured_commands_do_not_run(self):
        marker = self.root / 'filter-was-run'
        command = f'touch "{marker}"; cat'
        self.git('config', 'filter.fixture.clean', command)
        self.git('config', 'core.fsmonitor', f'touch "{marker}"')
        (self.repo / '.gitattributes').write_text('* filter=fixture\n')
        saved = self.take(env=dict(os.environ, GIT_DIR='/absent', GIT_WORK_TREE='/absent',
                                   GIT_INDEX_FILE='/absent', GIT_CONFIG_COUNT='1',
                                   GIT_CONFIG_KEY_0='core.fsmonitor', GIT_CONFIG_VALUE_0=command))
        self.assertEqual(saved['status'], 'complete')
        self.assertFalse(marker.exists())

    def test_missing_checkout_and_incomplete_baseline(self):
        saved = self.take(self.repo, self.root / 'missing', status=1)
        self.assertEqual(saved['status'], 'incomplete')
        self.assertEqual(len(saved['checkouts']), 1)
        self.assertEqual(len(saved['errors']), 1)
        result = self.compare(saved, status=1)
        self.assertIsNone(result['matches'])
        self.assertIn('complete version 1', result['errors'][0]['reason'])
        complete = self.take()
        moved = self.root / 'moved'
        self.repo.rename(moved)
        result = self.compare(complete, status=1)
        self.assertEqual(result['status'], 'incomplete')
        self.assertIsNone(result['matches'])

    def test_subdirectory_nested_repository_and_submodule_refused(self):
        self.take(self.repo / '.git', status=1)
        nested = self.repo / 'nested'
        nested.mkdir()
        self.git('init', '--quiet', repo=nested)
        self.assertIn('unsupported directory', self.take(status=1)['errors'][0]['reason'])
        self.git('update-index', '--add', '--cacheinfo',
                 '160000', self.git('rev-parse', 'HEAD').decode().strip(), 'submodule')
        self.assertIn('submodules', self.take(status=1)['errors'][0]['reason'])

    def test_malformed_baseline_and_usage_errors(self):
        for value in ('{', '[]', '{"schema_version":true}'):
            result = self.invoke('compare', '--file', '-', input_text=value, status=1)
            self.assertEqual(json.loads(result.stdout)['status'], 'incomplete')
        saved = self.take()
        saved['checkouts'][0]['tracked'] = {'files': True, 'sha256': 'bad'}
        self.assertIsNone(self.compare(saved, status=1)['matches'])
        saved = self.take()
        saved['checkouts'].append(saved['checkouts'][0])
        self.assertIn('duplicate', self.compare(saved, status=1)['errors'][0]['reason'])
        for args in ([], ['discover'], ['snapshot'], ['compare'], ['compare', '--file', '-', 'extra']):
            result = self.invoke(*args, status=2)
            self.assertEqual(result.stdout, '')
            self.assertIn('usage:', result.stderr)
        self.assertIn('Ignored files', self.invoke('--help').stdout)
        help_text = self.invoke('discover', '--help').stdout
        for text in ('Filesystem-only', 'symlinks', 'nested checkouts', 'rejected_markers', 'incomplete'):
            self.assertIn(text, help_text)

    def test_index_change_during_inspection_is_incomplete(self):
        namespace = runpy.run_path(str(SCRIPT))
        observe = namespace['snapshot']
        original = observe.__globals__['index_state']
        calls = []
        def changed(index):
            result = original(index)
            calls.append(result)
            return result if len(calls) == 1 else {**result, 'changed': '0' * 64}
        before = self.tree()
        with patch.dict(observe.__globals__, index_state=changed):
            with self.assertRaisesRegex(ValueError, 'index changed during inspection'):
                observe(self.repo)
        self.assertEqual(self.tree(), before)


if __name__ == '__main__':
    unittest.main()
