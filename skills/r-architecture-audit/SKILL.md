---
name: r-architecture-audit
description: Audit R package structure or diffs with R-specific reachability, dispatch, and mapping tools. Use for package modularity, dead-code, coupling, or simplification reviews.
---

# R Architecture Audit

Read [architecture-audit](../architecture-audit/SKILL.md) for the shared scope, authority, consumer
evidence, simplification judgment, and report contract. Apply this extension to R packages; if the
general skill routed here, continue with its already-loaded contract.

## Audit Boundary

Establish R package roots from `DESCRIPTION`, `NAMESPACE`, any `Collate` policy, and `R/`. Include
compiled or generated boundaries, tests, vignettes, scripts, and active plans as relevant. For a
bounded diff, trace the affected package routes; a full package map is useful when reachability or
cross-file structure is part of the question.

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

## R-Specific Judgment

- Confirm S3, S4, R6, nonstandard evaluation, package hooks, native registration, and supported
  non-exported entry points using the R-specific checks in the audit method.
- For base-R, dependency, or native replacements, preserve missing-value behavior, vector recycling,
  attributes and classes, ordering, sparse representations, numerical tolerances, and allocation
  costs where applicable. Use `$r-performance-workflow` when measured speed or memory claims matter.

## R Evidence And Handoff

Attach relevant mapper or comparison evidence to the shared report, including namespace roots,
dynamic-consumer caveats, and direct private-test coupling. If implementation is requested, hand
the accepted scope to `$r-package-workflow`.
