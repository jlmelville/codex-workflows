# Repository Instructions

This repository is the source of truth for personal Codex skills. The installed
runtime copy lives under `$HOME/.agents/skills`.

The visible user-authored preamble in `README.md`, between the
`USER-AUTHORED PREAMBLE` HTML comments, is protected text. Preserve it verbatim
and do not move, rewrite, or remove it unless James explicitly requests a change
to that preamble.

For accepted changes in this repo:

- Validate skill changes with `./scripts/validate-skills.sh`.
- Sync installed skills with `./install.sh` when files under `skills/` change.
  This may require sandbox approval because it writes outside the repo.
- Confirm managed installed skills match source with `./install.sh --check`.
  The check ignores unrelated installed skills not owned by this repo.
- Commit the intended repo changes and push to `origin/main` unless the user
  says otherwise.
- Do not stage or commit unrelated local changes.
