# Repository Instructions

This repository is the source of truth for personal Codex skills. User-scoped
runtime copies live under `$HOME/.agents/skills`; tracked links under
`.agents/skills` expose repository-only skills from their canonical `skills/`
sources.

The visible user-authored preamble in `README.md`, between the
`USER-AUTHORED PREAMBLE` HTML comments, is protected text. Preserve it verbatim
and do not move, rewrite, or remove it unless James explicitly requests a change
to that preamble.

Before source-changing maintenance, apply `$repo-update-preflight`, then use
`$codex-skill-repo`'s source-reconciliation overlay for incoming skill-repository
policy and machine-local state compatibility. Never hide or overwrite unrelated
work merely to make the checkout clean. After pulling retrospective helper or
protocol changes, validate this machine's local state with the newly pulled
source helper before judging or mutating records.

For accepted changes in this repo:

- Validate skill changes with `./scripts/validate-skills.sh`.
- Run `./install.sh` when files under `skills/` change. It syncs user-scoped
  skills and validates repository-local links, and may require sandbox approval
  because it writes outside the repo.
- Confirm both skill scopes match source with `./install.sh --check`. The check
  ignores unrelated user-scoped skills not owned by this repo.
- Commit the intended repo changes and push to `origin/main` unless the user
  says otherwise.
- Do not stage or commit unrelated local changes.
