#!/usr/bin/env python3
"""Render current-side Git changes in a tracked R Markdown document as standalone HTML."""

import argparse
from html import escape
from html.parser import HTMLParser
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
DIV = re.compile(r"^ {0,3}(:{3,})(.*)$")
LIST = re.compile(r"^ {0,3}(?:[-+*]|\d+[.)])\s")
RAW_BLOCK = re.compile(r"^\s*</?(?:div|table|script|style|pre|section|details|figure|iframe)\b", re.I)
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.M)


def command(argv, cwd):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise ValueError(f"{argv[0]} failed ({result.returncode}):\n{result.stderr or result.stdout}")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.stdout


def markdown_blocks(lines):
    """Conservatively group complete paragraphs, lists, fences, divs and display math."""
    start = 0
    if lines and lines[0] == "---":
        start = next((i + 1 for i in range(1, len(lines)) if lines[i] in ("---", "...")), 0)
        if not start:
            raise ValueError("unterminated YAML front matter")
    metadata_end = start
    blocks = []
    while start < len(lines):
        if not lines[start].strip():
            start += 1
            continue
        fence = None
        div_depth = 0
        math_end = None
        list_block = bool(LIST.match(lines[start]))
        indented_block = lines[start].startswith("    ")
        quote_block = lines[start].lstrip().startswith(">")
        end = start
        while end < len(lines):
            line = lines[end]
            if fence:
                if re.fullmatch(r" {0,3}" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*", line):
                    fence = None
            elif math_end:
                if line.rstrip().endswith(math_end):
                    math_end = None
            elif FENCE.match(line):
                fence = FENCE.match(line).group(1)
            elif DIV.match(line):
                marker = DIV.match(line)
                div_depth += 1 if marker.group(2).strip() else -1
                if div_depth < 0:
                    raise ValueError("unmatched fenced-div closer")
            elif line.lstrip().startswith("$$"):
                if line.strip() == "$$" or not line.rstrip().endswith("$$"):
                    math_end = "$$"
            elif line.lstrip().startswith(r"\["):
                if not line.rstrip().endswith(r"\]"):
                    math_end = r"\]"
            elif re.match(r"^\s*\\begin\{", line):
                raise ValueError("use $$ or \\[ display math; raw TeX environments require source review")
            elif RAW_BLOCK.match(line):
                raise ValueError("raw HTML blocks are outside this helper's scope; use the source diff")
            elif not line.strip() and not div_depth:
                following = end + 1
                while following < len(lines) and not lines[following].strip():
                    following += 1
                next_line = lines[following] if following < len(lines) else ""
                continued = (
                    (list_block and (LIST.match(next_line) or next_line.startswith((" ", "\t"))))
                    or (indented_block and next_line.startswith("    "))
                    or (quote_block and next_line.lstrip().startswith(">"))
                )
                if not continued:
                    break
            end += 1
        if fence or div_depth or math_end:
            raise ValueError("unterminated code fence, fenced div or display math")
        blocks.append((start, end))
        start = end
    return metadata_end, blocks


def annotate(source, diff):
    lines = source.splitlines()
    metadata_end, blocks = markdown_blocks(lines)
    selected = set()
    for match in HUNK.finditer(diff):
        first = int(match.group(1)) - 1
        count = int(match.group(2)) if match.group(2) is not None else 1
        if not count:
            continue  # Deletions have no current-side text; the review banner says so.
        if first < metadata_end:
            raise ValueError("front-matter changes require source review; metadata is not a visible text block")
        touched = {i for i, (start, end) in enumerate(blocks) if start < first + count and end > first}
        if not touched and blocks:
            # Blank-only changes may split or join paragraphs; show the adjacent current block.
            touched = {next((i for i, (_, end) in enumerate(blocks) if end > first), len(blocks) - 1)}
        selected.update(touched)
    if "cw-review-" in source:
        raise ValueError("source already uses the reserved cw-review- identifier prefix")
    for i in selected:
        start, end = blocks[i]
        if any(re.match(r"^ {0,3}\[[^\]]+\]:", line) for line in lines[start:end]):
            raise ValueError("reference-definition changes require source review")
    numbered = {block: number for number, block in enumerate(sorted(selected), 1)}
    starts = {blocks[i][0]: number for i, number in numbered.items()}
    ends = {blocks[i][1] for i in selected}
    result = []
    for index in range(len(lines) + 1):
        if index in ends:
            result.extend(["", "::::::::::::", ""])
        if index in starts:
            result.extend(["", f':::::::::::: {{#cw-review-change-{starts[index]} .cw-review-change tabindex="-1"}}', ""])
        if index < len(lines):
            result.append(lines[index])
    return "\n".join(result) + "\n", len(selected)


STYLE = """<style>
.cw-review-change { background: #fff8e8; border-left: 3px solid #ac6711;
  padding: .4rem 1rem; margin: .75rem 0; scroll-margin-top: 8rem; }
.cw-review-change:focus { outline: 2px solid #305f9c; }
#cw-review-navigation { position: sticky; top: 0; z-index: 1000; background: #f5f7fa;
  color: #182535; border-bottom: 1px solid #a4afbd; padding: .7rem; font: 15px sans-serif; }
#cw-review-navigation button { margin-right: .5rem; padding: .3rem .7rem; }
#cw-review-navigation p { margin: .4rem 0; }
@media print { #cw-review-navigation { position: static; } }
</style>"""

NAVIGATION_SCRIPT = """<script id="cw-review-script">
(() => {
  const regions = Array.from(document.querySelectorAll('.cw-review-change'));
  const previous = document.getElementById('cw-review-previous');
  const next = document.getElementById('cw-review-next');
  const status = document.getElementById('cw-review-status');
  let current = -1;
  function move(delta) {
    if (!regions.length) return;
    current = current < 0 ? (delta > 0 ? 0 : regions.length - 1)
                         : (current + delta + regions.length) % regions.length;
    regions[current].focus({preventScroll: true});
    regions[current].scrollIntoView({block: 'center'});
    status.textContent = `Change ${current + 1} of ${regions.length}`;
  }
  previous.disabled = next.disabled = !regions.length;
  previous.addEventListener('click', () => move(-1));
  next.addEventListener('click', () => move(1));
})();
</script>"""


class ReviewHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.regions = []
        self.external_assets = []
        self.math_count = 0
        self.in_style = False

    def check_asset(self, asset):
        if asset and not asset.startswith(("data:", "#")):
            self.external_assets.append(asset)

    def check_css(self, css):
        for match in re.finditer(r"url\(\s*(['\"]?)(.*?)\1\s*\)|@import\s+(['\"])(.*?)\3", css, re.I):
            self.check_asset((match.group(2) or match.group(4) or "").strip())

    def handle_data(self, data):
        if self.in_style:
            self.check_css(data)

    def handle_endtag(self, tag):
        if tag == "style":
            self.in_style = False

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        if "cw-review-change" in (attrs.get("class") or "").split():
            self.regions.append(attrs.get("id"))
        if tag == "math":
            self.math_count += 1
        self.check_asset(attrs.get("src"))
        self.check_asset(attrs.get("poster"))
        if tag == "object":
            self.check_asset(attrs.get("data"))
        if tag == "link" and "stylesheet" in (attrs.get("rel") or "").split():
            self.check_asset(attrs.get("href"))
        if attrs.get("srcset"):
            self.external_assets.append("srcset requires separate asset review")
        self.check_css(attrs.get("style") or "")
        if tag == "style":
            self.in_style = True


def validate_html(html, count):
    document = ReviewHTML()
    document.feed(html)
    expected = [f"cw-review-change-{i}" for i in range(1, count + 1)]
    if document.regions != expected:
        raise ValueError("rendered change regions do not match the annotated source")
    controls = ["cw-review-navigation", "cw-review-previous", "cw-review-next", "cw-review-status", "cw-review-script"]
    if any(document.ids.count(name) != 1 for name in expected + controls):
        raise ValueError("rendered review has missing or duplicate regions/navigation controls")
    if document.external_assets:
        raise ValueError("review has non-embedded assets: " + ", ".join(document.external_assets[:5]))
    if "Deleted text is omitted" not in html:
        raise ValueError("rendered review lost its deletion caveat")
    return document


def render_review(source_path, base, output):
    if source_path.is_symlink() or source_path.suffix.lower() != ".rmd":
        raise ValueError("source must be a regular .Rmd file, not a symlink")
    source_path = source_path.resolve(strict=True)
    root = Path(command(["git", "rev-parse", "--show-toplevel"], source_path.parent).strip())
    relative = source_path.relative_to(root).as_posix()
    command(["git", "ls-files", "--error-unmatch", "--", f":(literal){relative}"], root)
    revision = command(["git", "rev-parse", "--verify", "--end-of-options", base + "^{commit}"], root).strip()
    original = source_path.read_text(encoding="utf-8")
    diff = command(["git", "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
                    "--text", "--unified=0", revision, "--", f":(literal){relative}"], root)
    annotated, count = annotate(original, diff)
    output = output.absolute().parent.resolve(strict=True) / output.name
    if output.suffix.lower() != ".html":
        raise ValueError("output must have an .html extension")
    if output.exists() or output.is_symlink():
        raise ValueError(f"refusing to overwrite existing output: {output}")
    with tempfile.TemporaryDirectory(prefix="rmd-review.") as temporary:
        workspace = Path(temporary)
        staged = workspace / source_path.name
        staged.write_text(annotated, encoding="utf-8")
        # Use the source directory for chunk-relative inputs and Pandoc resources. The portable
        # output format is explicit; site themes/plugins and original output-format options do not run.
        expression = """
args <- commandArgs(TRUE)
if (!requireNamespace("rmarkdown", quietly = TRUE)) stop("rmarkdown is required")
rmarkdown::render(args[[1]], output_file = "review.html", output_dir = args[[2]],
  intermediates_dir = args[[2]], knit_root_dir = args[[3]], quiet = TRUE,
  envir = new.env(parent = globalenv()),
  output_format = rmarkdown::html_document(self_contained = TRUE, mathjax = NULL,
    md_extensions = "+fenced_divs", pandoc_args = c("--mathml", args[[4]])))
"""
        command(["Rscript", "--vanilla", "-e", expression, str(staged), str(workspace),
                 str(source_path.parent), "--resource-path=" + str(source_path.parent) + os.pathsep + str(workspace)],
                source_path.parent)
        html = (workspace / "review.html").read_text(encoding="utf-8")
        navigation = (
            '<nav id="cw-review-navigation" aria-label="Document changes">'
            f'<p>Current-side review of {escape(relative)} against {revision[:12]}. '
            'Deleted text is omitted; consult the Git source diff for removals.</p>'
            '<button type="button" id="cw-review-previous">Previous change</button>'
            '<button type="button" id="cw-review-next">Next change</button>'
            f'<span id="cw-review-status" role="status" aria-live="polite">{count} changed blocks</span></nav>'
        )
        if html.count("</head>") != 1 or html.count("</body>") != 1:
            raise ValueError("rendered HTML lacks a unique head/body boundary")
        html = html.replace("</head>", STYLE + "\n</head>")
        html, replacements = re.subn(r"<body\b[^>]*>", lambda match: match.group() + navigation, html, count=1)
        if replacements != 1:
            raise ValueError("rendered HTML lacks a body element")
        html = html.replace("</body>", NAVIGATION_SCRIPT + "\n</body>")
        validate_html(html, count)
        if source_path.read_text(encoding="utf-8") != original:
            raise ValueError("source changed during rendering; regenerate the review")
        # Publish the validated bytes without replacing a destination created during the render.
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".rmd-review.", delete=False) as stream:
            temporary_output = Path(stream.name)
            try:
                stream.write(html.encode("utf-8"))
                stream.flush()
                os.link(temporary_output, output)
            finally:
                temporary_output.unlink()
    return output, count


