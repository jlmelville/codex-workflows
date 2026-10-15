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
                if not isinstance(record, dict) or not isinstance(record.get('type'), str) or not record['type']:
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
        metadata = {'completed': completed, 'user_messages': users,
                    'latest_lifecycle': latest}
        if not users:
            return metadata, 'no_user_messages'
        if latest != 'task_complete':
            return metadata, 'not_completed'
        return metadata, None
    except OSError:
        raise MetadataError('unreadable_rollout') from None
    except (ValueError, UnicodeError, OverflowError):
        raise MetadataError('invalid_jsonl_or_timestamp') from None


def classify(row, after):
    """Use one eligibility decision for selection and optional explanations."""
    item = {'id': row['id']}
    try:
        if not isinstance(row['source'], str):
            raise MetadataError('invalid_catalog_source')
        if row['source'] not in SOURCES:
            return item, 'excluded', 'source'
        item['source'] = row['source']
        if child_agent(row['agent_path']):
            return item, 'excluded', 'subagent'
        created = creation_time(row)
        item['created_at'] = iso(created)
        if created <= after:
            return item, 'excluded', 'created_at_or_before_cutoff'
        metadata, reason = rollout_metadata(row)
        if metadata:
            item['user_messages'] = metadata['user_messages']
            if metadata['latest_lifecycle'] is not None:
                item['latest_lifecycle'] = metadata['latest_lifecycle']
                item['latest_lifecycle_at'] = iso(metadata['completed'])
                if metadata['latest_lifecycle'] == 'task_complete':
                    item['completed_at'] = item['latest_lifecycle_at']
        if reason:
            return item, 'excluded', reason
        if metadata['completed'] <= after:
            return item, 'excluded', 'completed_at_or_before_cutoff'
        item['_order'] = (metadata['completed'], created, row['id'])
        return item, 'eligible', None
    except MetadataError as error:
        return item, 'unknown', str(error)


def select(catalog, workspace, after, count, explain_ids=()):
    rows = catalog_rows(catalog, workspace)
    excluded = Counter()
    unknown = []
    eligible = []
    identities = set()
    explanations = dict.fromkeys(explain_ids)
    for row in rows:
        identity = row['id']
        if not isinstance(identity, str) or not identity or identity in identities:
            raise SelectionError('catalog contains an invalid or duplicate thread ID')
        identities.add(identity)
        item, status, reason = classify(row, after)
        if identity in explanations:
            explanations[identity] = {key: value for key, value in item.items() if key != '_order'}
            explanations[identity].update(status=status, reason=reason)
        if status == 'eligible':
            eligible.append(item)
        elif status == 'excluded':
            excluded[reason] += 1
        else:
            unknown.append({'id': identity, 'reason': reason})
    eligible.sort(key=lambda item: item['_order'], reverse=True)
    status = 'incomplete' if unknown else ('ready' if len(eligible) >= count else 'insufficient')
    selected = [{key: item[key] for key in ('id', 'source', 'created_at', 'completed_at', 'user_messages')}
                for item in eligible[:count]] if status == 'ready' else []
    result = {'schema_version': 1,
              'query': {'catalog': str(catalog), 'workspace': workspace, 'after': iso(after), 'count': count},
              'status': status,
              'counts': {'catalog_candidates': len(rows), 'eligible': len(eligible),
                         'excluded': sum(excluded.values()), 'unknown': len(unknown)},
              'excluded_by_reason': dict(sorted(excluded.items())),
              'unknown': sorted(unknown, key=lambda item: item['id']), 'selected': selected}
    if explanations:
        result['explanations'] = [item if item is not None else {
            'id': identity, 'status': 'unknown', 'reason': 'not_found_in_workspace'}
            for identity, item in explanations.items()]
    return result


def main():
    parser = argparse.ArgumentParser(
        description='Select fresh, completed top-level cli/vscode sessions using metadata only.',
        epilog='Requires a user record and latest task_complete after the cutoff. '
               'Orders completion, creation, ID descending; incomplete metadata blocks selection. '
               'Explanations add per-ID status, reason, and available metadata from the same pass; '
               'IDs absent from the workspace are unknown. Selection and exit status are unchanged. '
               'Catalog and rollouts are read-only; learning state is not accessed. '
               'JSON to stdout; diagnostics to stderr. Exit 0 ready, 1 not ready/error, 2 usage. '
               'Save this private manifest outside Git and learning state before reading outcomes; '
               'keep its IDs and completion boundaries fixed. Not an atomic cross-file snapshot. '
               'Requires Python 3.9+; standard library only.')
    parser.add_argument('--catalog', required=True, type=Path, help='explicit SQLite catalog (opened read-only)')
    parser.add_argument('--workspace', required=True, help='exact catalog cwd, expanded to an absolute path')
    parser.add_argument('--after', required=True, type=cutoff_argument, help='strict creation/completion cutoff, ISO with timezone')
    parser.add_argument('--count', required=True, type=count_argument, help='exact positive cohort size; no partial selection')
    parser.add_argument('--explain-id', action='append', default=[], metavar='ID',
                        help='explain one ID in JSON; repeatable, duplicates collapsed in request order')
    args = parser.parse_args()
    if any(not identity.strip() for identity in args.explain_id):
        parser.error('--explain-id requires a nonempty ID')
    try:
        result = select(args.catalog.expanduser().resolve(), os.path.abspath(os.path.expanduser(args.workspace)),
                        args.after, args.count, args.explain_id)
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
