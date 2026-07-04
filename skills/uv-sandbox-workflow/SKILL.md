---
name: uv-sandbox-workflow
description: Run uv and uvx reliably in Codex-managed sandboxes and restricted filesystems, including writable cache/tool/Python directories, network approval decisions, uv run --with, uvx, uv sync, uv lock, uv python, and avoiding false starts from read-only home caches or blocked dependency downloads. Use whenever Codex needs to execute uv, uvx, or uv-managed Python commands.
---

# uv Sandbox Workflow

Use this before running `uv`, `uvx`, or `uv`-managed Python commands in a
Codex environment.

## First Command

Assume the default uv cache under the home directory may be read-only. Put uv's
mutable state under `/tmp` before the first uv command:

```sh
export UV_CACHE_DIR="${UV_CACHE_DIR:-${TMPDIR:-/tmp}/uv-cache}"
export UV_TOOL_DIR="${UV_TOOL_DIR:-${TMPDIR:-/tmp}/uv-tools}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-${TMPDIR:-/tmp}/uv-python}"
```

Use these exports in the same command invocation when the shell state may not
persist:

```sh
UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" \
UV_TOOL_DIR="${TMPDIR:-/tmp}/uv-tools" \
UV_PYTHON_INSTALL_DIR="${TMPDIR:-/tmp}/uv-python" \
uv run --with pyyaml python script.py
```

## Network Decision

If the command is likely to download packages, tools, lock metadata, or Python
distributions, request network approval up front instead of trying once and
rerunning after DNS failure. This commonly includes:

- `uv run --with <package> ...`
- `uvx <tool>` or `uv tool run <tool>`
- `uv sync`
- `uv lock`
- `uv add`
- `uv python install`
- first use of a tool or dependency in a clean `/tmp` cache

If the project already has dependencies and a populated cache, a normal sandbox
run may be enough. If it fails with DNS, registry, index, or download errors,
rerun with escalation.

## Project Writes

Understand where uv will write before running:

- `uv sync` usually writes a project virtual environment such as `.venv`.
- `uv lock` writes `uv.lock`.
- `uv add` edits `pyproject.toml` and `uv.lock`.
- `uv run --with` can be kept temporary when no project dependency change is
  intended.
- `uv python install` writes to `UV_PYTHON_INSTALL_DIR`.

Do not run project-mutating commands in a user repo unless that mutation is part
of the task.

## Preferred Patterns

If a one-off tool is already installed and acceptable for the repository, prefer
the installed binary before `uvx` to avoid avoidable network and tool-cache
downloads. For example, run `zizmor` directly when present; use `uvx zizmor`
only as the fallback.

For one-off tool execution:

```sh
UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" \
UV_TOOL_DIR="${TMPDIR:-/tmp}/uv-tools" \
uvx tool-name ...
```

For one-off Python dependencies:

```sh
UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" \
UV_TOOL_DIR="${TMPDIR:-/tmp}/uv-tools" \
UV_PYTHON_INSTALL_DIR="${TMPDIR:-/tmp}/uv-python" \
uv run --with package-name python -c '...'
```

For helper scripts with undeclared Python dependencies, use `uv run --with`
instead of installing into the system Python:

```sh
UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" \
UV_TOOL_DIR="${TMPDIR:-/tmp}/uv-tools" \
UV_PYTHON_INSTALL_DIR="${TMPDIR:-/tmp}/uv-python" \
uv run --with pyyaml python path/to/helper.py args...
```

For project commands, keep the project as the working directory and still set
the writable uv directories:

```sh
UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" \
UV_TOOL_DIR="${TMPDIR:-/tmp}/uv-tools" \
UV_PYTHON_INSTALL_DIR="${TMPDIR:-/tmp}/uv-python" \
uv sync
```

## After Running

Report whether the command required network approval, changed project files, or
used temporary uv state. If a command used `/tmp` caches, do not imply the result
will remain available across sessions.

If `uvx <tool>` fails with DNS, registry, or package-download errors, classify
that as environment/tool acquisition failure, not as a finding from the tool
itself. Retry with network approval or use an installed binary when available.
