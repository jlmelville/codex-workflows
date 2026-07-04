# Repository Instructions

This repository is the source of truth for personal Codex skills. The installed
runtime copy lives under `${CODEX_HOME:-$HOME/.codex}/skills`.

For accepted changes in this repo:

- Validate skill changes with `./scripts/validate-skills.sh`.
- Sync installed skills with `./install.sh` when files under `skills/` change.
  This may require sandbox approval because it writes outside the repo.
- Confirm source and installed skills match when syncing matters:
  `diff -qr ./skills "${CODEX_HOME:-$HOME/.codex}/skills" -x .system`.
- Commit the intended repo changes and push to `origin/main` unless the user
  says otherwise.
- Do not stage or commit unrelated local changes.
