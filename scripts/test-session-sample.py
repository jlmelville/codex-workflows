#!/usr/bin/env python3
"""Exercise metadata selection and read-only behavior using synthetic inputs."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import runpy
import sqlite3
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


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
                                capture_output=True, text=True, timeout=15,
                                env={**os.environ, 'CODEX_WORKFLOWS_STATE_DIR': str(self.root / 'learning-state')})
        after = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(after, before, 'selector wrote catalog, rollouts, or learning state')
        self.assertNotIn('Traceback', result.stderr)
        self.assertNotIn('PRIVATE_OUTCOME', result.stdout + result.stderr)
        return result

    def manifest(self, count=1, status='ready', extra=()):
        result = self.run_selector(count, extra)
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

    def test_empty_record_type_blocks_completed_session(self):
        path = self.add('empty-kind')
        with path.open('a') as stream:
            stream.write(json.dumps({'type': 'turn_context', 'payload': {}}) + '\n')
        self.manifest()
        with path.open('a') as stream:
            stream.write(json.dumps({'type': ''}) + '\n')
        result = self.manifest(status='incomplete', extra=['--explain-id', 'empty-kind'])
        self.assertEqual(result['counts'], {'catalog_candidates': 1, 'eligible': 0, 'excluded': 0, 'unknown': 1})
        self.assertEqual(result['unknown'], [{'id': 'empty-kind', 'reason': 'invalid_rollout_record'}])
        self.assertEqual(result['explanations'][0]['status'], 'unknown')
        self.assertEqual(result['explanations'][0]['reason'], 'invalid_rollout_record')

    def test_outcome_fields_do_not_change_selection(self):
        path = self.add('good')
        original = self.manifest()
        explained = self.manifest(extra=['--explain-id', 'good'])
        path.write_text(path.read_text().replace('PRIVATE_OUTCOME', 'A completely different outcome'))
        self.append(path, 'agent_message')
        with sqlite3.connect(self.catalog) as connection:
            connection.execute('UPDATE threads SET title = ?, first_user_message = ?, has_user_event = 1',
                               ('Different outcome', 'Different outcome'))
        self.assertEqual(self.manifest(), original)
        self.assertEqual(self.manifest(extra=['--explain-id', 'good']), explained)

    def test_explanations_report_eligibility_without_changing_selection(self):
        self.add('good')
        self.add('other-eligible', completed=30)
        self.add('old-reopened', created=-1000).unlink()
        self.add('completed-equal', completed=0)
        self.add('source-child', source='PRIVATE_OUTCOME').unlink()
        self.add('catalog-child', agent_path='/root/PRIVATE_OUTCOME').unlink()
        self.add('rollout-child', meta_source={'subagent': {'other': 'PRIVATE_OUTCOME'}})
        self.add('no-users', users=0)
        self.append(self.add('failed'), 'task_failed')
        self.add('no-lifecycle').write_text('\n'.join(json.dumps(record) for record in [
            {'type': 'session_meta', 'payload': {'id': 'no-lifecycle', 'source': 'cli'}},
            {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user'}}]) + '\n')
        self.add('malformed').write_text('{PRIVATE_OUTCOME')
        self.add('other-workspace', workspace=self.workspace + '-other').unlink()
        original = self.manifest(status='incomplete')
        requested = ['failed', 'good', 'source-child', 'old-reopened', 'catalog-child',
                     'rollout-child', 'no-users', 'no-lifecycle', 'completed-equal',
                     'malformed', 'missing', 'other-workspace', 'failed']
        extra = [value for identity in requested for value in ('--explain-id', identity)]
        result = self.manifest(status='incomplete', extra=extra)
        explanations = result.pop('explanations')
        self.assertEqual(result, original)
        self.assertEqual([item['id'] for item in explanations], list(dict.fromkeys(requested)))
        items = {item['id']: item for item in explanations}
        self.assertEqual(items['good'], {
            'id': 'good', 'source': 'cli', 'created_at': stamp(1), 'completed_at': stamp(10),
            'user_messages': 1, 'latest_lifecycle': 'task_complete',
            'latest_lifecycle_at': stamp(10), 'status': 'eligible', 'reason': None})
        for identity, reason in [('source-child', 'source'), ('catalog-child', 'subagent'),
                                 ('rollout-child', 'subagent'), ('no-users', 'no_user_messages'),
                                 ('no-lifecycle', 'not_completed'), ('failed', 'not_completed'),
                                 ('old-reopened', 'created_at_or_before_cutoff'),
                                 ('completed-equal', 'completed_at_or_before_cutoff')]:
            self.assertEqual((items[identity]['status'], items[identity]['reason']), ('excluded', reason))
        self.assertEqual(items['failed']['latest_lifecycle'], 'task_failed')
        self.assertEqual(items['failed']['latest_lifecycle_at'], stamp(20))
        self.assertNotIn('completed_at', items['failed'])
        self.assertEqual(items['no-users']['user_messages'], 0)
        self.assertNotIn('latest_lifecycle', items['no-lifecycle'])
        self.assertNotIn('source', items['source-child'])
        self.assertNotIn('user_messages', items['old-reopened'])
        for identity in ('missing', 'other-workspace'):
            self.assertEqual(items[identity], {
                'id': identity, 'status': 'unknown', 'reason': 'not_found_in_workspace'})
        self.assertEqual(items['malformed']['reason'], 'invalid_jsonl_or_timestamp')
        self.assertEqual(items['malformed']['status'], 'unknown')

    def test_explanations_preserve_ready_and_insufficient_cohorts(self):
        self.add('a')
        self.add('b', completed=20)
        extra = ['--explain-id', 'a', '--explain-id', 'absent']
        for count, status in ((1, 'ready'), (3, 'insufficient')):
            with self.subTest(status=status):
                original = self.manifest(count, status)
                result = self.manifest(count, status, extra)
                explanations = result.pop('explanations')
                self.assertEqual(result, original)
                self.assertEqual(explanations[0]['status'], 'eligible')
                self.assertEqual(explanations[1]['reason'], 'not_found_in_workspace')
        self.assertEqual(self.manifest()['selected'][0]['id'], 'b')

    def test_explanations_do_not_reread_or_expand_rollout_access(self):
        module = runpy.run_path(str(SCRIPT))
        self.add('good')
        self.append(self.add('active'), 'task_started')
        self.add('old', created=-1000).unlink()
        self.add('child', agent_path='/root/child').unlink()
        self.add('elsewhere', workspace=self.workspace + '-other').unlink()
        reader = Mock(wraps=module['rollout_metadata'])
        args = (self.catalog, self.workspace, module['timestamp'](CUTOFF), 3)
        with patch.dict(module['classify'].__globals__, {'rollout_metadata': reader}):
            original = module['select'](*args)
            calls = [call.args[0]['id'] for call in reader.call_args_list]
            reader.reset_mock()
            explained = module['select'](*args, explain_ids=['good', 'active', 'old', 'child', 'elsewhere'])
            self.assertEqual([call.args[0]['id'] for call in reader.call_args_list], calls)
        self.assertEqual(set(calls), {'good', 'active'})
        explained.pop('explanations')
        self.assertEqual(explained, original)

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
        for extra in (['--count', '0'], ['--after', '2026-01-01'], ['--unknown'],
                      ['--explain-id', ''], ['--explain-id', ' '], ['--explain-id']):
            with self.subTest(extra=extra):
                result = self.run_selector(extra=extra)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')
                self.assertIn('usage:', result.stderr)
        result = subprocess.run([sys.executable, str(SCRIPT), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, '')
        self.assertIn('standard library only', result.stdout)
        self.assertIn('--explain-id ID', result.stdout)


if __name__ == '__main__':
    unittest.main()
