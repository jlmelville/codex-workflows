# Repository Validation

Use this reference when a skill-repository change needs more than the core
validator and installed-copy check.

## Skill And Script Validation

For new or substantially changed skills, run the system quick validator when
available:

```sh
python /path/to/quick_validate.py skills/<skill-name>
```

If the validator needs Python packages such as PyYAML, run it through `uv` and
follow `$uv-sandbox-workflow` so caches live under `/tmp`.

For bundled scripts, prefer validation that does not write artifacts into
`skills/`, such as in-memory parsing or caches under `/tmp`. Run representative
behavior checks and remove generated test artifacts such as `__pycache__`
before staging.

Markdown templates and documentation are subject to repository-path
validation. Use real existing repository paths in examples, or avoid
placeholder text shaped like a repository-relative path when no such file
exists.

## Workflow Validation

Use `${CODEX_HOME:-$HOME/.codex}/skills/...` command paths inside installed
skill workflows unless the text explicitly says it is source-repository only.

If the repository's generic workflow audit is unavailable, run `actionlint`,
`zizmor`, and ShellCheck as applicable.

When adding or changing a manual validation lane, push it, trigger it once with
`gh workflow run`, watch it to completion, and fix setup failures.

## Shared Policy And Mirrors

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance before
committing. If two scripts are intentionally mirrored across skills, update
both or record why they differ.

## Drift Audit

Run the advisory drift and bloat audit before or after consolidation work:

```sh
./scripts/audit-skill-drift.rb
```

Use `--strict-hard --hard-only` for validation that should fail only on hard
installed-runtime problems. Use `--strict` only when the current branch is
meant to remove all untriaged findings. The audit surfaces hard, review, and
informational findings for long descriptions, overlapping trigger surfaces,
repeated helper names, repeated command guidance, machine-specific paths, and
repo-relative skill script references.

Accepted advisory findings live in `scripts/audit-skill-drift-triage.tsv`;
each row records the audit section, a row substring to match, and the rationale
for accepting that finding.

## Pre-Commit Review

Before committing, stage only intended files and inspect:

```sh
git diff --cached --stat
git diff --cached --name-only
```

Commit and push only when publishing is in scope.
