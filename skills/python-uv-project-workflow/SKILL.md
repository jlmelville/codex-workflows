---
name: python-uv-project-workflow
description: Work in Python projects that use uv, pyproject.toml, pytest, Ruff, type hints, notebooks, fixtures, or package-style src/ layouts. Use when Codex edits, reviews, tests, debugs, or validates Python repository code, especially uv-managed projects. Pair with uv-sandbox-workflow when running uv inside Codex sandboxes.
---

# Python uv Project Workflow

Use this as the default operating procedure for Python repositories managed by
`uv`. This skill covers project workflow; use `$uv-sandbox-workflow` for Codex
sandbox cache directories, network approval, and `uv run --with` mechanics.

## First Pass

1. Inspect the worktree before editing:
   `git --no-optional-locks status --short --untracked-files=all`.
2. Read project context before assuming layout: `pyproject.toml`, `uv.lock`,
   `README*`, package modules under `src/` or the project package directory,
   relevant `tests/`, and any active local plan or handoff.
3. Identify the package manager and test/lint tools from `pyproject.toml`
   rather than guessing.
4. Do not revert unrelated user changes. If touched files already contain user
   edits, work with them.

## Change Discipline

- Prefer existing abstractions and module boundaries before adding new ones.
- Keep behavior fixes, broad formatting, dependency changes, and generated
  artifacts in separate phases unless the user asks for a combined sweep.
- Fail loudly with actionable error messages close to the failure source.
- Use type hints where they clarify behavior or match local style.
- Add comments only for durable context: invariants, non-obvious tradeoffs, or
  why code must exist.
- Do not add comments, docstrings, or docs that reference a prompt,
  conversation, agent, temporary plan, or implementation history.
- Be careful with large arrays, sparse data, notebooks, and generated outputs:
  avoid avoidable O(N^2) allocations and dense copies on hot paths.

## uv Workflow

Prefer project-managed commands:

```sh
uv sync --locked
uv run pytest
uv run pytest tests/<area>
uv run ruff format <paths>
uv run ruff check <paths>
```

Before changing dependencies, inspect dependency groups and lock policy in
`pyproject.toml`. Use `uv lock` or `uv sync` only when dependency or lockfile
updates are intended. Do not edit `uv.lock` manually.

When running uv in Codex, follow `$uv-sandbox-workflow` first so mutable uv
caches and downloaded tools live under `/tmp` and network approval is requested
when needed.

## Tests And Validation

Choose validation based on blast radius:

- Focused unit test for one module or bug:
  `uv run pytest tests/test_<area>.py -q`.
- Public behavior or integration change:
  run the focused test plus the nearest integration test.
- Formatting-only Python change:
  `uv run ruff format <paths>` and `uv run ruff check <paths>`.
- API, dependency, or broad package change:
  run focused tests first, then `uv run pytest` when feasible.

For behavior changes, state what failed or was missing before and what now
passes or works after. If a command is expensive, optional-data-dependent, or
unavailable, report that honestly and name the command that should be run.

For Python CLIs that accept arbitrary numeric vectors, add smoke tests for
negative values and scientific notation, especially when the command is called
from R or shell scripts. Avoid assuming `argparse` vector options with
`nargs="+"` will handle signed numeric tokens robustly; consider a delimiter or
CSV argument, or parse trailing tokens deliberately when the CLI needs raw
numeric vectors.

For cross-language numeric oracle comparisons, such as R/Python, Python/C++,
NumPy/Torch, or autograd checks, report both absolute and relative differences.
Accept either a meaningful absolute tolerance or a tight relative tolerance so
large-scale objectives, gradients, or Hessians do not become false formula
diffs from roundoff alone. Keep absolute tolerances for small or near-zero
reference values.

## Project Layout

Infer layout from the repo, but common paths are:

- `src/<package>/`: package code.
- `<package>/`: package code in flat layouts.
- `tests/`: pytest tests and fixtures.
- `notebooks/` or `examples/`: examples, demonstrations, generated outputs.
- `scripts/`: project automation.

When adding tests, prefer public APIs and realistic fixtures over private helper
tests. Private-helper tests are acceptable when they protect a subtle invariant
that is hard to reach through the public surface; document the behavior they
protect in the test name or nearby assertion.

## Notebooks And Artifacts

Use `$notebook-inspection` when the task touches `.ipynb` files, generated
plots, stored outputs, or notebook examples. Treat notebooks as examples and
exploratory records, not the primary implementation surface, unless the user is
specifically working on the notebook.

Avoid committing large regenerated outputs unless requested. Generated artifacts
should record the command, data source, random seed, and important parameters
when practical.

Prefer fixtures or small synthetic data for tests. If a Python task depends on
external data, make the missing-data behavior explicit instead of assuming the
file exists on every machine.

## Review Checklist

Before finalizing a substantial diff, check:

- The diff solves the requested problem without unrelated cleanup.
- Compatibility breaks are intentional and reflected in tests or examples.
- Edge cases are handled for empty, tiny, large, sparse, or unexpected
  dtype/shape inputs where relevant.
- Random seeds, ordering assumptions, and counts are explicit where they matter.
- The validation command actually exercises the changed behavior.
- Residual risks and skipped validation are reported plainly.
