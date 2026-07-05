---
name: codex-skill-repo
description: Maintain a repository of Codex skills as a source of truth, including skill folder layout, repo validation, installation into ~/.codex/skills, avoiding runtime-state commits, adding new skill families, and keeping skill metadata concise. Use when Codex edits, reviews, installs, validates, documents, commits, or publishes a Codex skill repository.
---

# Codex Skill Repo

Use this for repositories that version Codex skills separately from the active
Codex runtime directory.

## Source Of Truth

- Treat the repository under `~/dev` as source of truth.
- Treat `${CODEX_HOME:-$HOME/.codex}/skills` as installed output.
- Edit, validate, commit, and push in the source repo before or alongside
  installation.
- Install by running the repo's installer, usually `./install.sh`.
- Do not hand-edit installed copies unless diagnosing a sync problem; port useful
  changes back to the source repo immediately.

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

After installing, verify the source and installed skill trees match:

```sh
diff -qr ./skills "${CODEX_HOME:-$HOME/.codex}/skills" -x .system
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

For workflow changes, also run the repository's workflow audit if present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

If the generic audit script is not present, run `actionlint`, `zizmor`, and
ShellCheck as applicable.

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance before
committing. If two scripts are intentionally mirrored across skills, update both
or record why they differ.

Before committing, stage only intended files, inspect `git diff --cached --stat`
and `git diff --cached --name-only`, then commit and push when publishing is in
scope.

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
