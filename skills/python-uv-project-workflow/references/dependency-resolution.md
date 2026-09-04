# uv Dependency Resolution

Use this when resolver policy, nested workspaces, lock metadata, or invalid
remote dependency metadata affects a uv project.

## Nested Workspaces

For multi-workspace repositories or nested uv projects, enumerate every
`pyproject.toml` before changing resolver settings such as `[tool.uv]`
`exclude-newer`. Root settings may not apply when a nested project is run from
its own directory.

After changing resolver settings, run `uv --quiet --no-progress lock` and then
`uv --quiet --no-progress lock --check` in each affected workspace. Lockfile
metadata can change even when package versions do not.

## Invalid Remote Metadata

For uv warnings about invalid dependency metadata or version specifiers,
distinguish the resolved lock state from remote release metadata. The warning
may come from historical releases that were inspected but not selected.

After identifying the package, use
`uv tree --locked --invert --package <name>` to confirm the local reverse
dependency path before recommending local dependency changes.
