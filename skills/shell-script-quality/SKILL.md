---
name: shell-script-quality
description: Review, write, and harden shell scripts for reliability, portability, validation, quoting, error handling, executable bits, ShellCheck, Bash syntax, command availability, and safe filesystem operations. Use when Codex edits .sh files, install scripts, CI snippets, or shell-heavy automation.
---

# Shell Script Quality

Use this for shell scripts and shell-heavy CI snippets.

## Script Contract

Start by identifying:

- supported shell (`bash`, POSIX `sh`, or another shell),
- expected working directory,
- required tools,
- inputs and arguments,
- files or directories the script may create, overwrite, or delete,
- intended failure behavior.

Use `#!/usr/bin/env bash` only for Bash scripts. Do not use Bash-only features
in scripts that claim POSIX `sh` compatibility.

## Bash Defaults

For Bash automation, prefer:

```sh
set -euo pipefail
```

Then handle expected nonzero commands explicitly with `if`, `case`, or `|| true`
where silence is intentional. Avoid letting `set -e` obscure a meaningful
failure message.

## Bash Portability

If a script may run under macOS `/bin/bash`, target Bash 3.2 unless the workflow
explicitly installs and invokes a newer Bash. Avoid Bash 4+ features such as
`mapfile`, `readarray`, `local -n`, and `declare -n`; use `while read` loops and
ordinary arrays instead.

## Robust Patterns

- Quote expansions unless word splitting is required.
- Use arrays for argument lists in Bash.
- Use `mktemp` for temporary files and clean them up with `trap` when needed.
- Check required commands with `command -v` and fail clearly if they are
  mandatory.
- Validate arguments before doing work.
- Prefer explicit paths and scoped deletes over broad globs.
- Avoid `eval` and command construction from untrusted input.
- Keep parsing simple; use a language with structured libraries when shell would
  become ad hoc parsing.

## Repository Integration

- Keep scripts executable when they are meant to be run directly.
- Include scripts in the repository's main validation command.
- Run ShellCheck in CI when the repository contains shell scripts.
- For GitHub Actions snippets, apply `$github-actions-hardening` too.

## Checks

Run:

```sh
bash -n path/to/script.sh
shellcheck path/to/script.sh
```

Also run representative behavior checks:

```sh
path/to/script.sh --help
path/to/script.sh expected-mode
path/to/script.sh invalid-mode
```

For install or sync scripts, test against a temporary target when possible
before touching live directories.

## Review Focus

Prioritize findings that can cause data loss, hidden failures, incorrect
success exits, bad quoting, unsafe deletes, broken CI behavior, or scripts that
depend on unavailable tools without a clear error.
