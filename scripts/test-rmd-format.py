#!/usr/bin/env python3
"""Exercise Rmd preservation and unsafe-format refusal with a controlled formatter."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "skills/r-docs-pkgdown/scripts/format-rmd.py"


class FormatTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="test-rmd-format-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        air = bin_dir / "air"
        air.write_text("""#!/usr/bin/env python3
import os
import sys
text = sys.stdin.read()
if 'RMD_FORMATTED_FIXTURE' in os.environ:
    text = os.environ['RMD_FORMATTED_FIXTURE']
elif 'unsafe_marker' in text:
    text = text.replace('x<-1', 'x <- 2')
elif 'option_marker' in text:
    text = text.replace('#| echo: false', '#| echo: true')
else:
    text = text.replace('x<-1', 'x <- 1')
sys.stdout.write(text)
""", encoding="utf-8")
        air.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"])

    def write(self, name, data):
        path = self.root / name
        path.write_bytes(data.encode("utf-8"))
        return path

    def invoke(self, mode, *paths, formatted=None):
        env = self.env if formatted is None else dict(self.env, RMD_FORMATTED_FIXTURE=formatted)
        return subprocess.run([sys.executable, str(SCRIPT), mode, *map(str, paths)],
                              capture_output=True, text=True, env=env, timeout=30)

    def assert_status(self, result, status):
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)

    def test_preservation_no_execution_and_idempotence(self):
        sentinel = self.root / "must-not-exist"
        source = ("\ufeff---\ntitle: 'x<-1'\nexample: |\n  ```r\n  x<-1\n  ```\n---\n"
                  "Prose `x<-1`, $x_i$, and a table:\n\n| x<-1 | value |\n| --- | --- |\n"
                  "<!--\n```r\nx<-1\n```\n-->\n"
                  "```{r setup, echo = FALSE}\n#| warning: false\nx<-1\n"
                  f'writeLines("side effect", "{sentinel}")\n```\n'
                  "```sh\nx<-1\n```\n```text\nx<-1\n```\n"
                  "````markdown\n```r\nx<-1\n```\n````\n"
                  "~~~R\nx<-1\n~~~\n> ```r\n> x<-1\n> ```\n"
                  "```{r alternate, engine='python'}\nx<-1\n```\nLast paragraph")
        expected = source.replace("#| warning: false\nx<-1", "#| warning: false\nx <- 1")
        expected = expected.replace("~~~R\nx<-1", "~~~R\nx <- 1")
        expected = expected.replace("> x<-1", "> x <- 1")
        path = self.write("article.Rmd", source)
        result = self.invoke("--check", path)
        self.assert_status(result, 1)
        self.assertEqual(path.read_bytes(), source.encode("utf-8"))
        self.assert_status(self.invoke("--write", path), 0)
        self.assertEqual(path.read_bytes(), expected.encode("utf-8"))
        self.assertFalse(sentinel.exists())
        self.assert_status(self.invoke("--check", path), 0)

    def test_html_comment_markers_in_inline_code_leave_later_chunks_visible(self):
        hidden = "<!--\n```{r}\nx<-1\n```\n-->\n\n"
        visible = "```{r}\nx<-1\n```\n"
        for literal in ("`<!--`", "`` `<!--` ``"):
            with self.subTest(literal=literal):
                prose = f"Write {literal} to start an HTML comment.\n\n"
                source = hidden + prose + visible
                path = self.write("comments.Rmd", source)
                self.assert_status(self.invoke("--check", path), 1)
                self.assertEqual(path.read_bytes(), source.encode())
                self.assert_status(self.invoke("--write", path), 0)
                expected = hidden + prose + visible.replace("x<-1", "x <- 1")
                self.assertEqual(path.read_bytes(), expected.encode())

    def test_crlf_and_file_mode_survive(self):
        source = "---\r\ntitle: Example\r\n---\r\n```r\r\nx<-1\r\n```\r\n"
        path = self.write("article.Rmd", source)
        path.chmod(0o640)
        self.assert_status(self.invoke("--write", path), 0)
        self.assertEqual(path.read_bytes(), source.replace("x<-1", "x <- 1").encode())
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_braces_do_not_hide_parsed_changes(self):
        cases = (
            ("if (x) f()", "if (x) { f() }"),
            ("f <- function(x) x + 1\nbody(f)", "f <- function(x) { x + 1 }\nbody(f)"),
            ("if (x) f()", "if (x) { g() }"),
            ("if (x) f()", "if (y) { f() }"),
            ("if (x) f()", "if (x) { f(); g() }"),
            ("if (x) { f() }", "if (x) f()"),
            ("x <- f()", "x <- { f() }"),
            ("quote(if (x) f())", "quote(if (x) { f() })"),
            ("capture(if (x) f())", "capture(if (x) { f() })"),
            ("field(x) <- if (ok) f()", "field(x) <- if (ok) { f() }"),
        )
        for code, formatted in cases:
            with self.subTest(code=code, formatted=formatted):
                source = f"```r\n{code}\n```\n"
                path = self.write("unsafe.Rmd", source)
                result = self.invoke("--write", path, formatted=formatted + "\n")
                self.assert_status(result, 2)
                self.assertIn("changed parsed R expressions", result.stderr)
                self.assertEqual(path.read_bytes(), source.encode())

    def test_semantic_change_refuses_entire_batch(self):
        good = self.write("a.Rmd", "```r\nx<-1\n```\n")
        bad = self.write("b.Rmd", "```r\n# unsafe_marker\nx<-1\n```\n")
        originals = {p: p.read_bytes() for p in (good, bad)}
        result = self.invoke("--write", good, bad)
        self.assert_status(result, 2)
        self.assertIn("changed parsed R expressions", result.stderr)
        self.assertIn(str(bad), result.stderr)
        for path, data in originals.items():
            self.assertEqual(path.read_bytes(), data)

    def test_chunk_options_preserved_beyond_r_parse_identity(self):
        path = self.write("options.Rmd", "```r\n# option_marker\n#| echo: false\nx<-1\n```\n")
        original = path.read_bytes()
        result = self.invoke("--write", path)
        self.assert_status(result, 2)
        self.assertIn("changed #| chunk options", result.stderr)
        self.assertEqual(path.read_bytes(), original)

    def test_invalid_documents_and_r_never_write(self):
        for source in ("---\ntitle: Broken\n", "```r\nx<-1\n", "```r\nf(\n```\n"):
            with self.subTest(source=source):
                path = self.write("invalid.Rmd", source)
                self.assert_status(self.invoke("--write", path), 2)
                self.assertEqual(path.read_bytes(), source.encode())

    def test_width_report_does_not_rewrite_literal_output(self):
        output = "some " * 30
        source = "```r\nx <- 1\n```\n```text\n" + output + "\n```\n"
        path = self.write("output.Rmd", source)
        result = self.invoke("--check", self.root)
        self.assert_status(result, 0)
        self.assertIn("other code/output", result.stdout)
        self.assertIn("1 residual wide lines", result.stdout)
        self.assertEqual(path.read_bytes(), source.encode())


if __name__ == "__main__":
    unittest.main()
