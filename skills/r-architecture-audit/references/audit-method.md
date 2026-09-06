# R Architecture Audit Method

Use this reference for R mapper evidence, snapshot compatibility, and R-specific consumer checks.
The shared [architecture-audit](../../architecture-audit/SKILL.md) owns structural judgment and the
report contract.

## Read The Structural Map

The mapper recognizes conventional top-level assignments in `R/`, obtains
function-aware global references with `codetools` when available, and also
retains references where an internal function is passed as a value. It derives
roots from explicit namespace exports, S3 registrations, export patterns, and
package load hooks. Its report contains:

- `functions.tsv`: active top-level functions, source extent, public-root and
  reachability status, complexity, graph degree, component, and test coupling;
- `edges.tsv`: conservative internal function and higher-order references;
- `file-coupling.tsv`: cross-file edges aggregated by source and target file;
- `sccs.tsv`: recursive components, including the files they cross;
- `private-test-coupling.tsv`: direct parsed references from tests to
  non-exported functions;
- `metadata.tsv`: map format, producer and producer version, and reference
  analysis method used for compatibility checks; and
- `diagnostics.tsv`: duplicate definitions and dynamic constructs requiring
  manual review.

Review both extremes: large reachable components may expose responsibility
coupling, while mutually referring unreachable functions may expose an entire
stranded subsystem that a definition-only search misses.

## Compare Frozen Maps

Freeze the first mapper output before cleanup, then compare it with a later map.
The comparator reads `metadata.tsv` and fails closed unless both reports use its
supported map format and producer version and have the same reference-analysis
method. When maintaining the helpers, increment the producer version for a
semantic mapping change and the format version for an incompatible table
contract, keeping the mapper and comparator constants aligned:

```sh
Rscript "${HOME}/.agents/skills/r-architecture-audit/scripts/r-architecture-diff.R" \
  --before /tmp/r-architecture-baseline \
  --after /tmp/r-architecture-current \
  --out /tmp/r-architecture-diff
```

The comparison reports aggregate deltas and machine-readable changes in
functions, reachability, complexity, edges, cross-file coupling, strongly
connected components, and direct private-test references. Component identity is
based on its member set rather than the mapper's run-local component number.

## Confirm R Reachability Claims

Extend the shared consumer search to package vignettes, generated wrappers, and ignored development
material when relevant. Inspect:

- `get()`, `assign()`, `do.call()`, formula or string dispatch, registries, and
  option-driven lookup;
- S3, S4, R6, native registration, package load hooks, and generated wrappers;
- `Collate` or other source-order behavior and duplicate top-level bindings;
- callbacks passed through lists, environments, closures, or external tools;
  and
- documented or supported private entry points used outside the package.

## Trace R Value Families

For a field, mode, or related evidence family that function reachability cannot
represent, build a reproducible lexical reading set with named patterns:

```sh
Rscript "${HOME}/.agents/skills/r-architecture-audit/scripts/r-value-family-trace.R" \
  --package . \
  --family diagnostics \
  --pattern 'field=diagnostic_mode' \
  --pattern 'mode=trace' \
  --out /tmp/diagnostic-family.tsv
```

The trace scans conventional source, test, and documentation roots and emits one row per matching
file and line, with all matching pattern names, enclosing top-level R function when available, and
source text. Classify the rows using the shared
[boundary and value tracing method](../../architecture-audit/references/boundary-and-value-tracing.md).
