#!/usr/bin/env python3
"""Format fenced R in R Markdown with Air, preserving the document around it."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


FENCE = re.compile(r"^((?: {0,3}> ?)* {0,3})(`{3,}|~{3,})(.*)$")
R_INFO = re.compile(r"^(?:[rR]|\{\.[rR]\}|\{[rR](?:[\s,].*)?\})$")
VALIDATE = r'''
args <- commandArgs(TRUE)
paths <- readLines(args[1], warn = FALSE)
for (i in seq.int(1L, length(paths), by = 2L)) {
  original <- tryCatch(parse(paths[i], keep.source = FALSE), error = identity)
  formatted <- tryCatch(parse(paths[i + 1L], keep.source = FALSE), error = identity)
  if (inherits(original, "error") || inherits(formatted, "error")) {
    cat((i + 1L) %/% 2L, "invalid R syntax", sep = "\t")
    quit(status = 2L)
  }
  if (!identical(original, formatted)) {
    cat((i + 1L) %/% 2L, "formatting changed parsed R expressions", sep = "\t")
    quit(status = 2L)
  }
}
'''


@dataclass
class Block:
    start: int
    end: int
    r: bool
    prefix: str


def blocks(lines):
    """Recognize ordinary/quoted fences; skip YAML/comments, fail on open fences."""
    first = lines[0].lstrip("\ufeff").strip() if lines else ""
    i = 0
    if first == "---":
        i = next((n + 1 for n in range(1, len(lines))
                  if lines[n].strip() in ("---", "...")), 0)
        if not i:
            raise ValueError("unterminated YAML front matter")
    comment = False
    while i < len(lines):
        line = lines[i]
        if comment or "<!--" in line:
            # Leave the whole line alone even when a comment ends before a fence.
            comment = line.rfind("<!--") > line.rfind("-->") if "-->" in line else True
            i += 1
            continue
        opener = FENCE.match(line.rstrip("\r\n"))
        if not opener:
            if re.match(r"^(?: {4,}|\s*>).*(`{3,}|~{3,})\s*\{?[rR](?:\s|,|\}|$)", line):
                raise ValueError(f"line {i + 1}: nested R fence needs manual formatting")
            i += 1
            continue
        prefix, fence, info = opener.group(1), opener.group(2), opener.group(3).strip()
        r = bool(R_INFO.fullmatch(info))
        if re.match(r"^\{[rR](?:\s|,|$)", info) and not r:
            raise ValueError(f"line {i + 1}: unsupported R chunk header")
        engine = re.search(r"\bengine\s*=\s*(['\"])(.*?)\1", info)
        if engine and engine.group(2).lower() != "r":
            r = False
        end = i + 1
        closer = re.compile(r"^" + re.escape(prefix) + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$")
        while end < len(lines) and not closer.fullmatch(lines[end].rstrip("\r\n")):
            end += 1
        if end == len(lines):
            raise ValueError(f"line {i + 1}: unterminated code fence")
        yield Block(i + 1, end, r, prefix)
        i = end + 1


def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", **kwargs)
    if result.returncode:
        raise ValueError(f"{Path(argv[0]).name} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def files_in(paths):
    found = set()
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            candidates = sorted(path.rglob("*"))
            found.update(p.resolve() for p in candidates
                         if p.is_file() and p.suffix.lower() == ".rmd" and not p.is_symlink())
        elif path.is_file() and path.suffix.lower() == ".rmd":
            found.add(path.resolve())
        else:
            raise ValueError(f"{path}: expected an Rmd file or directory")
    if not found:
        raise ValueError("no Rmd files found")
    return sorted(found)


def prepare(paths, scratch, air):
    results, comparisons, locations = [], [], []
    for path in paths:
        original = path.read_bytes()
        text = original.decode("utf-8")
        lines = text.splitlines(keepends=True)
        try:
            fences = list(blocks(lines))
        except ValueError as error:
            raise ValueError(f"{path}: {error}") from error
        replacements = []
        for block in fences:
            if not block.r:
                continue
            body = lines[block.start:block.end]
            if any(s.strip() and not s.startswith(block.prefix) for s in body):
                raise ValueError(f"{path}:{block.start + 1}: inconsistent fence indentation/quotation")
            code = "".join(s[len(block.prefix):] if s.startswith(block.prefix) else s for s in body)
            if not code.strip():
                continue
            # The synthetic .R suffix enables stdin formatting of a chunk while
            # keeping configuration lookup anchored in the article's directory.
            try:
                formatted = run([air, "format", "--stdin-file-path", str(path.with_suffix(".R"))], input=code)
            except ValueError as error:
                raise ValueError(f"{path}:{block.start + 1}: {error}") from error
            if code.strip() and not formatted.strip():
                raise ValueError(f"{path}:{block.start + 1}: Air returned empty code")
            newline = "\r\n" if all(s.endswith("\r\n") for s in lines[block.start:block.end]) else "\n"
            formatted = formatted.replace("\r\n", "\n").replace("\n", newline)
            options = lambda text: [s for s in text.splitlines() if re.match(r"^\s*#\|", s)]
            if options(code) != options(formatted):
                raise ValueError(f"{path}:{block.start + 1}: formatting changed #| chunk options")
            number = len(locations)
            before, after = scratch / f"{number}-before.R", scratch / f"{number}-after.R"
            before.write_bytes(code.encode("utf-8"))
            after.write_bytes(formatted.encode("utf-8"))
            comparisons.extend([str(before), str(after)])
            locations.append(f"{path}:{block.start + 1}")
            replacements.append((block, "".join(block.prefix + s for s in formatted.splitlines(keepends=True))))
        for block, formatted in reversed(replacements):
            lines[block.start:block.end] = [formatted]
        candidate = "".join(lines).encode("utf-8")
        results.append((path, original, candidate, len(replacements)))
    if comparisons:
        manifest = scratch / "manifest"
        manifest.write_text("\n".join(comparisons) + "\n", encoding="utf-8")
        validation = subprocess.run(["Rscript", "--vanilla", "-e", VALIDATE, str(manifest)],
                                    capture_output=True, text=True, encoding="utf-8")
        if validation.returncode:
            details = validation.stdout.split("\t", 1)
            if len(details) == 2 and details[0].isdigit():
                raise ValueError(f"{locations[int(details[0]) - 1]}: {details[1].strip()}")
            raise ValueError(f"R validation failed: {validation.stderr.strip() or validation.stdout.strip()}")
    return results


def report_width(path, candidate, width):
    lines = candidate.decode("utf-8").splitlines(keepends=True)
    count = 0
    for block in blocks(lines):
        kind = "R source" if block.r else "other code/output"
        for i in range(block.start, block.end):
            length = len(lines[i].rstrip("\r\n").expandtabs(2))
            if length > width:
                print(f"{path}:{i + 1}: width {length} > {width} ({kind})")
                count += 1
    return count


def write_candidate(path, original, candidate):
    if path.read_bytes() != original:
        raise ValueError(f"{path}: changed while formatting; rerun")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(candidate)
        shutil.copymode(path, temporary)
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        "Requires Air and Rscript. Uses each article's project Air configuration. "
        "Does not execute examples. Width reports are advisory, not browser measurements. "
        "Exit: 0 success; 1 --check needs formatting; 2 invalid/unsafe input or tool failure."))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write validated formatting changes")
    mode.add_argument("--check", action="store_true", help="report changes without writing")
    parser.add_argument("--report-width", type=int, default=80, metavar="N", help="advisory character width (default: 80)")
    parser.add_argument("paths", nargs="+", help="explicit Rmd files or directories searched recursively")
    args = parser.parse_args()
    try:
        if args.report_width < 1:
            raise ValueError("--report-width must be positive")
        paths = files_in(args.paths)
        air = shutil.which("air")
        if not air or not shutil.which("Rscript"):
            raise ValueError("Air and Rscript must be available on PATH")
        with tempfile.TemporaryDirectory(prefix="format-rmd-") as directory:
            results = prepare(paths, Path(directory), air)
        # Check every input again before the first write.
        for path, original, _, _ in results:
            if path.read_bytes() != original:
                raise ValueError(f"{path}: changed while formatting; rerun")
        changed, chunks, wide = 0, 0, 0
        for path, original, candidate, count in results:
            chunks += count
            if original != candidate:
                changed += 1
                if args.write:
                    write_candidate(path, original, candidate)
                print(f"{'Formatted' if args.write else 'Would format'} {path}")
            wide += report_width(path, candidate, args.report_width)
        print(f"{len(paths)} files, {chunks} R blocks, {changed} {'formatted' if args.write else 'need formatting'}, {wide} residual wide lines")
        return int(args.check and changed > 0)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"format-rmd: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
