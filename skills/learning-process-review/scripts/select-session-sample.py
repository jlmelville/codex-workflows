#!/usr/bin/env python3
"""Select a fixed conversation cohort without inspecting outcome text."""

import argparse
from collections import Counter
from contextlib import closing
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sqlite3
import stat
import sys


SOURCES = ('cli', 'vscode')
ROOT_AGENTS = (None, '', '/root')
LIFECYCLE = ('task_started', 'task_complete', 'turn_aborted', 'task_failed')
UTC = timezone.utc
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)


class SelectionError(Exception):
    pass


class MetadataError(Exception):
    pass


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('timestamp must be a string')
    parsed = datetime.fromisoformat(value[:-1] + '+00:00' if value.endswith('Z') else value)
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError('timestamp requires a timezone')
    return parsed.astimezone(UTC)


def cutoff_argument(value):
    try:
        return timestamp(value)
    except (ValueError, OverflowError):
        raise argparse.ArgumentTypeError('expected an ISO timestamp with a timezone') from None


def count_argument(value):
    try:
        count = int(value)
        if count > 0:
            return count
    except ValueError:
        pass
    raise argparse.ArgumentTypeError('count must be a positive integer')


def iso(value):
    return value.isoformat().replace('+00:00', 'Z')


def catalog_rows(catalog, workspace):
    if not catalog.is_file():
        raise SelectionError('catalog must be an existing regular SQLite file')
    with closing(sqlite3.connect(catalog.as_uri() + '?mode=ro', uri=True)) as connection:
        connection.execute('PRAGMA query_only=ON')
        columns = {row[1] for row in connection.execute('PRAGMA table_info(threads)')}
        missing = {'id', 'rollout_path', 'created_at', 'source', 'cwd'} - columns
        if missing:
            raise SelectionError('unsupported threads schema; missing: ' + ', '.join(sorted(missing)))
        optional = [name if name in columns else 'NULL AS ' + name
                    for name in ('created_at_ms', 'agent_path')]
        connection.row_factory = sqlite3.Row
        query = 'SELECT id, rollout_path, created_at, source, ' + ', '.join(optional)
        return connection.execute(query + ' FROM threads WHERE cwd = ?', (workspace,)).fetchall()


def creation_time(row):
    milliseconds = row['created_at_ms']
    value = milliseconds if milliseconds is not None else row['created_at']
    if not isinstance(value, int):
        raise MetadataError('invalid_creation_timestamp')
    try:
        return EPOCH + (timedelta(milliseconds=value) if milliseconds is not None
                        else timedelta(seconds=value))
    except OverflowError:
        raise MetadataError('invalid_creation_timestamp') from None


def child_agent(value):
    if value is not None and not isinstance(value, str):
        raise MetadataError('invalid_agent_path')
    return value not in ROOT_AGENTS


def rollout_metadata(row):
    """Parse JSONL, but use only identities, roles, timestamps and lifecycle tags."""
    path_text = row['rollout_path']
    if not isinstance(path_text, str) or not Path(path_text).is_absolute():
        raise MetadataError('invalid_rollout_path')
    path = Path(path_text)
    try:
        before = path.stat()
        if not stat.S_ISREG(before.st_mode):
            raise MetadataError('rollout_not_regular_file')
        users = 0
        latest = None
        completed = None
        seen_meta = False
        with path.open(encoding='utf-8') as stream:
            for line in stream:
                record = json.loads(line)
                if not isinstance(record, dict) or not isinstance(record.get('type'), str):
                    raise MetadataError('invalid_rollout_record')
                kind = record['type']
                if kind not in ('session_meta', 'response_item', 'event_msg'):
                    continue
                payload = record.get('payload')
                if not isinstance(payload, dict):
                    raise MetadataError('invalid_rollout_payload')
                if kind == 'session_meta':
                    if payload.get('id') != row['id']:
                        raise MetadataError('rollout_identity_mismatch')
                    seen_meta = True
                    source = payload.get('source')
                    if isinstance(source, dict) and 'subagent' in source:
                        return None, 'subagent'
                    if source not in SOURCES:
                        raise MetadataError('unsupported_session_source')
                    if child_agent(payload.get('agent_path')):
                        return None, 'subagent'
                elif kind == 'response_item':
                    if not isinstance(payload.get('type'), str) or not payload['type']:
                        raise MetadataError('invalid_response_type')
                    if payload['type'] == 'message':
                        if not isinstance(payload.get('role'), str) or not payload['role']:
                            raise MetadataError('invalid_message_role')
                        users += payload['role'] == 'user'
                else:
                    tag = payload.get('type')
                    if not isinstance(tag, str) or not tag:
                        raise MetadataError('invalid_lifecycle_tag')
                    if tag in LIFECYCLE:
                        latest = tag
                        completed = timestamp(record.get('timestamp'))
                    elif tag.startswith('task_'):
                        raise MetadataError('unsupported_lifecycle_event')
        after = path.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise MetadataError('rollout_changed_during_read')
        if not seen_meta:
            raise MetadataError('missing_session_metadata')
        if not users:
            return None, 'no_user_messages'
        if latest != 'task_complete':
            return None, 'not_completed'
        return {'completed': completed, 'user_messages': users}, None
    except OSError:
        raise MetadataError('unreadable_rollout') from None
    except (ValueError, UnicodeError, OverflowError):
        raise MetadataError('invalid_jsonl_or_timestamp') from None


