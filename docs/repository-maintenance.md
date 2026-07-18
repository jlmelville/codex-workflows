# Repository Maintenance

This document contains the detailed installation, authoring, validation, and
tooling reference for `codex-workflows`. Start with the repository
[README](../README.md) for installation and retrospective-state setup.

## Skill Shape

Future skills should use this layout:

```text
skills/<skill-name>/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
  assets/
```

Only include `references/`, `scripts/`, or `assets/` when the skill actually
needs them. Prefer concise skills with narrow trigger descriptions. Put
human-facing repository documentation in the README or `docs/`, not inside
individual skill folders.

## Installation Details

Install the source tree into the default Codex home:

```sh
./install.sh
```

To install to a different Codex home:

```sh
CODEX_HOME=/path/to/.codex ./install.sh
```

The installer syncs `skills/*` into `${CODEX_HOME:-$HOME/.codex}/skills`. It
writes a managed-skill manifest at
`${CODEX_HOME:-$HOME/.codex}/codex-workflows-managed-skills.tsv`. On the first
run without a manifest, the current source skill names become the ownership
set; later runs remove only stale skills named in the previous manifest.
Unrelated installed skills are preserved.

Preview changes without replacing installed skills:

```sh
./install.sh --dry-run
```

Confirm that managed installed skills match the source tree, including relevant
file modes:

```sh
./install.sh --check
```

Do not hand-edit installed copies. Port useful diagnostic changes back to the
source repository and reinstall them.

## Validation

Run the repository validator before committing:

```sh
./scripts/validate-skills.sh
```

The validator reports local `actionlint`, `uv`, and `zizmor` versions that do
not match the versions pinned for CI. Treat the report as advisory locally and
run the parity check explicitly before claiming CI-equivalent results:

```sh
./scripts/check-ci-tool-parity.sh --strict
```

Under `CI=true`, the parity check is strict automatically.

It checks skill frontmatter, UI metadata YAML, shell syntax, ShellCheck results,
Ruby/Python/R script syntax, local links, skill references, mirrored files,
executable modes for bundled shell scripts, hard drift findings, installer
behavior, and substantial bundled-script interfaces. The retro-state smoke test
uses temporary fixtures; repository validation never reads the live
`CODEX_WORKFLOWS_STATE_DIR`.

Review skill trigger and metadata shape with:

```sh
./scripts/list-skills.rb
```

Run the advisory bloat and drift audit with:

```sh
./scripts/audit-skill-drift.rb
```

The audit reports always-loaded description budget, long or overlapping skill
descriptions, repeated helper names, repeated command guidance, machine-specific
paths, and repo-relative skill-script references that may break after
installation. Findings are grouped as hard, review, or informational. Accepted
advisory findings live in
[`scripts/audit-skill-drift-triage.tsv`](../scripts/audit-skill-drift-triage.tsv);
each row records the audit section, a row substring to match, and the rationale
for accepting that finding.

Use `--strict-hard --hard-only` for validation that should fail only on hard
installed-runtime problems. Use `--strict` when a cleanup branch should fail if
any untriaged findings remain.

For new or substantially changed skills, also run the system skill quick
validator when its dependencies are available. If it needs Python packages such
as PyYAML, use temporary `uv` state rather than modifying the project.

Markdown templates and documentation are subject to repository-path
validation. Use real existing repository paths in examples, or avoid
placeholder text shaped like a repository-relative path when no such file
exists.

For workflow changes, run the source-tree workflow audit when present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

When adding or changing a manual validation lane, push it, trigger it once with
`gh workflow run`, watch it to completion, and fix setup failures.

## Consistency Surfaces

Maintain the repository across four surfaces:

- **Source validity:** frontmatter, metadata, links, scripts, smoke tests,
  mirrored files, and workflow hardening.
- **Installed validity:** executable commands in installed skills should use
  `${CODEX_HOME:-$HOME/.codex}/skills/...` unless explicitly marked as
  source-repository commands.
- **Cross-platform validity:** shell, Ruby, Python, and R checks should keep
  Linux and macOS behavior in view when scripts become substantial.
- **Drift validity:** duplicated helpers, repeated command prose, overlapping
  triggers, machine-local paths, and large always-read skills need triage rather
  than automatic churn.

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance. If
two scripts are intentionally mirrored, update both or record why they differ.

GitHub Actions runs the repository validation on pushes and pull requests, plus
a lightweight workflow audit. A manual macOS validation job is available
through `workflow_dispatch` for cross-platform checks.

## Publication Checklist

Before publishing an accepted change:

1. Run `./scripts/validate-skills.sh`.
2. Run `./install.sh` when files under `skills/` changed.
3. Run `./install.sh --check`.
4. Stage only intended files.
5. Inspect `git diff --cached --stat` and
   `git diff --cached --name-only`.
6. Commit and push to `origin/main` unless the user says otherwise.

Use `$skill-retro-triage` for accepted Skill Candidate Reports after re-reading
the cited destinations. Personal candidate, ledger, draft, audit, and cadence
state remains beneath `CODEX_WORKFLOWS_STATE_DIR` and must not be committed.

## Local Tooling

Some skills assume these tools may be available in project worktrees:

- `python3` for bundled Python script validation
- Bash 3.2-compatible Bash for bundled shell scripts
- `ruby` for repository validation
- `rg` / `ripgrep` for repository and roxygen source searches
- `shellcheck` for shell script validation
- `perl` for roxygen odd-backtick audits
- `Rscript`
- `air`
- `actionlint`
- `uvx`
- `clang-format`

Project-specific package dependencies still belong in the project repository,
not in this workflow repository.
