# Renovate

Use this reference for Renovate-managed repositories and configuration.

Inspect the Dependency Dashboard issue as a control surface, not as an ordinary
bug. Use it to cross-check open PRs, detected dependency managers, update
groups, file categories, rebase controls, and immortal or blocked updates.

For Python or uv repositories with multiple workspaces, plugin SDKs, or legacy
packages, treat different `requires-python`, `.python-version`,
`pyproject.toml`, and lockfile constraints as possible compatibility islands.
Before recommending broad dependency loosening or root Python requirement
changes, inspect every intentional version boundary and prefer Renovate
`packageRules`, `allowedVersions`, or manager-specific constraint filtering
when one island cannot accept a proposed update.

When editing Renovate config, validate in a safe ladder: JSON syntax first,
Renovate docs for option names and parent sections, then an installed local
`renovate-config-validator` if present. Treat `npx` or other external validator
downloads as networked code execution that needs explicit approval. If used,
prefer a temporary directory containing only the config file over running from
a dirty or private worktree.
