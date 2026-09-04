---
name: r-architecture-audit
description: Audit R package architecture before structural cleanup. Use for package modularity, bloat, dead-code, reachability, coupling, or proportionality reviews.
---

# R Architecture Audit

Produce a checked, report-only architecture map before recommending package-wide
splits, deletions, or rewrites. Treat static metrics as navigation evidence, not
quality scores or automatic refactoring verdicts.

## Audit Boundary

Start from the owner's question and the package's actual public surface. Read
`DESCRIPTION`, `NAMESPACE`, any `Collate` policy, `R/`, relevant compiled or
generated boundaries, tests, vignettes, scripts, and active plans. Record the
current revision and worktree state. Do not edit the package unless the user
separately asks to implement an accepted recommendation.

Use the bundled mapper for a conventional package:

```sh
Rscript "${HOME}/.agents/skills/r-architecture-audit/scripts/r-architecture-map.R" \
  --package . --out /tmp/r-architecture-map
```

The output inventories top-level functions, conservative internal references,
public-root reachability, file coupling, strongly connected components,
complexity, and direct private-test coupling. Read
[audit-method.md](references/audit-method.md) before interpreting the map or
comparing snapshots, or auditing mode and field consumers. For nonstandard
assignment, generated registration, heavy reflection, or runtime plugin systems,
use the mapper only as a high-recall starting point and trace those mechanisms
manually.

## Judgment

- Cross-check function-aware references with repository-wide search. A static
  absence is a deletion candidate, never proof of dead code.
- Trace representative public routes across data ownership, persistence, and
  external-process boundaries. A reachable function or value can still have no
  production consumer.
- Separate source responsibility from filenames. Multi-file cycles, high
  complexity, and large private test surfaces identify where to read; they do
  not require a file split or public API.
- Preserve dynamic dispatch, load hooks, native entry points, generated calls,
  configuration lookup, and non-package consumers unless evidence rules them
  out.
- Prefer removing a confirmed stranded branch or behaviorless variant before
  introducing a new abstraction around it.

## Output

Report the public roots and principal operator paths, cross-file components and
complexity concentrations, unreachable or test-only candidates with confidence
and caveats, value-level non-consumers, and the smallest recommended actions.
Distinguish safe deletion candidates, design questions, and accepted behavior.
If implementation is requested, hand the accepted scope to `$r-package-workflow`
and use `$planning-workflow` for a broad refactor.
