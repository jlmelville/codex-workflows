# Benchmark Evidence Script

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

## Resumable Evidence Checkpoints

Treat an incremental checkpoint as an evidence cache rather than a list of
outputs. Give it a versioned schema and bind every reusable result to the exact
frozen design, full per-result specification, and canonical input subset or
view that produced it. Store a stable content identity for the consumed input,
validate every binding before reuse, and save completed increments atomically.

Capture the producing runtime and toolchain record in the checkpoint and render
later reports from that immutable record. If original provenance must be
reconstructed, label it as reconstruction rather than implying it was captured
during the run. Exercise cache guards with bounded mutations to the schema,
design, result specification, and input binding. For an already complete run,
hash the checkpoint and report before and after a resume and require byte-stable
output when no evidence changed.

## Human Review Projection

Treat a human report as a tested projection of the frozen evaluation contract.
Before a decision gate, crosswalk every required evidence field to the artifact
schema and either a rendered summary or an explicit raw-artifact location. Keep
decision-critical disaggregations visible, and compare rendered counts and
values with their stored source using local deterministic assertions where
practical.

Audit every total, peak, and memory label against the exact measured code region
and allocator. Name material exclusions such as result construction,
validation, serialization, accumulated process state, or native allocations
instead of describing a component observation as an end-to-end measurement.

## Allocation Evidence

Name the allocation profiler, warmup or JIT policy, and allocation class it can
observe. A zero from warmed `Rprofmem()` means only that the measured run
reported no vector-heap allocation events; it does not prove that R created no
cons cells or performed no allocation work. When a zero is surprising, add a
sanity control that the profiler should detect. If allocation is
decision-critical, select a profiler that observes the relevant class or state
the limitation explicitly.