def self_test(render=False):
    source = "# Heading\n\nBefore.\n\n```{r}\n1 + 1\n\n2 + 2\n```\n\nAfter.\n"
    annotated, count = annotate(source, "@@ -6 +6 @@\n")
    assert count == 1 and annotated.index("cw-review-change-1") < annotated.index("```{r}")
    assert annotated.index("2 + 2") < annotated.rindex("::::::::::::")
    nested = "::: outer\n\n:::: inner\n\nOld\n\n::::\n\n:::\n"
    annotated, count = annotate(nested, "@@ -5 +5 @@\n")
    assert count == 1 and annotated.index("cw-review-change-1") < annotated.index("::: outer")
    listing = "- first\n\n  continuation\n\n- second\n\nOther.\n"
    assert annotate(listing, "@@ -3 +3 @@\n")[1] == 1
    assert annotate(source, "@@ -3,2 +2,0 @@\n")[1] == 0
    for invalid in ("```{r}\n1", "::: outer\ntext", "$$\nx", "<div>\ntext\n</div>",
                    r"\begin{align} x = 1 \end{align}"):
        try:
            annotate(invalid, "@@ -1 +1 @@\n")
        except ValueError:
            pass
        else:
            raise AssertionError("unsupported or incomplete structure was accepted")
    sample = ('<nav id="cw-review-navigation"><button id="cw-review-previous"></button>'
              '<button id="cw-review-next"></button><span id="cw-review-status"></span></nav>'
              '<div id="cw-review-change-1" class="cw-review-change">Changed</div>'
              'Deleted text is omitted' + NAVIGATION_SCRIPT)
    validate_html(sample, 1)
    for invalid in (sample.replace('class="cw-review-change"', ''),
                    sample + '<script src="https://example.invalid/script.js"></script>',
                    sample + '<style>body {background: url("missing.png")}</style>',
                    sample + '<style>@import "https://example.invalid/theme.css";</style>',
                    sample.replace('id="cw-review-next"', 'id="missing-control"')):
        try:
            validate_html(invalid, 1)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid delivered artifact was accepted")
    if not render:
        print("R Markdown review structural self-test passed.")
        return
    with tempfile.TemporaryDirectory(prefix="rmd-review-test.") as temporary:
        root = Path(temporary)
        command(["git", "init", "--quiet"], root)
        command(["git", "config", "user.name", "Review Fixture"], root)
        command(["git", "config", "user.email", "fixture@example.invalid"], root)
        article = root / "article.Rmd"
        baseline = ('---\ntitle: Review fixture\n---\n\n# Result\n\nA formula $x^2$.\n\n'
                    '| Input | Output |\n| --- | --- |\n| 2 | 4 |\n\n'
                    '```{r}\nsum(read.csv("values.csv")$value)\nplot(1:3)\n```\n\n'
                    '::: outer\n\n:::: inner\n\nNested text.\n\n::::\n\n:::\n\n'
                    '- first\n\n  continuation\n\n- second\n\nDelete this paragraph.\n')
        article.write_text(baseline, encoding="utf-8")
        (root / "values.csv").write_text("value\n2\n3\n", encoding="utf-8")
        command(["git", "add", "article.Rmd"], root)
        command(["git", "commit", "--quiet", "-m", "fixture"], root)
        changed = (baseline.replace("$x^2$", "$x^3$").replace("$value)", "$value) + 1")
                   .replace("Nested text.", "Nested revision.").replace("continuation", "revised continuation"))
        article.write_text(changed, encoding="utf-8")
        output, count = render_review(article, "HEAD", root / "review.html")
        html = output.read_text(encoding="utf-8")
        document = validate_html(html, count)
        assert count == 4 and document.math_count == 1 and "<table>" in html
        assert "## [1] 6" in html and "data:image/png;base64," in html
        assert "Nested revision." in html and "revised continuation" in html
        assert article.read_text(encoding="utf-8") == changed
        try:
            render_review(article, "HEAD", output)
        except ValueError:
            pass
        else:
            raise AssertionError("existing output was overwritten")
        assert output.read_text(encoding="utf-8") == html
        article.write_text(baseline.replace("Delete this paragraph.\n", ""), encoding="utf-8")
        deleted, count = render_review(article, "HEAD", root / "deletion.html")
        assert count == 0
        validate_html(deleted.read_text(encoding="utf-8"), count)
    print("R Markdown review self-test passed.")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, help="tracked .Rmd source; rendering executes its chunks")
    parser.add_argument("--base", default="HEAD", help="Git comparison commit (default HEAD)")
    parser.add_argument("--out", type=Path, help="new standalone .html file in an existing directory")
    parser.add_argument("--self-test", action="store_true", help="test block expansion and artifact validation")
    parser.add_argument("--self-test-render", action="store_true", help="also render real R Markdown fixtures (requires R/rmarkdown/Pandoc)")
    args = parser.parse_args(argv)
    if args.self_test or args.self_test_render:
        if argv not in (["--self-test"], ["--self-test-render"]):
            parser.error("self-test options must be used alone")
        self_test(render=args.self_test_render)
        return
    if args.source is None or args.out is None:
        parser.error("SOURCE and --out are required")
    output, count = render_review(args.source, args.base, args.out)
    print(f"{output}\t{count} changed blocks")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError) as error:
        print(f"render-rmd-review: {error}", file=sys.stderr)
        sys.exit(1)
