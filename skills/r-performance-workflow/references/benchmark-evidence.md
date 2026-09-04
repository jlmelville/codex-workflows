# Benchmark Evidence

Use the bundled harness for a simple case file that should emit raw timing CSV
and plan-ready Markdown:

```sh
Rscript "${HOME}/.agents/skills/r-performance-workflow/scripts/benchmark-evidence.R" \
  path/to/cases.R --reps 5 --seed 1 --out bench/results
```

The case file must define `benchmark_cases`, a non-empty named list of
zero-argument functions. It may also define `benchmark_setup()` and
`benchmark_metadata`, a named list of scalar values.

```r
set.seed(42)
x <- matrix(rnorm(10000), ncol = 10)

benchmark_metadata <- list(dataset = "synthetic", nrow = nrow(x), ncol = ncol(x))

benchmark_cases <- list(
  baseline = function() old_fn(x),
  current = function() new_fn(x)
)
```

The first case is the default baseline; use `--baseline NAME` to select another
case. The command writes `<prefix>.csv` with per-repetition timings and
`<prefix>.md` with the command, metadata, median/minimum/maximum elapsed time,
and relative speed versus the baseline. Treat the generated files as benchmark
evidence, not package validation, and follow the active plan or repository
policy when deciding whether to retain them.

## Gate And Probe Design

Before treating a selector as one factor, resolve conditional defaults. Compare a coherent public profile separately
from fixed-policy variants, and use controlled variants for component-level causal claims.

For a causal size-sensitivity claim, vary size inside a self-similar objective family, evaluate with a size-invariant
witness, and include an analytically scaled-rate trajectory oracle. Use heterogeneous suites to test transfer only
after the within-family mechanism is identified; changing geometry, units, and size together cannot identify size.

For an anisotropic synthetic objective with a known minimizer or meaningful residual partition, pair relative objective
reduction with normalized parameter distance or per-component residual progress. Reconcile disagreements before ranking
methods; stiff directions can dominate the objective gap while other directions remain effectively unchanged.

For an adaptive method, report configured-rate transfer separately from fixed-budget performance. Measure internal
compensation at matched progress and the iterations required to acquire it. An effective rate that stabilizes only
after proportionally more iterations demonstrates self-calibration, not iteration-count invariance.

For component ablations whose methods transform gradient magnitude differently, match realized first-step
displacement at a declared reference input and freeze that calibration across the scaling study. Prove claimed
limiting-case identities and run objective-scale and relevant symmetry trajectory oracles before attributing paired
outcomes to the changed component.

When compared variants use different momentum recurrences, control sustained coherent-gradient response as well as the
first step. Normalize the recurrence, compensate the configured rate for its momentum-dependent gain, or report both
responses; otherwise an apparent memory effect may be an implicit update-scale change.

When a strict bridge requires full-trajectory identity, reuse the exact implementation and arithmetic operation order;
algebraically equivalent rewrites can amplify roundoff over long nonlinear trajectories. Pair a short prefix smoke with
a full baseline checkpoint. If only invariant outcomes matter, predeclare tolerant witnesses instead of requiring exact
trajectory reproduction.

Scope relative gates before observing results, name their workload class, and report absolute medians beside ratios.
Retain crossed unconditional gates as explicit review decisions even when their absolute cost is small.

When pilot responses select a reduced panel, apply the final feature transform and numerical-invariance rule first.
Derive feasible capacity after structural caps and require every selected unit to retain a downstream feature.

Freeze each case's evaluative or diagnostic role before the grid. Retain raw diagnostic outcomes, but report
role-specific denominators so universally solved or unsolved probes do not silently control an aggregate ranking.

Use bounded direct/wrapped, zero/one-operation, scaling-heavy, and rich/minimal-result probes to separate costs.
Profiles choose targets; representative whole-operation benchmarks plus the semantic oracle decide what to keep.

For expensive grids, predeclare the evidence threshold and stop rule, start with distinguishing rows, and summarize
each tranche. Skip rows unlikely to change the decision and record the stop rationale in the plan or handoff.

## Callback Work Accounting

Define the measured workload boundary and install fresh wrappers for each run. Count attempted physical provider
entries before execution; a composite invocation remains one call while real standalone calls remain visible.

When logical numerical work differs from its provider callback, record both axes and the owning phase. Keep native
counters as a separate consistency witness so setup and reporting work cannot be mistaken for algorithm cost.

Callback totals do not identify selected points. Keep tracing outside the timed run, replay deterministically, and
require exact result and callback-count agreement; identify selected state from parameters, objective, and realized step.
Carry state across zero steps, handle improving fallbacks explicitly, and fail closed on projection mismatch.

When termination can restore, average, project, or replace the final iterate, apply the
[result-identity contract](../../r-package-workflow/references/public-api-contracts.md#result-identity-and-diagnostic-value), audit the return, and name which point owns `solved`.

## Search-Budget Exit Diagnosis

Treat a local evaluation cap as a hypothesis, not a diagnosis. Replay beyond it before recommending more budget, then
trace objectives, directional derivatives, parameter displacement, and initial-step choices through the changed exit.

Compare expected objective and parameter changes with their floating-point spacing. Distinguish an uninformative
interpolation initializer from an acceptance condition that no representable step can satisfy.

## Allocation Evidence

Name the allocation profiler, warmup or JIT policy, and allocation class it can
observe. A zero from warmed `Rprofmem()` means only that the measured run
reported no vector-heap allocation events; it does not prove that R created no
cons cells or performed no allocation work. When a zero is surprising, add a
sanity control that the profiler should detect. If allocation is
decision-critical, select a profiler that observes the relevant class or state
the limitation explicitly.
