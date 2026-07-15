---
name: codex-skill-repo
description: Maintain a Codex skill repository as source of truth. Use when Codex edits, reviews, installs, validates, documents, commits, or publishes skills, including layout, metadata, runtime install sync, validation scripts, and avoiding runtime-state commits.
---

# Codex Skill Repo

Use this for repositories that version Codex skills separately from the active
Codex runtime directory.

## Source Of Truth

- Treat the version-controlled source repository, not the installed runtime
  copy, as source of truth.
- Treat `${CODEX_HOME:-$HOME/.codex}/skills` as installed output.
- Edit, validate, commit, and push in the source repo before or alongside
  installation.
- Install by running the repo's installer, usually `./install.sh`.
- Confirm managed installed skills with `./install.sh --check`; installer
  checks should ignore unrelated installed skills outside the repo's ownership
  manifest.
- Do not hand-edit installed copies unless diagnosing a sync problem; port useful
  changes back to the source repo immediately.

## Consistency Surfaces

Check this repo across four surfaces:

1. Source validity: frontmatter, metadata, links, scripts, smoke tests, mirrored
   files, and workflow hardening.
2. Installed validity: executable commands in installed skills should use
   `${CODEX_HOME:-$HOME/.codex}/skills/...` unless explicitly marked as
   source-repository commands.
3. Cross-platform validity: shell, Ruby, Python, and R behavior should account
   for Linux and macOS when scripts become substantial.
4. Drift validity: duplicated helpers, repeated command prose, overlapping
   triggers, machine-local paths, and large always-read skills need triage
   rather than automatic churn.

## Repository Shape

Keep the top level small:

```text
skills/
scripts/
install.sh
README.md
.github/
```

Each skill folder should contain only files used by the agent:

```text
skills/<skill-name>/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
  assets/
```

Only create `references/`, `scripts/`, or `assets/` when the skill needs them.
Put human-facing repo documentation in the repository README, not inside skill
folders.

## Do Not Commit

Never copy or commit raw Codex runtime state:

- `auth.json`
- sessions, history, attachments, logs, sqlite state
- caches and installed plugin caches
- temporary files from validation or experiments
- machine-specific secrets or credentials
- retrospective inbox, archive, accepted records, drafts, ledgers, learning
  audits, or cadence state from `CODEX_WORKFLOWS_STATE_DIR`

Review `.gitignore` before staging whenever the repo was created from a
runtime directory.

## Adding Skills

1. Read the system `skill-creator` guidance.
2. Initialize new skills with `init_skill.py` when available.
3. Keep `SKILL.md` concise and put trigger conditions in frontmatter
   `description`.
4. Add `agents/openai.yaml` with a short display name, short description, and
   default prompt. When passing `$skill-name` through shell arguments, use
   single quotes or escape `$`, then inspect the generated file to confirm the
   default prompt contains the literal skill invocation.
5. Add bundled scripts only when deterministic reuse is worth the extra file.
6. Validate the repository and any new skill folders.
7. Install the updated skills and confirm the installed copies match the source
   repo when that matters.

## Promoting Local Guidance

When turning repo-local `.agents/skills`, `docs/agents`, `prompts/`,
`AGENTS.md`, or `PLANS.md` material into global skills:

1. Inventory the local guidance and classify it as generic, language-specific,
   repo-specific, stale duplicate, or ordinary engineering judgment.
2. Promote only reusable, non-obvious workflows that are likely to recur.
3. Generalize names, triggers, paths, and examples so the new skill does not
   leak one repo's domain model.
4. Leave domain-specific contracts local until the same pattern appears in
   another repo.
5. When promoting a stable prompt into a skill, replace the old prompt file with
   a short pointer if existing workflows may still link to that path.
6. Replace duplicated local rules with short references to the global skill when
   editing that repo is in scope.

## Validation

Run the repository validator before committing:

```sh
./scripts/validate-skills.sh
```

After installing, verify managed installed skills match source:

```sh
./install.sh --check
```

For new or substantially changed skills, also run the system quick validator:

```sh
python /path/to/quick_validate.py skills/<skill-name>
```

If the validator needs Python packages such as PyYAML, run it through `uv` and
follow `$uv-sandbox-workflow` so caches live under `/tmp`.

For bundled scripts, prefer validation that does not write artifacts into
`skills/`, such as in-memory parsing or caches under `/tmp`. Run representative
behavior checks and remove any generated test artifacts such as `__pycache__`
before staging.

Markdown templates and documentation are subject to repository-path
validation. Use real existing repository paths in examples, or avoid
placeholder text shaped like a repository-relative path when no such file
exists.

For workflow changes from this source repository root, run the workflow audit if present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

When adding/changing a manual validation lane, push it, trigger it once with
`gh workflow run`, watch to completion, and fix setup failures.

Use `${CODEX_HOME:-$HOME/.codex}/skills/...` command paths inside installed
skill workflows unless the text explicitly says it is source-repository only.

If the generic audit script is not present, run `actionlint`, `zizmor`, and
ShellCheck as applicable.

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance before
committing. If two scripts are intentionally mirrored across skills, update both
or record why they differ.

Run the advisory drift and bloat audit before or after consolidation work:

```sh
./scripts/audit-skill-drift.rb
```

Use `--strict-hard --hard-only` for validation that should fail only on hard
installed-runtime problems. Use `--strict` only when the current branch is meant
to remove all untriaged findings. The audit surfaces hard, review, and
informational findings for long descriptions, overlapping trigger surfaces,
repeated helper names, repeated command guidance, machine-specific paths, and
repo-relative skill script references. Accepted advisory findings live in
`scripts/audit-skill-drift-triage.tsv`; each row records the audit section, a
row substring to match, and the rationale for accepting that finding.

Before committing, stage only intended files, inspect `git diff --cached --stat`
and `git diff --cached --name-only`, then commit and push when publishing is in
scope.

Use `$skill-retro-triage` for accepted Skill Candidate Reports after re-reading cited destination files.

## Deferred Maintenance Memory

For observations about this skill repository that should survive chat
compaction but are not yet ready for direct skill, script, or prompt changes,
use the external maintenance ledger beneath `CODEX_WORKFLOWS_STATE_DIR` as
defined by `$skill-retro` in
`skills/skill-retro/references/state-protocol.md`. Never put personal ledger,
inbox, archive, accepted-record, draft, audit, or cadence state in this source
repository. Review external state during periodic learning-process
retrospectives and when a cluster of skill-retro changes suggests consolidation
or script opportunities. Source validity must not depend on that state being
available.

## Skill Family Growth

Use short prefixes for related skills:

- `r-*` for R package workflows.
- `python-*` for Python package workflows.
- `local-*` for durable James-local workflows tied to local files or data
  surfaces that recur across sessions.
- Generic names for cross-language operations such as repository bootstrap,
  dependency PR maintenance, uv sandbox execution, shell quality, and planning.

Prefer adding a new skill when a repeated workflow has clear triggers and
repeatable decisions. Prefer a README note when the knowledge is only useful to
the human maintainer.
