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
