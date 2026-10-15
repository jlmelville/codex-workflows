#!/usr/bin/env python3
"""Exercise static article checks without changing inspected files."""

import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'skills/r-docs-pkgdown/scripts/inspect-article-html.py'


class ArticleHTMLTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='article-html-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.site = self.root / 'site with spaces'
        self.site.mkdir()
        self.article = self.site / 'article.html'

    def write(self, relative, text):
        path = self.site / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def tree(self):
        return {str(path.relative_to(self.root)): ('link', os.readlink(path)) if path.is_symlink()
                else ('file', path.read_bytes(), path.stat().st_mode)
                for path in self.root.rglob('*') if path.is_symlink() or path.is_file()}

    def invoke(self, *args, status=0):
        before = self.tree()
        result = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, status, result.stderr or result.stdout)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(self.tree(), before, 'inspection changed HTML, assets, or adjacent files')
        if status != 2:
            self.assertEqual(result.stderr, '')
        return result

    def inspect(self, text=None, *args, status=0):
        if text is not None:
            self.write('article.html', text)
        return json.loads(self.invoke(self.article, *args, status=status).stdout)

    def test_clean_article_counts_and_local_targets(self):
        self.write('other.html', '<h1 id="résumé">Other</h1><a name="legacy"></a>')
        self.write('image.png', 'image bytes')
        self.write('style.css', 'body {background: url(unchecked.png)}')
        result = self.inspect('''<!doctype html><h1 id="intro">Intro</h1><a name="old"></a>
<a href="#intro">Intro</a><a href="#old">Legacy</a><a href="#top">Top</a>
<a href="other.html?version=1#r%C3%A9sum%C3%A9">Other</a><img src="image.png">
<link rel="stylesheet" href="style.css"><a href="https://example.invalid/">Remote</a>
<script src="//example.invalid/script.js"></script><a href="mailto:x@example.invalid">Mail</a>
<img src="data:image/png;base64,AAAA"><math><mi>x</mi></math>
<math display="block"><mn>2</mn></math>''')
        self.assertEqual(result['status'], 'complete')
        self.assertIs(result['ok'], True)
        self.assertEqual(result['counts'], {'ids': 1, 'math': 2, 'display_math': 1,
                                          'local_references': 6, 'skipped_urls': 4,
                                          'checked_targets': 4})
        self.assertEqual(result['issues'], [])
        self.assertEqual(result['errors'], [])

    def test_duplicate_ids_missing_links_and_fragments(self):
        result = self.inspect('''<h1 id="duplicate">One</h1><p id="duplicate">Two</p>
<a href="#absent">Missing fragment</a><img src="absent.png">''', status=1)
        self.assertEqual(result['status'], 'complete')
        self.assertIs(result['ok'], False)
        self.assertEqual({item['reason'] for item in result['issues']},
                         {'duplicate_id', 'missing_fragment', 'missing_target'})
        duplicate = next(item for item in result['issues'] if item['reason'] == 'duplicate_id')
        self.assertEqual(duplicate, {'reason': 'duplicate_id', 'id': 'duplicate', 'count': 2})
        self.assertEqual(next(item['line'] for item in result['issues']
                              if item['reason'] == 'missing_target'), 2)

    def test_mathml_errors_and_unclosed_elements(self):
        for text in ('<math><mi>x</math>', '<math><mi>x</mi>', '</math>'):
            with self.subTest(text=text):
                result = self.inspect(text, status=1)
                self.assertIn('malformed_mathml', [item['reason'] for item in result['issues']])
        result = self.inspect('<math><merror><mtext>bad formula</mtext></merror></math>', status=1)
        self.assertEqual(result['issues'], [{'reason': 'mathml_error_element', 'line': 1}])

    def test_mathml_html_entities_self_closing_and_script_text(self):
        result = self.inspect('''<!-- <math>not real math</math> -->
<script>const fake = '<math><merror>not real math</merror></math>';</script>
<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>&nbsp;</mi><mo>&amp;</mo>
<mo>&#x2264;</mo><mtext>&lt;value&gt;</mtext></math><math /><math data-label=">" />''')
        self.assertEqual(result['counts']['math'], 3)
        self.assertEqual(result['issues'], [])

    def test_root_relative_directory_and_encoded_paths(self):
        page = self.write('articles/nested.html', '''<a href="/index.html#home">Root</a>
<a href="../section/#section">Section</a><img src="../image%20one.png?size=2">''')
        self.write('index.html', '<h1 id="home">Home</h1>')
        self.write('section/index.html', '<h1 id="section">Section</h1>')
        self.write('image one.png', 'asset')
        result = json.loads(self.invoke(page, '--root', self.site).stdout)
        self.assertTrue(result['ok'])
        self.assertEqual(result['counts']['checked_targets'], 3)
        result = json.loads(self.invoke(page, status=1).stdout)
        self.assertEqual(result['status'], 'incomplete')
        self.assertIn('outside_root', [item['reason'] for item in result['errors']])

    def test_symlink_escapes_including_directory_index_are_unchecked(self):
        outside = self.root / 'outside.html'
        outside.write_text('<h1 id="secret">Outside</h1>')
        (self.site / 'escape.html').symlink_to(outside)
        section = self.site / 'section'
        section.mkdir()
        (section / 'index.html').symlink_to(outside)
        result = self.inspect('''<a href="escape.html#secret">Escape</a>
<a href="section/#secret">Index escape</a><a href="../outside.html#secret">Parent</a>''', status=1)
        self.assertIsNone(result['ok'])
        self.assertEqual([item['reason'] for item in result['errors']], ['outside_root'] * 3)

    def test_linked_html_only_supplies_fragment_targets(self):
        self.write('linked.html', '''<h1 id="target">Target</h1><a href="absent.html">Unvisited</a>
<math><merror>not the inspected article</merror></math>''')
        result = self.inspect('<a href="linked.html#target">Good</a><a href="linked.html#absent">Bad</a>', status=1)
        self.assertEqual(result['counts']['checked_targets'], 1)
        self.assertEqual(result['issues'], [{'reason': 'missing_fragment', 'line': 1,
                                            'target': 'linked.html#absent'}])

    def test_media_object_targets_and_non_html_fragments(self):
        self.write('movie.mp4', 'movie')
        self.write('poster.png', 'poster')
        self.write('figure.svg', '<svg></svg>')
        result = self.inspect('''<video src="movie.mp4" poster="poster.png"></video>
<object data="figure.svg#external-svg-fragment"></object>
<img srcset="unchecked.png 1x" style="background:url(unchecked.png)">''')
        self.assertEqual(result['counts']['local_references'], 3)
        self.assertEqual(result['counts']['checked_targets'], 3)

    def test_base_href_is_explicitly_incomplete(self):
        result = self.inspect('<base href="https://example.invalid/"><a href="other.html">Other</a>', status=1)
        self.assertEqual(result['status'], 'incomplete')
        self.assertIsNone(result['ok'])
        self.assertEqual(result['errors'][0]['reason'], 'unsupported_base_href')

    def test_bad_utf8_source_and_linked_target(self):
        self.article.write_bytes(b'\xff')
        self.assertEqual(self.inspect(status=1)['status'], 'incomplete')
        (self.site / 'bad.html').write_bytes(b'\xff')
        result = self.inspect('<a href="bad.html#anchor">Bad encoding</a>', status=1)
        self.assertEqual(result['errors'][0]['reason'], 'reference_unchecked')
        self.assertIsNone(result['ok'])

    def test_missing_input_bad_root_and_invalid_url(self):
        result = self.inspect(status=1)
        self.assertEqual(result['errors'][0]['reason'], 'inspection_failed')
        self.write('article.html', '<p>Article</p>')
        self.assertEqual(self.inspect(None, '--root', self.article, status=1)['status'], 'incomplete')
        result = self.inspect('<a href="http://[invalid">Invalid URL</a>', status=1)
        self.assertEqual(result['errors'][0]['reason'], 'reference_unchecked')
        self.assertEqual(self.inspect('<![broken]>', status=1)['status'], 'incomplete')

    def test_usage_help_and_no_math_is_not_a_failure(self):
        result = self.inspect('<p>Plain article or unexecuted MathJax</p>')
        self.assertEqual(result['counts']['math'], 0)
        self.assertTrue(result['ok'])
        for args in ([], [self.article, '--root'], [self.article, '--unknown']):
            result = self.invoke(*args, status=2)
            self.assertEqual(result.stdout, '')
            self.assertIn('usage:', result.stderr)
        help_text = self.invoke('--help').stdout
        self.assertIn('srcset', help_text)
        self.assertIn('JSON stdout', help_text)

    def test_changed_html_is_not_reported_clean(self):
        self.write('article.html', '<p>Article</p>')
        namespace = runpy.run_path(str(SCRIPT))
        read_html = namespace['read_html']
        before = self.tree()
        with patch.dict(read_html.__globals__, signature=unittest.mock.Mock(side_effect=[1, 2])):
            with self.assertRaisesRegex(ValueError, 'changed during inspection'):
                read_html(self.article)
        self.assertEqual(self.tree(), before)


if __name__ == '__main__':
    unittest.main()
