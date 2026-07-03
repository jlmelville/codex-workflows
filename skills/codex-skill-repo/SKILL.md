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
   default prompt.
5. Add bundled scripts only when deterministic reuse is worth the extra file.
6. Validate the repository and any new skill folders.
7. Install the updated skills and confirm the installed copies match the source
   repo when that matters.

## Validation

Run the repository validator before committing:

```sh
./scripts/validate-skills.sh
```

For workflow changes, also run the repository's workflow audit if present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

If the generic audit script is not present, run `actionlint`, `zizmor`, and
ShellCheck as applicable.

## Skill Family Growth

Use short prefixes for related skills:

- `r-*` for R package workflows.
- `python-*` for Python package workflows.
- Generic names for cross-language operations such as repository bootstrap,
  dependency PR maintenance, shell quality, and planning.

Prefer adding a new skill when a repeated workflow has clear triggers and
repeatable decisions. Prefer a README note when the knowledge is only useful to
the human maintainer.
