#!/usr/bin/env python3
"""Inspect notebook content; exit 2 on bad inputs, or 1 for a search with no match."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Iterable


def text_value(value: Any) -> bool:
    return isinstance(value, str) or (
        isinstance(value, list) and all(isinstance(part, str) for part in value)
    )


def check_notebook_shape(nb: Any) -> None:
    """Check the fields inspection consumes, not the full notebook schema."""
    if not isinstance(nb, dict) or not isinstance(nb.get("cells"), list):
        raise ValueError("expected a notebook object with a cells array")
    for index, cell in enumerate(nb["cells"], start=1):
        if not isinstance(cell, dict):
            raise ValueError(f"cell {index}: expected an object")
        if cell.get("cell_type") not in ("code", "markdown", "raw"):
            raise ValueError(f"cell {index}: expected code, markdown, or raw cell_type")
        if not text_value(cell.get("source")):
            raise ValueError(f"cell {index}: source must be text or an array of strings")
        outputs = cell.get("outputs", [])
        if not isinstance(outputs, list):
            raise ValueError(f"cell {index}: outputs must be an array")
        for output in outputs:
            if not isinstance(output, dict):
                raise ValueError(f"cell {index}: output must be an object")
            if not text_value(output.get("text", "")):
                raise ValueError(f"cell {index}: output text must be text or an array of strings")
            traceback = output.get("traceback", [])
            if not isinstance(traceback, list) or not all(isinstance(line, str) for line in traceback):
                raise ValueError(f"cell {index}: traceback must be an array of strings")
            data = output.get("data", {})
            if not isinstance(data, dict):
                raise ValueError(f"cell {index}: output data must be an object")
            for key in ("text/plain", "text/markdown"):
                if key in data and not text_value(data[key]):
                    raise ValueError(f"cell {index}: {key} must be text or an array of strings")


def source_text(cell: dict[str, Any]) -> str:
    source = cell["source"]
    return "".join(source) if isinstance(source, list) else source


def raise_walk_error(error: OSError) -> None:
    raise error


def iter_notebooks(path: Path, recursive: bool) -> Iterable[Path]:
    # stat and walk's error callback distinguish failed discovery from emptiness.
    path.stat()
    if path.is_dir() and recursive:
        files = []
        for directory, _, names in os.walk(path, onerror=raise_walk_error):
            files.extend(Path(directory) / name for name in names if name.endswith(".ipynb"))
        if not files:
            print(f"{path}: no notebooks found", file=sys.stderr)
        yield from sorted(files)
    elif path.is_file() and path.suffix == ".ipynb":
        yield path
    else:
        expected = "a .ipynb file or directory" if recursive else "a .ipynb file"
        raise ValueError(f"expected {expected}")


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def output_text(output: dict[str, Any]) -> list[tuple[str, str]]:
    output_type = output.get("output_type")
    if output_type == "stream":
        value = output.get("text", "")
        return [("stream", "".join(value) if isinstance(value, list) else value)]
    if output_type == "error":
        return [("error", "\n".join(output.get("traceback", [])))]

    items = []
    for key in ("text/plain", "text/markdown"):
        if key in output.get("data", {}):
            value = output["data"][key]
            items.append((key, "".join(value) if isinstance(value, list) else value))
    return items


def print_outputs(path: Path, nb: dict[str, Any], limit: int) -> None:
    for index, cell in enumerate(nb["cells"], start=1):
        if cell["cell_type"] != "code" or not cell.get("outputs"):
            continue
        print(f"\n# outputs [{path}:{index}]")
        for output in cell["outputs"]:
            safe_items = output_text(output)
            printed_keys = {label for label, _ in safe_items}
            omitted_keys = sorted(set(output.get("data", {})) - printed_keys)
            for label, text in safe_items:
                print(f"[{label}]")
                print(text[:limit].rstrip())
                if len(text) > limit:
                    print(f"[truncated to {limit} characters]")
            if omitted_keys or not safe_items:
                print(f"[non-text output omitted: keys={omitted_keys}]")


def inspect_notebook(args: argparse.Namespace, path: Path) -> bool:
    raw = path.read_bytes()
    nb = json.loads(raw.decode("utf-8"))
    if args.command == "validate":
        print(f"{path}: valid JSON")
        return False
    check_notebook_shape(nb)
    if args.command == "stats":
        cells = nb["cells"]
        code_cells = [cell for cell in cells if cell["cell_type"] == "code"]
        print(
            f"{path}\tsize={len(raw) / 1024 / 1024:.2f} MiB\t"
            f"cells={len(cells)}\tcode={len(code_cells)}\t"
            f"code_with_outputs={sum(bool(cell.get('outputs')) for cell in code_cells)}\t"
            f"outputs={sum(len(cell.get('outputs', [])) for cell in code_cells)}"
        )
        return False
    if args.command == "outputs":
        print_outputs(path, nb, args.limit)
        return False
    found = False
    for index, cell in enumerate(nb["cells"], start=1):
        if args.type != "all" and cell["cell_type"] != args.type:
            continue
        text = source_text(cell)
        if args.command == "search" and args.needle not in text:
            continue
        found = True
        print(f"\n# %% [{path}:{index} {cell['cell_type']}]")
        print(text.rstrip())
    return found


def command_inspect(args: argparse.Namespace) -> int:
    failed = False
    found = False
    for target in args.paths:
        try:
            paths = list(iter_notebooks(target, args.recursive))
        except (OSError, ValueError) as exc:
            print(f"{target}: discovery failed: {exc}", file=sys.stderr)
            failed = True
            continue
        for path in paths:
            try:
                found = inspect_notebook(args, path) or found
            except (OSError, ValueError) as exc:
                print(f"{path}: inspection failed: {exc}", file=sys.stderr)
                failed = True
    if failed:
        return 2
    return 1 if args.command == "search" and not found else 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.set_defaults(recursive=False)
    subparsers = root.add_subparsers(dest="command", required=True)

    stats = subparsers.add_parser("stats", help="summarize notebook sizes and outputs")
    stats.add_argument("paths", nargs="+", type=Path)
    stats.set_defaults(recursive=True)

    cells = subparsers.add_parser("cells", help="print source cells only")
    cells.add_argument("--type", choices=("code", "markdown", "all"), default="code")
    cells.add_argument("paths", nargs="+", type=Path)

    search = subparsers.add_parser("search", help="search source cells")
    search.add_argument("--type", choices=("code", "markdown", "all"), default="code")
    search.add_argument("needle")
    search.add_argument("paths", nargs="+", type=Path)
    search.set_defaults(recursive=True)

    outputs = subparsers.add_parser("outputs", help="print safe text outputs")
    outputs.add_argument("--limit", type=positive_int, default=2000)
    outputs.add_argument("paths", nargs="+", type=Path)

    validate = subparsers.add_parser("validate", help="parse JSON only; no notebook schema or execution check")
    validate.add_argument("paths", nargs="+", type=Path)
    return root


def main() -> int:
    return command_inspect(parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
