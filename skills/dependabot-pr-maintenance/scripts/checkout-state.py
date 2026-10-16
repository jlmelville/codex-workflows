#!/usr/bin/env python3
"""Discover, snapshot or compare Git checkouts without writing to them."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


ENV = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
ENV.update(GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0', LC_ALL='C')
FIELDS = {'head', 'branch', 'refs', 'stashes', 'indexes', 'tracked', 'untracked'}
OID = re.compile(r'(?:[0-9a-f]{40}|[0-9a-f]{64})\Z')
SHA256 = re.compile(r'[0-9a-f]{64}\Z')


def checkout_marker(marker):
    mode = marker.lstat().st_mode
    if stat.S_ISDIR(mode):
        kind, git_dir = 'directory', marker
    elif stat.S_ISREG(mode):
        with marker.open('rb') as stream:
            content = stream.read(65537)
        if len(content) > 65536:
            raise ValueError('gitfile exceeds 64 KiB')
        if not content.startswith(b'gitdir: '):
            raise ValueError('expected gitdir: path in gitfile')
        target = content[8:].rstrip(b'\r\n')
        if not target or b'\0' in target:
            raise ValueError('empty or invalid gitfile target')
        kind, git_dir = 'gitfile', marker.parent / os.fsdecode(target)
    else:
        raise ValueError('expected a .git directory or regular gitfile; marker symlinks are skipped')
    try:
        if not stat.S_ISREG((git_dir / 'HEAD').stat().st_mode):
            raise ValueError('expected a regular HEAD file in Git directory')
    except (FileNotFoundError, NotADirectoryError):
        raise ValueError('Git directory or HEAD file is missing') from None
    return kind


def discover(paths):
    result = {'roots': [], 'candidates': [], 'rejected_markers': [], 'errors': []}
    roots = set()
    for raw in sorted(set(paths)):
        try:
            root = Path(raw).expanduser().resolve(strict=True)
            if not root.is_dir():
                raise ValueError('expected a directory root')
            roots.add(str(root))
        except (OSError, ValueError, RuntimeError) as error:
            result['errors'].append({'path': raw, 'reason': str(error)})
    result['roots'] = sorted(roots)
    pending, visited = list(reversed(result['roots'])), set()
    while pending:
        directory = pending.pop()
        if directory in visited:
            continue
        visited.add(directory)
        try:
            with os.scandir(directory) as stream:
                entries = sorted(stream, key=lambda entry: entry.name)
            for entry in entries:
                try:
                    if entry.name == '.git':
                        kind = checkout_marker(Path(entry.path))
                        result['candidates'].append({'path': directory, 'marker': kind})
                    elif entry.is_dir(follow_symlinks=False):
                        pending.append(entry.path)
                except ValueError as error:
                    result['rejected_markers'].append({'path': entry.path, 'reason': str(error)})
                except OSError as error:
                    result['errors'].append({'path': entry.path, 'reason': str(error)})
        except OSError as error:
            result['errors'].append({'path': directory, 'reason': str(error)})
    for field in ('candidates', 'rejected_markers', 'errors'):
        result[field].sort(key=lambda entry: (entry['path'], entry.get('reason', '')))
    return result


def git(root, *args, accepted=(0,)):
    result = subprocess.run(
        ['git', '-c', 'diff.autoRefreshIndex=false', '-c', 'core.fsmonitor=false',
         '-C', str(root), *args], env=ENV, capture_output=True, timeout=45,
    )
    if result.returncode not in accepted:
        detail = os.fsdecode(result.stderr).strip()
        raise ValueError(f'git {args[0]} failed ({result.returncode}): {detail}')
    return result.stdout


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def file_entry(path, missing=False):
    try:
        before = path.lstat()
    except FileNotFoundError:
        if missing:
            return {'kind': 'missing'}
        raise
    if stat.S_ISLNK(before.st_mode):
        entry = {'kind': 'symlink', 'target': os.readlink(path)}
    elif stat.S_ISREG(before.st_mode):
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            if signature(os.fstat(stream.fileno())) != signature(before):
                raise ValueError(f'file changed during inspection: {path}')
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        entry = {'kind': 'file', 'sha256': digest.hexdigest(),
                 'mode': stat.S_IMODE(before.st_mode)}
    else:
        raise ValueError(f'unsupported directory or special file: {path}')
    if signature(path.lstat()) != signature(before):
        raise ValueError(f'file changed during inspection: {path}')
    return entry


def inventory(root, names, missing=False):
    entries = []
    for name in sorted(set(names)):
        relative = Path(os.fsdecode(name))
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('invalid Git file path')
        # Refuse intermediate symlinks rather than following them outside the checkout.
        if any(parent.is_symlink() for parent in (root / relative).parents if parent != root
               and root in parent.parents):
            raise ValueError(f'symlink parent: {relative}')
        entries.append([os.fsdecode(name), file_entry(root / relative, missing)])
    payload = json.dumps(entries, ensure_ascii=True, separators=(',', ':')).encode('ascii')
    return {'files': len(entries), 'sha256': hashlib.sha256(payload).hexdigest()}


def index_state(index):
    # Even read-only Git index queries freshen shared-index mtimes. Refuse the layout
    # using filesystem inspection, including leftovers, before Git can read the index.
    if next(index.parent.glob('sharedindex.*'), None) is not None:
        raise ValueError('shared-index layouts are unsupported for read-only inspection (sharedindex.* files found)')
    entry = file_entry(index, missing=True)
    if entry['kind'] not in ('file', 'missing'):
        raise ValueError(f'unsupported index symlink: {index}')
    return {str(index): entry.get('sha256')}


def snapshot(root):
    top = Path(os.fsdecode(git(root, 'rev-parse', '--show-toplevel')).removesuffix('\n')).resolve(strict=True)
    if top != root:
        raise ValueError('expected a checkout root, not a subdirectory')
    index = Path(os.fsdecode(git(root, 'rev-parse', '--git-path', 'index')).removesuffix('\n'))
    index = (root / index).absolute()
    before = index_state(index)
    tracked = []
    for record in git(root, 'ls-files', '--stage', '-z').split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            if metadata.split()[0] == b'160000':
                raise ValueError('submodules are outside this helper\'s scope')
            tracked.append(name)
    untracked = [name for name in git(root, 'ls-files', '--others', '--exclude-standard', '-z')
                 .split(b'\0') if name]
    refs = {}
    for line in git(root, 'for-each-ref', '--format=%(refname) %(objectname)',
                    'refs/heads', 'refs/tags', 'refs/remotes', 'refs/stash').splitlines():
        name, oid = os.fsdecode(line).split(' ', 1)
        refs[name] = oid
    stashes = []
    if 'refs/stash' in refs:
        stashes = git(root, 'reflog', 'show', '--no-show-signature', '--no-notes',
                      '--format=%H', 'refs/stash').decode('ascii').splitlines()
    result = {
        'path': str(root),
        'head': git(root, 'rev-parse', '--verify', '--quiet', 'HEAD', accepted=(0, 1))
        .decode('ascii').strip() or None,
        'branch': os.fsdecode(git(root, 'symbolic-ref', '--quiet', 'HEAD', accepted=(0, 1))).strip() or None,
        'refs': refs, 'stashes': stashes, 'indexes': before,
        'tracked': inventory(root, tracked, missing=True),
        'untracked': inventory(root, untracked),
    }
    if index_state(index) != before:
        raise ValueError('index changed during inspection')
    return result


def valid_record(record):
    if not isinstance(record, dict) or set(record) != FIELDS | {'path'}:
        return False
    if not isinstance(record['path'], str) or not Path(record['path']).is_absolute():
        return False
    if record['head'] is not None and not (isinstance(record['head'], str) and OID.fullmatch(record['head'])):
        return False
    if record['branch'] is not None and not (
            isinstance(record['branch'], str) and record['branch'].startswith('refs/')):
        return False
    for field in ('refs', 'indexes'):
        values = record[field]
        if not isinstance(values, dict) or (field == 'indexes' and not values):
            return False
        for key, value in values.items():
            if field == 'refs':
                if (not key.startswith(('refs/heads/', 'refs/tags/', 'refs/remotes/', 'refs/stash'))
                        or not isinstance(value, str) or not OID.fullmatch(value)):
                    return False
            elif (not Path(key).is_absolute() or (value is not None and not (
                    isinstance(value, str) and SHA256.fullmatch(value)))):
                return False
    if not isinstance(record['stashes'], list) or any(
            not isinstance(value, str) or not OID.fullmatch(value) for value in record['stashes']):
        return False
    for field in ('tracked', 'untracked'):
        value = record[field]
        if (not isinstance(value, dict) or set(value) != {'files', 'sha256'}
                or type(value['files']) is not int or value['files'] < 0
                or not isinstance(value['sha256'], str) or not SHA256.fullmatch(value['sha256'])):
            return False
    return True


def baseline(stream):
    data = json.load(stream)
    if (not isinstance(data, dict) or type(data.get('schema_version')) is not int
            or data['schema_version'] != 1 or data.get('operation') != 'snapshot'
            or data.get('status') != 'complete' or data.get('errors') != []
            or not isinstance(data.get('checkouts'), list) or not data['checkouts']
            or not all(valid_record(record) for record in data['checkouts'])):
        raise ValueError('expected a complete version 1 checkout snapshot')
    paths = [record['path'] for record in data['checkouts']]
    if len(set(paths)) != len(paths):
        raise ValueError('snapshot contains duplicate checkout paths')
    return data['checkouts']


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        'Python 3.9+ required; snapshot/compare also require Git. JSON on stdout; exit 0 complete/unchanged, '
        '1 differences or inspection errors, 2 usage. Save private snapshots outside inspected '
        'checkouts. Hashes cover file bytes/modes, symlink targets, index, HEAD/branch, '
        'heads/tags/remotes/stash refs and stash order. Ignored files, empty directories, '
        'timestamps, config and object storage are excluded. No network, restoration '
        'or atomic/concurrent-change attribution. Snapshot/compare refuse shared-index layouts (including leftover '
        'sharedindex.* files), submodules and nested repositories.'
    ))
    commands = parser.add_subparsers(dest='operation', required=True)
    scan = commands.add_parser('discover', help='find checkout candidates beneath explicit roots, without Git',
                               description=(
        'Filesystem-only recursive scan. Explicit roots resolve symlinks; descendant symlinks '
        'are skipped. Include nested checkouts; prune .git directories. Candidates require a '
        '.git directory or gitfile (up to 64 KiB) pointing to a directory with a regular HEAD file. '
        'Gitfile targets may lie outside roots. No Git validity, remote or package checks. '
        'JSON lists canonical roots, sorted/deduplicated candidates (path, marker), '
        'rejected_markers and errors. Rejected markers alone are complete (exit 0); '
        'root/traversal/read errors make the inventory incomplete (exit 1).'
    ))
    scan.add_argument('roots', nargs='+', help='directory roots; overlaps and aliases collapse')
    take = commands.add_parser('snapshot', help='print state for explicit checkout roots')
    take.add_argument('checkouts', nargs='+', help='checkout root paths; duplicates collapse')
    compare = commands.add_parser('compare', help='compare current checkouts with a complete snapshot')
    compare.add_argument('--file', required=True, help='snapshot JSON path, or - for stdin')
    args = parser.parse_args()
    result = {'schema_version': 1, 'operation': args.operation, 'status': 'complete', 'errors': []}
    if args.operation == 'discover':
        result.update(discover(args.roots))
        if result['errors']:
            result['status'] = 'incomplete'
        print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
        return int(bool(result['errors']))
    old = None
    try:
        if args.operation == 'compare':
            if args.file == '-':
                old = baseline(sys.stdin)
            else:
                with open(args.file, encoding='utf-8') as stream:
                    old = baseline(stream)
            paths = [record['path'] for record in old]
        else:
            paths = args.checkouts
        current = {}
        for raw in sorted(set(paths)):
            try:
                root = Path(raw).expanduser().resolve(strict=True)
                if old is not None and str(root) != raw:
                    raise ValueError('snapshot checkout path no longer resolves to itself')
                if str(root) not in current:
                    current[str(root)] = snapshot(root)
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                result['errors'].append({'path': raw, 'reason': str(error)})
        if old is None:
            result['checkouts'] = [current[path] for path in sorted(current)]
        else:
            result['changes'] = [{'path': record['path'], 'fields': sorted(
                field for field in FIELDS if record[field] != current[record['path']][field])}
                for record in sorted(old, key=lambda record: record['path'])
                if record['path'] in current and record != current[record['path']]]
            result['matches'] = not result['changes'] if not result['errors'] else None
    except (OSError, ValueError, RecursionError) as error:
        result['errors'].append({'path': args.file, 'reason': str(error)})
        result.update(changes=[], matches=None)
    if result['errors']:
        result['status'] = 'incomplete'
    print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
    return int(bool(result['errors']) or result.get('matches') is False)


if __name__ == '__main__':
    if sys.version_info < (3, 9):
        print('checkout-state.py: Python 3.9+ is required', file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
