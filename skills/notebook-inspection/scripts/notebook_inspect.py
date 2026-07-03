#!/usr/bin/env python3
"""Inspect Jupyter notebooks without dumping noisy output JSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable


def load_notebook(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def source_text(cell: dict[str, Any]) -> str:
    source = cell.get("source", "")
    if isinstance(source, list):
        return "".join(str(part) for part in source)
    return str(source)


def iter_notebooks(paths: Iterable[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.ipynb"))
        elif path.suffix == ".ipynb":
            yield path


def selected_cell(cell: dict[str, Any], cell_type: str) -> bool:
    return cell_type == "all" or cell.get("cell_type") == cell_type


def command_stats(args: argparse.Namespace) -> int:
    for path in iter_notebooks(args.paths):
        try:
            text = path.read_text(encoding="utf-8")
            nb = json.loads(text)
        except Exception as exc:  # noqa: BLE001 - report parse failures and continue.
            print(f"{path}: parse failed: {exc}", file=sys.stderr)
            continue

        cells = nb.get("cells", [])
        code_cells = [cell for cell in cells if cell.get("cell_type") == "code"]
        output_cells = [cell for cell in code_cells if cell.get("outputs")]
        output_items = sum(len(cell.get("outputs", [])) for cell in code_cells)
        print(
            f"{path}\t"
            f"size={len(text) / 1024 / 1024:.2f} MiB\t"
            f"cells={len(cells)}\t"
            f"code={len(code_cells)}\t"
            f"code_with_outputs={len(output_cells)}\t"
            f"outputs={output_items}"
        )
    return 0


def command_cells(args: argparse.Namespace) -> int:
    for path in args.notebooks:
        nb = load_notebook(path)
        for index, cell in enumerate(nb.get("cells", []), start=1):
            if not selected_cell(cell, args.type):
                continue
            print(f"\n# %% [{path}:{index} {cell.get('cell_type', 'unknown')}]")
            print(source_text(cell).rstrip())
    return 0


def command_search(args: argparse.Namespace) -> int:
    found = False
    for path in iter_notebooks(args.paths):
        try:
            nb = load_notebook(path)
        except Exception as exc:  # noqa: BLE001 - report parse failures and continue.
            print(f"{path}: failed to parse notebook: {exc}", file=sys.stderr)
            continue

        for index, cell in enumerate(nb.get("cells", []), start=1):
            if not selected_cell(cell, args.type):
                continue
            text = source_text(cell)
            if args.needle in text:
                found = True
                print(f"\n# %% [{path}:{index} {cell.get('cell_type', 'unknown')}]")
                print(text.rstrip())
    return 0 if found else 1


def output_text(output: dict[str, Any]) -> list[tuple[str, str]]:
    output_type = output.get("output_type")
    if output_type == "stream":
        text = output.get("text", "")
        return [("stream", "".join(text) if isinstance(text, list) else str(text))]
    if output_type == "error":
        traceback = output.get("traceback", [])
        return [("error", "\n".join(str(line) for line in traceback))]

    data = output.get("data", {})
    items: list[tuple[str, str]] = []
    for key in ("text/plain", "text/markdown"):
        if key in data:
            value = data[key]
            text = "".join(value) if isinstance(value, list) else str(value)
            items.append((key, text))
    return items


def command_outputs(args: argparse.Namespace) -> int:
    for path in args.notebooks:
        nb = load_notebook(path)
        for index, cell in enumerate(nb.get("cells", []), start=1):
            if cell.get("cell_type") != "code":
                continue
            outputs = cell.get("outputs", [])
            if not outputs:
                continue

            print(f"\n# outputs [{path}:{index}]")
            for output in outputs:
                safe_items = output_text(output)
                if not safe_items:
                    keys = sorted(output.get("data", {}).keys())
                    print(f"[non-text output omitted: keys={keys}]")
                    continue
                for label, text in safe_items:
                    print(f"[{label}]")
                    print(text[: args.limit].rstrip())
                    if len(text) > args.limit:
                        print(f"[truncated to {args.limit} characters]")
    return 0


def command_validate(args: argparse.Namespace) -> int:
    for path in args.notebooks:
        load_notebook(path)
        print(f"{path}: valid JSON")
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subparsers = root.add_subparsers(dest="command", required=True)

    stats = subparsers.add_parser("stats", help="summarize notebook sizes and outputs")
    stats.add_argument("paths", nargs="+", type=Path)
    stats.set_defaults(func=command_stats)

    cells = subparsers.add_parser("cells", help="print source cells only")
    cells.add_argument("--type", choices=("code", "markdown", "all"), default="code")
    cells.add_argument("notebooks", nargs="+", type=Path)
    cells.set_defaults(func=command_cells)

    search = subparsers.add_parser("search", help="search source cells")
    search.add_argument("--type", choices=("code", "markdown", "all"), default="code")
    search.add_argument("needle")
    search.add_argument("paths", nargs="+", type=Path)
    search.set_defaults(func=command_search)

    outputs = subparsers.add_parser("outputs", help="print safe text outputs")
    outputs.add_argument("--limit", type=int, default=2000)
    outputs.add_argument("notebooks", nargs="+", type=Path)
    outputs.set_defaults(func=command_outputs)

    validate = subparsers.add_parser("validate", help="parse notebooks as JSON")
    validate.add_argument("notebooks", nargs="+", type=Path)
    validate.set_defaults(func=command_validate)

    return root


def main() -> int:
    args = parser().parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