def select(catalog, workspace, after, count):
    rows = catalog_rows(catalog, workspace)
    excluded = Counter()
    unknown = []
    eligible = []
    identities = set()
    for row in rows:
        identity = row['id']
        if not isinstance(identity, str) or not identity or identity in identities:
            raise SelectionError('catalog contains an invalid or duplicate thread ID')
        identities.add(identity)
        try:
            if not isinstance(row['source'], str):
                raise MetadataError('invalid_catalog_source')
            if row['source'] not in SOURCES:
                excluded['source'] += 1
                continue
            if child_agent(row['agent_path']):
                excluded['subagent'] += 1
                continue
            created = creation_time(row)
            if created <= after:
                excluded['created_at_or_before_cutoff'] += 1
                continue
            metadata, reason = rollout_metadata(row)
            if reason:
                excluded[reason] += 1
            elif metadata['completed'] <= after:
                excluded['completed_at_or_before_cutoff'] += 1
            else:
                eligible.append({'id': identity, 'source': row['source'],
                                 'created_at': iso(created), 'completed_at': iso(metadata['completed']),
                                 'user_messages': metadata['user_messages'],
                                 '_order': (metadata['completed'], created, identity)})
        except MetadataError as error:
            unknown.append({'id': identity, 'reason': str(error)})
    eligible.sort(key=lambda item: item['_order'], reverse=True)
    status = 'incomplete' if unknown else ('ready' if len(eligible) >= count else 'insufficient')
    selected = [{key: value for key, value in item.items() if key != '_order'}
                for item in eligible[:count]] if status == 'ready' else []
    return {'schema_version': 1,
            'query': {'catalog': str(catalog), 'workspace': workspace, 'after': iso(after), 'count': count},
            'status': status,
            'counts': {'catalog_candidates': len(rows), 'eligible': len(eligible),
                       'excluded': sum(excluded.values()), 'unknown': len(unknown)},
            'excluded_by_reason': dict(sorted(excluded.items())),
            'unknown': sorted(unknown, key=lambda item: item['id']), 'selected': selected}


def main():
    parser = argparse.ArgumentParser(
        description='Select fresh, completed top-level cli/vscode sessions using metadata only.',
        epilog='Requires a user record and latest task_complete after the cutoff. '
               'Orders completion, creation, ID descending; incomplete metadata blocks selection. '
               'Catalog and rollouts are read-only; learning state is not accessed. '
               'JSON to stdout; diagnostics to stderr. Exit 0 ready, 1 not ready/error, 2 usage. '
               'Save this private manifest outside Git and learning state before reading outcomes; '
               'keep its IDs and completion boundaries fixed. Not an atomic cross-file snapshot. '
               'Requires Python 3.9+; standard library only.')
    parser.add_argument('--catalog', required=True, type=Path, help='explicit SQLite catalog (opened read-only)')
    parser.add_argument('--workspace', required=True, help='exact catalog cwd, expanded to an absolute path')
    parser.add_argument('--after', required=True, type=cutoff_argument, help='strict creation/completion cutoff, ISO with timezone')
    parser.add_argument('--count', required=True, type=count_argument, help='exact positive cohort size; no partial selection')
    args = parser.parse_args()
    try:
        result = select(args.catalog.expanduser().resolve(), os.path.abspath(os.path.expanduser(args.workspace)),
                        args.after, args.count)
    except (SelectionError, sqlite3.Error, OSError) as error:
        print(f'{parser.prog}: {error}', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=True))
    return 0 if result['status'] == 'ready' else 1


if __name__ == '__main__':
    if sys.version_info < (3, 9):
        print('select-session-sample.py: Python 3.9+ is required', file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
