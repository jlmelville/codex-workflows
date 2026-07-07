---
name: r-performance-workflow
description: Run phased R package performance optimization work with benchmarks, semantic validation, execution plans, and before/after evidence. Use when Codex works on R package speed, memory, allocation, parallelism, Rcpp performance, benchmark scripts, baseline/current comparisons, or plan-driven optimization phases.
---

# R Performance Workflow

Use this skill for performance work in R packages where evidence must survive
across agents and sessions.

## First Pass

1. Apply `$r-package-workflow`; if compiled code is involved, also apply
   `$r-rcpp-package`.
2. Inspect the active plan, handoff, or benchmark notes before editing. Search
   ignored paths too:

   ```sh
   rg --files -uu | rg '(^|/)plans?/|performance|benchmark|bench|EXECPLAN|handoff'
   ```

3. Capture current worktree state and do not mix unrelated cleanup with
   performance work.
4. Define the acceptance question before editing: what must stay semantically
   identical, what speed or allocation evidence is expected, and what benchmark
   is strong enough to justify the change.

## Phase Discipline

Prefer one scoped optimization per phase. For each phase:

1. Record baseline behavior and benchmark evidence before editing unless a
   trustworthy baseline artifact already exists.
2. Make the smallest implementation change that targets the bottleneck.
3. Run focused semantic validation before interpreting timings.
4. Benchmark current versus baseline or old wrapper with identical inputs,
   seeds, thread counts, and repetitions.
5. Audit generated-file churn when roxygen, Rcpp attributes, or package metadata
   changed.
6. Update the active plan with files changed, validation, benchmark table,
   decision, residual risk, and next phase.
7. Stop at a coherent boundary when the next optimization is separable.

Do not claim a performance win from smoke tests, tiny toy data, or noisy single
runs. Use smoke benchmarks to prove the harness works; use evidence benchmarks
to justify source decisions.

When adding a permanent developer benchmark harness under `scripts/` or a
similar repo-local path, document it adjacent to the script. State whether it is
developer evidence rather than package validation, list required and optional
dependencies or datasets, give a tiny smoke command distinct from evidence
benchmark commands, and describe where generated CSV or other benchmark
artifacts may be written and whether they should be committed.

Do not move code into C++ or a lower-level path merely because it looks
optimizable. Require benchmark evidence that the R path is the relevant
bottleneck, and record explicit defer/continue decisions for plausible but
unproven optimizations.

For new optimizer or algorithm method profiles, keep experimental variants as
internal prototypes until benchmark evidence, failure diagnostics, and
complementarity against existing methods justify making them public documented
choices. Do not graduate a method on raw speed alone.

## Semantic Guardrails

Performance changes must preserve user-visible behavior unless the plan
explicitly accepts a behavior change. Before benchmarking, verify relevant
semantics:

- output shape, type, names, ordering, missing-value handling, and tolerances;
- random seed and thread-count reproducibility contracts;
- sparse, dense, logical, tiny, and invalid-input behavior when relevant;
- public API behavior before private helper details.

Prefer exported API tests. Private-helper tests are acceptable only when they
protect a subtle performance-path invariant that is hard to reach publicly.

## Benchmark Evidence

Capture enough metadata for a future agent to interpret the result:

- package/repo commit or worktree state;
- R version and platform;
- CPU/thread settings and BLAS/OpenMP notes when relevant;
- seed, data dimensions, data source, repetitions, and warmup choice;
- exact command used to run the benchmark;
- baseline/current labels and result table.

Use base R `system.time()` when adding benchmark dependencies is undesirable.
The bundled script can run a simple case file and emit CSV plus plan-ready
Markdown:

```sh
Rscript <skill-dir>/scripts/benchmark-evidence.R path/to/cases.R --reps 5 --seed 1 --out bench/results
```

The case file must define `benchmark_cases`, a named list of zero-argument
functions. It may optionally define `benchmark_setup()` and
`benchmark_metadata`, a named list of scalar values.

Example case file:

```r
set.seed(42)
x <- matrix(rnorm(10000), ncol = 10)

benchmark_metadata <- list(dataset = "synthetic", nrow = nrow(x), ncol = ncol(x))

benchmark_cases <- list(
  baseline = function() old_fn(x),
  current = function() new_fn(x)
)
```

Report median elapsed time and relative speed versus the baseline label. If
results are noisy, say so and record what stronger workload is needed.

For expensive exploratory benchmark grids, define the evidence threshold and
stop rule before running the full grid. Start with rows likely to distinguish
hypotheses, summarize after each tranche, and skip expensive remaining rows when
they are unlikely to change the decision. Record the stop rationale in the plan
or handoff.

## Plan And Handoff Updates

When an execution plan is active, update durable state after every phase:

- phase goal and implementation summary;
- semantic validation commands and results;
- benchmark command, metadata, and table;
- generated-file audit results when generated artifacts may have changed;
- decision: keep, revert, broaden testing, or continue;
- if tracked experiment code is reverted while benchmark scripts or results are
  kept, state whether retained artifacts still run against current `HEAD`, are
  evidence-only, or depend on reverted local APIs;
- explicit deferrals with the evidence threshold needed to revisit them;
- next recommended phase and guardrails.

Use `$planning-workflow` for handoff format and local plan artifact discipline.
Do not rely on chat history to preserve benchmark interpretation.
