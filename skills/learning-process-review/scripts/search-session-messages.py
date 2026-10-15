#!/usr/bin/env python3
"""Search local transcript message text without changing inputs or learning state."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


class ReadError(Exception):
    def __init__(self, reason, line=None):
        super().__init__(reason)
        self.reason = reason
        self.line = line


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('timestamp must be a string')
    result = datetime.fromisoformat(value[:-1] + '+00:00' if value.endswith('Z') else value)
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError('timestamp requires a timezone')
    return result.astimezone(timezone.utc)


def before_argument(value):
    try:
        return timestamp(value)
    except (ValueError, OverflowError):
        raise argparse.ArgumentTypeError('expected an ISO timestamp with a timezone') from None


def positive_argument(value):
    try:
        result = int(value)
        if result > 0:
            return result
    except ValueError:
        pass
    raise argparse.ArgumentTypeError('expected a positive integer')


def transcript_name(path):
    return path.name.endswith(('.jsonl', '.jsonl.zst'))


def discover(inputs, errors):
    files = set()
    for value in inputs:
        path = Path(value).expanduser().absolute()
        try:
            mode = path.stat().st_mode
            if stat.S_ISREG(mode) and transcript_name(path):
                files.add(path.resolve())
            elif stat.S_ISDIR(mode):
                found = False
                error_count = len(errors)

                def onerror(error):
                    errors.append({'file': str(error.filename), 'reason': 'directory_scan_failed'})

                for directory, dirs, names in os.walk(path, onerror=onerror, followlinks=False):
                    dirs.sort()
                    for name in sorted(names):
                        candidate = Path(directory) / name
                        if transcript_name(candidate) and not candidate.is_symlink():
                            files.add(candidate.resolve())
                            found = True
                if not found and len(errors) == error_count:
                    errors.append({'file': str(path), 'reason': 'no_transcripts_found'})
            else:
                errors.append({'file': str(path), 'reason': 'unsupported_input'})
        except OSError:
            errors.append({'file': str(path), 'reason': 'input_unreadable'})
    return sorted(files)


@contextmanager
def transcript_lines(path):
    if path.name.endswith('.jsonl.zst'):
        executable = shutil.which('zstd')
        if executable is None:
            raise ReadError('zstd_unavailable')
        process = subprocess.Popen([executable, '-d', '-c', '-q', '--', str(path)],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   text=True, encoding='utf-8')
        try:
            yield process.stdout
            if process.wait() != 0:
                raise ReadError('decompression_failed')
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.kill()
            process.wait()
    else:
        with path.open(encoding='utf-8') as stream:
            yield stream


def message_text(content):
    if not isinstance(content, list):
        raise ReadError('invalid_message_content')
    texts = []
    for block in content:
        if not isinstance(block, dict):
            raise ReadError('invalid_content_block')
        kind = block.get('type')
        if kind in ('input_text', 'output_text', 'text', 'refusal'):
            value = block.get('refusal' if kind == 'refusal' else 'text')
            if not isinstance(value, str):
                raise ReadError('invalid_text_block')
            texts.append(value)
        elif kind not in ('input_image', 'output_image', 'input_audio', 'output_audio', 'audio'):
            raise ReadError('unsupported_content_type')
    return '\n'.join(texts)


def excerpt(text, match, maximum):
    start = max(0, match.start() - maximum // 3) if match is not None else 0
    end = min(len(text), start + maximum)
    return {'excerpt': text[start:end], 'start': start, 'end': end,
            'clipped': start > 0 or end < len(text)}


def search(inputs, pattern=None, role='both', before=None, limit=20, max_chars=800):
    errors = []
    files = discover(inputs, errors)
    matches = []
    counts = {'files_scanned': 0, 'messages_scanned': 0, 'matched_messages': 0}
    for path in files:
        canonical = 0
        try:
            initial = path.stat()
            if not stat.S_ISREG(initial.st_mode):
                raise ReadError('transcript_not_regular_file')
            counts['files_scanned'] += 1
            with transcript_lines(path) as stream:
                for line_number, line in enumerate(stream, 1):
                    try:
                        try:
                            record = json.loads(line)
                        except ValueError:
                            raise ReadError('invalid_jsonl') from None
                        if not isinstance(record, dict) or not isinstance(record.get('type'), str) or not record['type']:
                            raise ReadError('invalid_record')
                        if record['type'] != 'response_item':
                            payload = record.get('payload')
                            if record['type'] != 'event_msg' and isinstance(payload, dict) and (
                                    payload.get('type') == 'message' or payload.get('role') in ('user', 'assistant')):
                                raise ReadError('unsupported_message_record')
                            continue
                        payload = record.get('payload')
                        if not isinstance(payload, dict) or not isinstance(payload.get('type'), str) or not payload['type']:
                            raise ReadError('invalid_response_item')
                        if payload['type'] != 'message':
                            continue
                        message_role = payload.get('role')
                        if message_role in ('system', 'developer', 'tool'):
                            continue
                        if message_role not in ('user', 'assistant'):
                            raise ReadError('unsupported_message_role')
                        canonical += 1
                        counts['messages_scanned'] += 1
                        try:
                            at = timestamp(record.get('timestamp'))
                        except (ValueError, OverflowError):
                            raise ReadError('invalid_message_timestamp') from None
                        if (before is not None and at > before) or role not in ('both', message_role):
                            continue
                        text = message_text(payload.get('content'))
                        match = pattern.search(text) if pattern is not None else None
                        if not text or (pattern is not None and match is None):
                            continue
                        counts['matched_messages'] += 1
                        if len(matches) < limit:
                            matches.append({'file': str(path), 'line': line_number,
                                            'timestamp': at.isoformat().replace('+00:00', 'Z'),
                                            'role': message_role, **excerpt(text, match, max_chars)})
                    except ReadError as error:
                        error.line = line_number
                        raise
            final = path.stat()
            if (initial.st_size, initial.st_mtime_ns, initial.st_ino) != (final.st_size, final.st_mtime_ns, final.st_ino):
                raise ReadError('transcript_changed_during_read')
            if not canonical:
                raise ReadError('no_supported_message_records')
        except ReadError as error:
            item = {'file': str(path), 'reason': error.reason}
            if error.line is not None:
                item['line'] = error.line
            errors.append(item)
        except UnicodeError:
            errors.append({'file': str(path), 'reason': 'invalid_utf8'})
        except OSError:
            errors.append({'file': str(path), 'reason': 'transcript_unreadable'})
    return {'schema_version': 1, 'status': 'incomplete' if errors else 'complete',
            'counts': counts, 'truncated': counts['matched_messages'] > len(matches),
            'matches': matches, 'errors': errors}


def main():
    parser = argparse.ArgumentParser(
        description='Search user/assistant messages in explicit local JSONL or JSONL.zst inputs.',
        epilog='Directories recurse without following symlinks; files are deduplicated and sorted by path, '
               'then read in line order. Uses canonical response_item messages; event mirrors are ignored '
               'and repeated messages retained. Text blocks join with newline; excerpt whitespace is preserved. '
               'All files are scanned even after the global output limit; partial results carry errors. '
               'JSON stdout. Exit 0 complete (including no hits), 1 incomplete, 2 usage on stderr. '
               'Python 3.9+; zstd is needed only for compressed inputs. Transcripts and learning state '
               'are read-only. Keep private output outside Git and learning state; sanitize saved evidence.')
    parser.add_argument('inputs', nargs='+', metavar='PATH', help='explicit transcript files or directories')
    parser.add_argument('--pattern', help='optional Python regex; (?i) ignores case; omit for message excerpts')
    parser.add_argument('--role', choices=('user', 'assistant', 'both'), default='both', help='message roles (default: both)')
    parser.add_argument('--before', type=before_argument, help='inclusive ISO timestamp with timezone')
    parser.add_argument('--limit', type=positive_argument, default=20, help='global returned-message limit (default: 20)')
    parser.add_argument('--max-chars', type=positive_argument, default=800, help='characters per excerpt (default: 800)')
    args = parser.parse_args()
    try:
        pattern = re.compile(args.pattern) if args.pattern is not None else None
    except re.error:
        parser.error('--pattern requires a valid Python regex')
    result = search(args.inputs, pattern, args.role, args.before, args.limit, args.max_chars)
    print(json.dumps(result, indent=2, ensure_ascii=True))
    return 0 if result['status'] == 'complete' else 1


if __name__ == '__main__':
    if sys.version_info < (3, 9):
        print('search-session-messages.py: Python 3.9+ is required', file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
