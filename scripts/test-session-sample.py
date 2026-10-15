#!/usr/bin/env python3
"""Exercise metadata selection and read-only behavior using synthetic inputs."""

from datetime import datetime, timezone
import json
from pathlib import Path
import runpy
import sqlite3
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/learning-process-review/scripts/select-session-sample.py'
CUTOFF = '2026-01-01T00:00:00Z'
BASE = int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp())


def stamp(offset):
    return datetime.fromtimestamp(BASE + offset, timezone.utc).isoformat().replace('+00:00', 'Z')


class SessionSampleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='session-sample-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = self.root / 'catalog ? #.sqlite'
        self.workspace = str(self.root / 'workspace')
        (self.root / 'learning-state').mkdir()
        (self.root / 'learning-state' / 'sentinel').write_text('unchanged\n')
        self.create_catalog()

    def create_catalog(self, optional=True):
        self.catalog.unlink(missing_ok=True)
        extra = ', created_at_ms INTEGER, agent_path TEXT' if optional else ''
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT, '
                               'created_at INTEGER, source TEXT, cwd TEXT, title TEXT, '
                               'first_user_message TEXT, has_user_event INTEGER' + extra + ')')
        self.optional = optional

    def add(self, identity, created=1000, completed=10, source='cli', agent_path=None,
            meta_source=None, meta_agent=None, users=1, milliseconds=True, workspace=None):
        rollout = self.root / (identity + '.jsonl')
        records = [{'type': 'session_meta', 'payload': {
            'id': identity, 'source': meta_source if meta_source is not None else source,
            'agent_path': meta_agent}}]
        records += [{'type': 'response_item', 'payload': {
            'type': 'message', 'role': 'user', 'content': 'PRIVATE_OUTCOME'}} for _ in range(users)]
        records += [{'type': 'event_msg', 'timestamp': stamp(completed),
                     'payload': {'type': 'task_complete'}}]
        rollout.write_text(''.join(json.dumps(record) + '\n' for record in records))
        values = {'id': identity, 'rollout_path': str(rollout), 'created_at': BASE + created // 1000,
                  'source': source, 'cwd': workspace or self.workspace, 'title': 'PRIVATE_OUTCOME',
                  'first_user_message': 'PRIVATE_OUTCOME', 'has_user_event': 0}
        if self.optional:
            values.update(created_at_ms=BASE * 1000 + created if milliseconds else None,
                          agent_path=agent_path)
        with sqlite3.connect(self.catalog) as connection:
            names = ', '.join(values)
            connection.execute(f'INSERT INTO threads ({names}) VALUES ({", ".join("?" for _ in values)})',
                               tuple(values.values()))
        return rollout

    def append(self, path, tag, offset=20):
        with path.open('a') as stream:
            stream.write(json.dumps({'type': 'event_msg', 'timestamp': stamp(offset),
                                     'payload': {'type': tag}}) + '\n')

    def run_selector(self, count=1, extra=()):
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        args = ['--catalog', str(self.catalog), '--workspace', self.workspace,
                '--after', CUTOFF, '--count', str(count)]
        result = subprocess.run([sys.executable, str(SCRIPT), *args, *extra],
                                capture_output=True, text=True, timeout=15)
        after = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(after, before, 'selector wrote catalog, rollouts, or learning state')
        self.assertNotIn('Traceback', result.stderr)
        self.assertNotIn('PRIVATE_OUTCOME', result.stdout + result.stderr)
        return result

    def manifest(self, count=1, status='ready'):
        result = self.run_selector(count)
        self.assertEqual(result.returncode, 0 if status == 'ready' else 1, result.stderr)
        self.assertEqual(result.stderr, '')
        document = json.loads(result.stdout)
        self.assertEqual(document['status'], status)
        self.assertEqual(sum(document['counts'][key] for key in ('eligible', 'excluded', 'unknown')),
                         document['counts']['catalog_candidates'])
        if status != 'ready':
            self.assertEqual(document['selected'], [])
        self.assertNotIn('rollout_path', result.stdout)
        return document

    def test_ordering_and_exact_size(self):
        self.add('a', created=1001, completed=20)
        self.add('b', created=1002, completed=20)
        self.add('c', created=1002, completed=20)
        self.add('d', created=9000, completed=10)
        result = self.manifest(3)
        self.assertEqual([item['id'] for item in result['selected']], ['c', 'b', 'a'])
        self.assertEqual(result['counts']['eligible'], 4)
        self.assertEqual(result['selected'][0]['created_at'], '2026-01-01T00:00:01.002000Z')
        self.manifest(5, 'insufficient')

    def test_strict_cutoffs_and_second_fallback(self):
        self.add('created-equal', created=0)
        self.add('old-reopened', created=-1000, completed=100)
        self.add('completed-equal', completed=0)
        self.add('completed-before', completed=-1)
        self.add('millisecond-new', created=1)
        self.add('second-fallback', created=2000, milliseconds=False)
        result = self.manifest(2)
        self.assertEqual({item['id'] for item in result['selected']}, {'millisecond-new', 'second-fallback'})
        self.assertEqual(result['excluded_by_reason'], {
            'created_at_or_before_cutoff': 2, 'completed_at_or_before_cutoff': 2})

    def test_sources_subagents_and_workspace(self):
        self.add('root', source='vscode', agent_path='/root')
        self.add('source-child', source='{"subagent":{"other":"guardian"}}')
        self.add('catalog-child', agent_path='/root/child')
        self.add('rollout-child', meta_source={'subagent': {'other': 'worker'}})
        self.add('rollout-agent', meta_agent='/root/worker')
        self.add('other-workspace', workspace=self.workspace + '-other')
        result = self.manifest()
        self.assertEqual([item['id'] for item in result['selected']], ['root'])
        self.assertEqual(result['counts']['catalog_candidates'], 5)
        self.assertEqual(result['excluded_by_reason'], {'source': 1, 'subagent': 3})

    def test_latest_lifecycle_and_actual_user_records(self):
        self.add('good')
        for tag in ('task_started', 'task_failed', 'turn_aborted'):
            self.append(self.add(tag), tag)
        self.add('no-users', users=0)
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('UPDATE threads SET has_user_event = 1 WHERE id = ?', ('no-users',))
        result = self.manifest()
        self.assertEqual([item['id'] for item in result['selected']], ['good'])
        self.assertEqual(result['excluded_by_reason'], {'no_user_messages': 1, 'not_completed': 3})

    def test_unknown_metadata_blocks_otherwise_sufficient_selection(self):
        self.add('good')
        self.add('missing').unlink()
        self.add('malformed').write_text('{PRIVATE_OUTCOME')
        self.add('empty').write_text('')
        self.append(self.add('future-tag'), 'task_new_terminal')
        path = self.add('wrong-identity')
        path.write_text(path.read_text().replace('wrong-identity', 'different-identity'))
        result = self.manifest(status='incomplete')
        self.assertEqual(result['counts']['eligible'], 1)
        self.assertEqual(result['counts']['unknown'], 5)
        self.assertEqual({item['reason'] for item in result['unknown']}, {
            'unreadable_rollout', 'invalid_jsonl_or_timestamp', 'missing_session_metadata',
            'unsupported_lifecycle_event', 'rollout_identity_mismatch'})

    def test_bad_timestamps_are_unknown(self):
        self.add('good')
        self.append(self.add('bad-time'), 'task_complete')
        path = self.root / 'bad-time.jsonl'
        path.write_text(path.read_text().replace(stamp(20), 'bad timestamp'))
        self.add('bad-creation')
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('UPDATE threads SET created_at_ms = ? WHERE id = ?', ('invalid', 'bad-creation'))
        result = self.manifest(status='incomplete')
        self.assertEqual(result['counts']['unknown'], 2)

    def test_malformed_metadata_fields_block_selection(self):
        self.add('good')
        cases = [('event_msg', {}, 'invalid_lifecycle_tag'),
                 ('event_msg', {'type': ''}, 'invalid_lifecycle_tag'),
                 ('response_item', {}, 'invalid_response_type'),
                 ('response_item', {'type': ''}, 'invalid_response_type'),
                 ('response_item', {'type': 'message'}, 'invalid_message_role'),
                 ('response_item', {'type': 'message', 'role': ''}, 'invalid_message_role')]
        for index, (kind, payload, reason) in enumerate(cases):
            path = self.add('bad-field-' + str(index))
            with path.open('a') as stream:
                stream.write(json.dumps({'type': kind, 'payload': payload}) + '\n')
            result = self.manifest(status='incomplete')
            self.assertIn(reason, [item['reason'] for item in result['unknown']])

    def test_outcome_fields_do_not_change_selection(self):
        path = self.add('good')
        original = self.manifest()
        path.write_text(path.read_text().replace('PRIVATE_OUTCOME', 'A completely different outcome'))
        self.append(path, 'agent_message')
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('UPDATE threads SET title = ?, first_user_message = ?, has_user_event = 1',
                               ('Different outcome', 'Different outcome'))
        self.assertEqual(self.manifest(), original)

    def test_legacy_catalog_columns(self):
        self.create_catalog(optional=False)
        self.add('legacy')
        self.assertEqual(self.manifest()['selected'][0]['id'], 'legacy')

    def test_changed_rollout_is_unknown(self):
        module = runpy.run_path(str(SCRIPT))
        path = self.add('changing')
        original = path.stat()
        changed = SimpleNamespace(st_size=original.st_size + 1, st_mtime_ns=original.st_mtime_ns,
                                  st_ino=original.st_ino)
        with patch.object(Path, 'stat', side_effect=[original, changed]):
            with self.assertRaisesRegex(module['MetadataError'], 'rollout_changed_during_read'):
                module['rollout_metadata']({'id': 'changing', 'rollout_path': str(path)})

    def test_unsupported_schema_and_missing_catalog_fail_without_json(self):
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('DROP TABLE threads')
        result = self.run_selector()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('unsupported threads schema', result.stderr)
        self.catalog.unlink()
        result = self.run_selector()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertFalse(self.catalog.exists())

    def test_usage_and_help(self):
        for extra in (['--count', '0'], ['--after', '2026-01-01'], ['--unknown']):
            with self.subTest(extra=extra):
                result = self.run_selector(extra=extra)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')
                self.assertIn('usage:', result.stderr)
        result = subprocess.run([sys.executable, str(SCRIPT), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, '')
        self.assertIn('standard library only', result.stdout)


if __name__ == '__main__':
    unittest.main()
