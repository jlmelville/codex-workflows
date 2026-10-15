#!/usr/bin/env python3
"""Inspect IDs, local links/assets, and embedded MathML in one existing HTML file."""

import argparse
from collections import Counter
from html import escape, unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import stat
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET


class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=False)
        self.source = source
        self.offsets = [0] + [match.end() for match in re.finditer('\n', source)]
        self.ids = Counter()
        self.anchors = set()
        self.references = []
        self.math = []
        self.math_start = None
        self.math_depth = 0
        self.display_math = 0
        self.issues = []
        self.base = False
        self.feed(source)
        self.close()
        if self.math_depth:
            self.issues.append({'reason': 'malformed_mathml', 'line': self.math_start[1],
                                'detail': 'unclosed math element'})

    def source_offset(self):
        line, column = self.getpos()
        return self.offsets[line - 1] + column

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        line = self.getpos()[0]
        if attrs.get('id'):
            self.ids[attrs['id']] += 1
            self.anchors.add(attrs['id'])
        if tag == 'a' and attrs.get('name'):
            self.anchors.add(attrs['name'])
        if tag == 'base' and 'href' in attrs:
            self.base = True
        for attribute in ('src', 'poster', 'data'):
            if attribute == 'data' and tag != 'object':
                continue
            if attrs.get(attribute):
                self.references.append((line, attrs[attribute]))
        if tag in ('a', 'area', 'link') and attrs.get('href'):
            self.references.append((line, attrs['href']))
        if tag == 'math':
            if not self.math_depth:
                self.math_start = (self.source_offset(), line)
                self.display_math += attrs.get('display') == 'block'
            self.math_depth += 1
        if tag == 'merror':
            self.issues.append({'reason': 'mathml_error_element', 'line': line})

    def handle_startendtag(self, tag, attributes):
        self.handle_starttag(tag, attributes)
        if tag == 'math' and self.math_depth == 1:
            self.math.append((self.math_start[1], self.get_starttag_text()))
            self.math_depth = 0
        else:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag != 'math':
            return
        if not self.math_depth:
            self.issues.append({'reason': 'malformed_mathml', 'line': self.getpos()[0],
                                'detail': 'unmatched math closing tag'})
            return
        self.math_depth -= 1
        if not self.math_depth:
            start, line = self.math_start
            end = self.source.index('>', self.source_offset()) + 1
            self.math.append((line, self.source[start:end]))


def signature(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_html(path):
    before = path.stat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError('expected a regular HTML file')
    with path.open('rb') as stream:
        content = stream.read()
    if signature(path.stat()) != signature(before):
        raise ValueError('HTML changed during inspection')
    try:
        return Document(content.decode('utf-8-sig'))
    except AssertionError as error:
        raise ValueError(f'HTML parser rejected input: {error}') from error


def inspect(path, root, result):
    document = read_html(path)
    counts = result['counts']
    counts.update(ids=len(document.ids), math=len(document.math) + bool(document.math_depth),
                  display_math=document.display_math)
    result['issues'].extend(document.issues)
    result['issues'].extend({'reason': 'duplicate_id', 'id': name, 'count': count}
                            for name, count in sorted(document.ids.items()) if count > 1)
    for line, fragment in document.math:
        # HTML named entities are legal in embedded MathML; normalize them for the XML parser.
        fragment = re.sub(r'&(?:#[0-9]+|#x[0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]+);',
                          lambda match: escape(unescape(match[0]), quote=False), fragment)
        try:
            ET.fromstring(fragment)
        except ET.ParseError as error:
            result['issues'].append({'reason': 'malformed_mathml', 'line': line, 'detail': str(error)})
    if document.base:
        result['errors'].append({'reason': 'unsupported_base_href', 'file': str(path)})
        return
    cache = {path: document}
    checked = set()
    for line, raw in document.references:
        location = {'line': line, 'target': raw}
        try:
            url = urlsplit(raw.strip())
            if url.scheme or url.netloc or raw.strip().startswith('//'):
                counts['skipped_urls'] += 1
                continue
            counts['local_references'] += 1
            decoded = unquote(url.path, errors='strict')
            target = ((root / decoded.lstrip('/')) if decoded.startswith('/')
                      else (path.parent / decoded) if decoded else path).resolve()
            if root != target and root not in target.parents:
                result['errors'].append({'reason': 'outside_root', **location})
                continue
            try:
                info = target.stat()
                if stat.S_ISDIR(info.st_mode):
                    target = (target / 'index.html').resolve()
                    if root != target and root not in target.parents:
                        result['errors'].append({'reason': 'outside_root', **location})
                        continue
                    info = target.stat()
            except (FileNotFoundError, NotADirectoryError):
                result['issues'].append({'reason': 'missing_target', **location})
                continue
            if not stat.S_ISREG(info.st_mode):
                result['errors'].append({'reason': 'unsupported_target', **location})
                continue
            checked.add(target)
            fragment = unquote(url.fragment, errors='strict')
            if fragment and (target == path or target.suffix.lower() in ('.html', '.htm', '.xhtml')):
                if target not in cache:
                    cache[target] = read_html(target)
                anchors = cache[target].anchors
                if fragment not in anchors and fragment.lower() != 'top':
                    result['issues'].append({'reason': 'missing_fragment', **location})
        except (OSError, ValueError, RuntimeError) as error:
            result['errors'].append({'reason': 'reference_unchecked', **location, 'detail': str(error)})
    counts['checked_targets'] = len(checked)


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        'Python 3.9+; standard library only. Read-only: no rendering, crawling, URL fetches '
        'or script execution. Relative links resolve beside FILE; leading / resolves under '
        '--root (default FILE parent). Targets escaping root, including symlinks, are unchecked '
        'errors. Directories use index.html; linked HTML is read only for fragment targets. '
        'Checks href on a/area/link, src, poster and object data; ignores URL schemes, CSS, '
        'srcset and non-HTML fragments. Base href is unsupported. MathML is checked for '
        'XML well-formedness and merror, not mathematical meaning; MathJax is not executed. '
        'JSON stdout: status complete/incomplete, ok true/false/null, counts, issues, errors. '
        'Exit 0 clean, 1 findings or incomplete inspection, 2 usage.'
    ))
    parser.add_argument('file', type=Path, help='existing UTF-8 HTML file')
    parser.add_argument('--root', type=Path, help='local site root (default FILE parent)')
    args = parser.parse_args()
    result = {'schema_version': 1, 'file': str(args.file), 'root': None,
              'status': 'complete', 'ok': None,
              'counts': {'ids': 0, 'math': 0, 'display_math': 0, 'local_references': 0,
                         'skipped_urls': 0, 'checked_targets': 0}, 'issues': [], 'errors': []}
    try:
        path = args.file.expanduser().resolve(strict=True)
        root = args.root.expanduser().resolve(strict=True) if args.root else path.parent
        result.update(file=str(path), root=str(root))
        if not root.is_dir() or (path != root and root not in path.parents):
            raise ValueError('FILE must be beneath a directory root')
        inspect(path, root, result)
    except (OSError, ValueError, RuntimeError) as error:
        result['errors'].append({'reason': 'inspection_failed', 'file': str(args.file), 'detail': str(error)})
    result['status'] = 'incomplete' if result['errors'] else 'complete'
    result['ok'] = None if result['errors'] else not result['issues']
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2))
    return int(result['ok'] is not True)


if __name__ == '__main__':
    if sys.version_info < (3, 9):
        print('inspect-article-html.py: Python 3.9+ is required', file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
