---
name: python-uv-project-workflow
description: Work in Python projects managed with uv. Use when Codex edits, reviews, tests, debugs, or validates uv-managed Python code, dependencies, pyproject.toml, uv.lock, pytest, Ruff, type hints, notebooks, fixtures, or src layouts. Pair with uv-sandbox-workflow when running uv in sandboxes.
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

- Keep behavior fixes, broad formatting, dependency changes, and generated
  artifacts in separate phases unless the user requests a combined sweep.
- Keep comments and documentation about durable contracts or tradeoffs, not
  prompts, conversations, agents, temporary plans, or implementation history.
- When large arrays or sparse data are involved, inspect allocation and storage
  behavior before accepting transformations on hot paths.

## uv Workflow

Prefer project-managed commands:

```sh
uv sync --locked
uv run --locked pytest
uv run --locked pytest tests/<area>
uv run --locked ruff format <paths>
uv run --locked ruff check <paths>
```

Before changing dependencies, inspect dependency groups and lock policy in
`pyproject.toml`. Use `--locked` for behavior-only setup and validation so a
command fails instead of rewriting `uv.lock`. Reserve unlocked `uv sync`,
`uv lock`, and `uv add` for intended dependency changes. Do not edit `uv.lock`
manually.

For nested workspaces, resolver policy, lock metadata, or invalid dependency
metadata warnings, read
[dependency-resolution.md](references/dependency-resolution.md).

When running uv in Codex, follow `$uv-sandbox-workflow` first so mutable uv
caches and downloaded tools live under `/tmp` and network approval is requested
when needed.

## Tests And Validation

Choose validation based on blast radius:

- Focused unit test for one module or bug:
  `uv run --locked pytest tests/test_<area>.py -q`.
- Public behavior or integration change:
  run the focused test plus the nearest integration test.
- Formatting-only Python change:
  `uv run --locked ruff format <paths>` and
  `uv run --locked ruff check <paths>`.
- API, dependency, or broad package change:
  run focused tests first, then `uv run --locked pytest` when feasible; omit
  `--locked` only when an intended dependency change requires lock resolution.

When auditing Ruff config, check whether `select` is replacing Ruff's default
rules. Use `extend-select` for additive choices such as import sorting, or make
the default safety set explicit with rules such as `E4`, `E7`, `E9`, `F`, and
`I`. Decide notebook lint policy explicitly before treating exploratory notebook
findings like package source or test failures.

For behavior changes, state what failed or was missing before and what now
passes or works after. If a command is expensive, optional-data-dependent, or
unavailable, report that honestly and name the command that should be run.

For Python CLIs that accept arbitrary numeric vectors, or for cross-language
objective, gradient, Hessian, or autograd comparisons, read
[numerical-validation.md](references/numerical-validation.md).

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
