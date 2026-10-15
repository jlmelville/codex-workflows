#!/usr/bin/env python3
"""Exercise bounded transcript searches using disposable plain and compressed logs."""

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/learning-process-review/scripts/search-session-messages.py'
AT = '2026-01-01T00:00:00Z'
ZSTD = shutil.which('zstd')


def message(text, role='user', at=AT):
    return {'type': 'response_item', 'timestamp': at, 'payload': {
        'type': 'message', 'role': role, 'content': [{'type': 'input_text', 'text': text}]}}


class SessionMessageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='session-messages-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state = self.root / 'learning-state'
        self.state.mkdir()
        (self.state / 'sentinel').write_text('PRIVATE_STATE\n')

    def write(self, name, records):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(''.join(json.dumps(record) + '\n' for record in records))
        return path

    def snapshot(self):
        result = {}
        for path in self.root.rglob('*'):
            key = str(path.relative_to(self.root))
            result[key] = (('link', os.readlink(path)) if path.is_symlink() else
                           ('dir', None) if path.is_dir() else ('file', path.read_bytes()))
        return result

    def run_search(self, paths, extra=(), env=None):
        before = self.snapshot()
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, paths), *extra],
                                capture_output=True, text=True, timeout=15,
                                env={**os.environ, 'CODEX_WORKFLOWS_STATE_DIR': str(self.state), **(env or {})})
        self.assertEqual(self.snapshot(), before, 'search changed transcripts or learning state')
        self.assertNotIn('Traceback', result.stderr)
        self.assertNotIn('PRIVATE_STATE', result.stdout + result.stderr)
        self.assertNotIn('PRIVATE_TOOL', result.stdout + result.stderr)
        return result

    def report(self, paths, extra=(), status='complete', env=None):
        result = self.run_search(paths, extra, env)
        self.assertEqual(result.returncode, 0 if status == 'complete' else 1, result.stderr)
        self.assertEqual(result.stderr, '')
        document = json.loads(result.stdout)
        self.assertEqual(document['status'], status)
        self.assertEqual(bool(document['errors']), status == 'incomplete')
        return document

    def test_roles_mirrors_and_genuine_repeats(self):
        path = self.write('roles.jsonl', [
            {'type': 'session_meta', 'payload': {'id': 'opaque'}},
            {'type': 'event_msg', 'payload': {'type': 'user_message', 'message': 'repeat'}},
            message('repeat'), message('repeat'), message('answer', 'assistant'),
            message('PRIVATE_TOOL', 'developer'), message('PRIVATE_TOOL', 'system'),
            {'type': 'response_item', 'payload': {'type': 'reasoning', 'text': 'PRIVATE_TOOL'}},
            {'type': 'response_item', 'payload': {'type': 'function_call_output', 'output': 'PRIVATE_TOOL'}},
            {'type': 'event_msg', 'payload': {'type': 'agent_message', 'message': 'answer'}}])
        result = self.report([path])
        self.assertEqual(result['counts'], {'files_scanned': 1, 'messages_scanned': 3, 'matched_messages': 3})
        self.assertEqual([item['excerpt'] for item in result['matches']], ['repeat', 'repeat', 'answer'])
        self.assertEqual([item['line'] for item in result['matches']], [3, 4, 5])
        self.assertEqual(len(self.report([path], ['--role', 'user'])['matches']), 2)
        self.assertEqual(self.report([path], ['--role', 'assistant'])['matches'][0]['excerpt'], 'answer')

    def test_regex_excerpt_offsets_and_whitespace(self):
        text = 'é' * 60 + '\n\tKEEP  spacing\n' + 'z' * 60
        path = self.write('excerpt.jsonl', [message(text)])
        result = self.report([path], ['--pattern', '(?i)keep', '--max-chars', '30'])
        item = result['matches'][0]
        self.assertEqual(item['excerpt'], text[item['start']:item['end']])
        self.assertEqual(len(item['excerpt']), 30)
        self.assertIn('\n\tKEEP  spacing\n', item['excerpt'])
        self.assertTrue(item['clipped'])
        self.assertEqual(item['timestamp'], AT)
        self.assertEqual(item['file'], str(path))

    def test_global_limit_ordering_and_overlapping_inputs(self):
        first = self.write('logs/a.jsonl', [message('first'), message('second')])
        last = self.write('logs/b.jsonl', [message('third'), message('fourth')])
        result = self.report([last, first, first.parent, first], ['--limit', '3'])
        self.assertEqual([item['excerpt'] for item in result['matches']], ['first', 'second', 'third'])
        self.assertEqual(result['counts'], {'files_scanned': 2, 'messages_scanned': 4, 'matched_messages': 4})
        self.assertTrue(result['truncated'])
        self.assertFalse(self.report([first], ['--limit', '2'])['truncated'])

    def test_inclusive_cutoff_and_filter_before_content_extraction(self):
        later = message('PRIVATE_AFTER_CUTOFF', at='2026-01-01T00:00:00.001Z')
        later['payload']['content'] = 'outside the requested boundary'
        path = self.write('cutoff.jsonl', [message('before', at='2025-12-31T23:59:59Z'),
                                         message('equal', at='2026-01-01T01:00:00+01:00'), later])
        result = self.report([path], ['--before', AT])
        self.assertEqual([item['excerpt'] for item in result['matches']], ['before', 'equal'])
        self.assertEqual(result['matches'][1]['timestamp'], AT)
        self.assertEqual(result['counts']['messages_scanned'], 3)

    def test_no_hits_is_complete(self):
        path = self.write('no-hits.jsonl', [message('ordinary text')])
        result = self.report([path], ['--pattern', 'absent'])
        self.assertEqual(result['matches'], [])
        self.assertEqual(result['counts']['matched_messages'], 0)
        self.assertFalse(result['truncated'])

    def test_text_blocks_and_nontext_content(self):
        record = message('unused')
        record['payload']['content'] = [{'type': 'input_image', 'image_url': 'PRIVATE_TOOL'},
                                        {'type': 'text', 'text': 'first\n'},
                                        {'type': 'output_text', 'text': 'second'},
                                        {'type': 'refusal', 'refusal': 'declined'}]
        path = self.write('blocks.jsonl', [record])
        self.assertEqual(self.report([path])['matches'][0]['excerpt'], 'first\n\nsecond\ndeclined')

    def test_malformed_records_and_unsupported_messages_are_incomplete(self):
        cases = [({}, 'invalid_record'), ({'type': ''}, 'invalid_record'),
                 ({'type': 'response_item', 'payload': {}}, 'invalid_response_item'),
                 ({'type': 'response_item', 'payload': {'type': ''}}, 'invalid_response_item'),
                 ({'type': 'new_kind', 'payload': {'type': 'message'}}, 'unsupported_message_record')]
        for field, value, reason in [('role', 'new-role', 'unsupported_message_role'),
                                     ('content', 'wrong', 'invalid_message_content'),
                                     ('content', [None], 'invalid_content_block'),
                                     ('content', [{'type': 'new_text'}], 'unsupported_content_type'),
                                     ('content', [{'type': 'input_text', 'text': 1}], 'invalid_text_block')]:
            record = message('valid')
            record['payload'][field] = value
            cases.append((record, reason))
        record = message('valid', at='missing timezone')
        cases.append((record, 'invalid_message_timestamp'))
        for index, (record, reason) in enumerate(cases):
            with self.subTest(reason=reason, index=index):
                path = self.write('bad-' + str(index) + '.jsonl', [message('valid prefix'), record])
                result = self.report([path], status='incomplete')
                self.assertEqual(result['errors'], [{'file': str(path), 'line': 2, 'reason': reason}])

    def test_errors_after_limit_and_invalid_utf8_are_reported(self):
        path = self.write('truncated.jsonl', [message('first'), message('second')])
        with path.open('a') as stream:
            stream.write('{PRIVATE_TOOL\n')
        result = self.report([path], ['--limit', '1'], status='incomplete')
        self.assertEqual(result['errors'][0]['reason'], 'invalid_jsonl')
        self.assertEqual(result['errors'][0]['line'], 3)
        self.assertTrue(result['truncated'])
        path.write_bytes(b'\xff')
        self.assertEqual(self.report([path], status='incomplete')['errors'][0]['reason'], 'invalid_utf8')

    def test_event_only_and_empty_files_are_diagnostic(self):
        for name, records in [('events', [{'type': 'event_msg', 'payload': {
                'type': 'user_message', 'message': 'legacy text'}}]), ('empty', [])]:
            path = self.write(name + '.jsonl', records)
            result = self.report([path], status='incomplete')
            self.assertEqual(result['errors'][0]['reason'], 'no_supported_message_records')

    def test_discovery_errors_and_directory_symlinks(self):
        path = self.write('logs/good.jsonl', [message('in scope')])
        other = self.write('elsewhere/private.jsonl', [message('not in scope')])
        (path.parent / 'linked.jsonl').symlink_to(other)
        (path.parent / 'linked-dir').symlink_to(other.parent, target_is_directory=True)
        self.assertEqual([item['excerpt'] for item in self.report([path.parent])['matches']], ['in scope'])
        self.assertEqual(self.report([path, path.parent / 'linked.jsonl'])['counts']['files_scanned'], 2)
        empty = self.root / 'empty-directory'
        empty.mkdir()
        unsupported = self.root / 'unsupported.txt'
        unsupported.write_text('unused')
        result = self.report([path, empty, unsupported, self.root / 'missing.jsonl'], status='incomplete')
        self.assertEqual({item['reason'] for item in result['errors']}, {
            'no_transcripts_found', 'unsupported_input', 'input_unreadable'})
        self.assertEqual(len(result['matches']), 1)

    def test_missing_zstd_is_explicit_and_plain_inputs_still_work(self):
        plain = self.write('a.jsonl', [message('plain')])
        compressed = self.root / 'b.jsonl.zst'
        compressed.write_bytes(b'unread without zstd')
        result = self.report([plain, compressed], status='incomplete', env={'PATH': ''})
        self.assertEqual(result['errors'], [{'file': str(compressed), 'reason': 'zstd_unavailable'}])
        self.assertEqual(result['matches'][0]['excerpt'], 'plain')

    @unittest.skipUnless(ZSTD, 'optional zstd executable is unavailable')
    def test_real_compression_and_corrupt_frame(self):
        plain = self.write('log ? #[x].jsonl', [message('compressed text'), message('answer', 'assistant')])
        compressed = plain.with_suffix('.jsonl.zst')
        compressed.write_bytes(subprocess.run([ZSTD, '-q', '-c', '--', str(plain)],
                                             capture_output=True, check=True).stdout)
        original = self.report([plain])
        result = self.report([compressed])
        for item in result['matches']:
            item['file'] = str(plain)
        self.assertEqual(result, original)
        compressed.write_bytes(compressed.read_bytes()[:-3])
        result = self.report([compressed], status='incomplete')
        self.assertEqual(result['errors'][0]['reason'], 'decompression_failed')

    def test_changed_file_is_incomplete(self):
        module = runpy.run_path(str(SCRIPT))
        path = self.write('changing.jsonl', [message('read')])
        original = path.stat()
        changed = SimpleNamespace(st_size=original.st_size + 1, st_mtime_ns=original.st_mtime_ns,
                                  st_ino=original.st_ino)
        with patch.dict(module['search'].__globals__, {'discover': lambda inputs, errors: [path]}):
            with patch.object(Path, 'stat', side_effect=[original, changed]):
                result = module['search']([path])
        self.assertEqual(result['status'], 'incomplete')
        self.assertEqual(result['errors'][0]['reason'], 'transcript_changed_during_read')

    def test_usage_and_help(self):
        path = self.write('usage.jsonl', [message('valid')])
        for extra in (['--pattern', '['], ['--limit', '0'], ['--max-chars', '-1'],
                      ['--before', '2026-01-01'], ['--role', 'tool']):
            with self.subTest(extra=extra):
                result = self.run_search([path], extra)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')
                self.assertIn('usage:', result.stderr)
        result = subprocess.run([sys.executable, str(SCRIPT), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, '')
        self.assertIn('--max-chars', result.stdout)
        self.assertIn('read-only', result.stdout)


if __name__ == '__main__':
    unittest.main()
