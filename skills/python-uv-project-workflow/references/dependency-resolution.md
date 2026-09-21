# uv Dependency Resolution

Use this for CI interpreter selection, package-manager migration, resolver
policy, nested workspaces, lock metadata, or invalid remote dependency metadata.

## CI And Package-Manager Migration

Observe the interpreter used by the actual uv validation command; a setup-step
label does not prove that a Python matrix selected the intended runtime. When
changing lock validation, exercise stale project metadata against an unchanged
lock and require failure without repair. `--locked` checks freshness;
`--frozen` skips that check. Follow the current
[CI integration](https://docs.astral.sh/uv/guides/integration/github/) and
[locking semantics](https://docs.astral.sh/uv/concepts/projects/sync/).

Before replacing dependency manifests or package managers, inventory consumers:
scanners, dependency bots, release jobs, caches, and scripts. Update each
affected consumer to the new source or a deliberate compatibility export, then
exercise its entry point. Keep this bounded to actual consumers; a reporting
matrix for every package is unnecessary.

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
