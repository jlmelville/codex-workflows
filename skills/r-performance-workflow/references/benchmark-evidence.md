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

Scope relative performance gates before observing results. Name the workload
class each gate governs and report absolute medians beside ratios. For an
abstraction boundary, pair low-operation and scaling-heavy cases, then classify
a repeated regression as fixed per-call cost or scaling cost. Do not waive a
crossed unconditional gate after the fact merely because its absolute cost is
small; retain it as an explicit review decision.

Before optimizing abstraction overhead, use bounded component probes to
separate causes: compare direct and wrapped operations for marginal overhead,
zero- and one-operation end-to-end paths for fixed versus marginal work, and
rich versus minimal result construction when discarded diagnostics may be
costly. Profiles and component microbenchmarks choose targets; representative
whole-operation benchmarks plus the semantic oracle decide whether to keep or
revert the change.

For expensive exploratory benchmark grids, define the evidence threshold and
stop rule before running the full grid. Start with rows likely to distinguish
hypotheses, summarize after each tranche, and skip expensive remaining rows when
they are unlikely to change the decision. Record the stop rationale in the plan
or handoff.

## Callback Work Accounting

For callback-based algorithm benchmarks, define the measured workload boundary
and install fresh external wrappers for each run. Count every physical provider
entry point independently, including standalone, composite, and derivative
callbacks, and increment attempted calls before provider execution. A composite
call remains one composite invocation even when it computes several values;
retain any real standalone calls made in the same mode.

When the logical numerical operation differs from the provider callback that
implements it, record both axes plus the owning phase so setup and
reporting-oracle work cannot be mistaken for algorithm cost. Keep
framework-native counters as a separate consistency witness rather than
replacing either observed view.

Cumulative callback counts are resource totals, not selected-point identities.
When the timed optimizer does not retain the values needed for target histories,
keep tracing out of the measured run and perform an unmeasured deterministic
replay. Match the measured result and physical callback counts exactly, then
identify selected points from final parameter, objective, and realized-step
identity rather than the last callback. Carry selected state across zero steps,
handle improving fallbacks explicitly, and fail closed when the replay
projection does not match the measured run.

## Resumable Evidence Checkpoints

Treat an incremental checkpoint as an evidence cache rather than a list of
outputs. Give it a versioned schema, bind every reusable result to its exact
semantic design, configuration, and canonical input view, validate structural
invariants before reuse, and save completed increments atomically. Exercise
these guards with bounded mutations that must be rejected.

Scale identity controls to the trust and storage boundary. A self-contained
local checkpoint normally does not need hashes for every nested payload or the
exact harness bytes. Preserve a stable content identity for mutable external
inputs and separately stored artifacts, and use a run identifier when files
must be joined. Treat complete-file hashing and byte-stable no-op reruns as
high-assurance or reproducibility checks when file identity itself matters, not
as universal cache-validity requirements.

Capture the producing runtime and toolchain record in the checkpoint and render
later reports from that immutable record. Structurally validate every provenance
field that the report consumes; if provenance must be reconstructed, label it
as reconstruction rather than implying capture during the run.

Treat resumability as a lifecycle state machine. Run the production validator
on the newly initialized zero-result state, each independently persisted valid
prefix, and completion, with required and forbidden fields declared per stage.
Inspect a valid completed state through the minimal read-and-validate dependency
path before loading acquisition-only packages, providers, network clients, or
expensive backends. Exercise that short circuit with later-stage operations
stubbed to fail and at least one genuinely unavailable stage-only dependency.

Define terminal attempts from the numerical result contract rather than from
normal return. Persist success, structured non-success, and thrown conditions
as distinct completed outcomes with their status, messages, diagnostics,
resource use, and timing. Resume should skip every terminal outcome unless an
explicit retry policy says otherwise. Smoke both returned non-success and
thrown paths through save, resume, reporting, and completed replay.

Independent acceptance changes phase authority. A downstream production entry
point must require the accepted upstream state and fail closed on missing or
incomplete evidence; it must not create, repair, or recompute that evidence
unless authority is explicitly reopened. If a later continuation rule depends
on an accepted prior packet, bind that packet as a read-only semantic input,
validate its identity and minimum verdict fields, compute the frozen combination
rule, and render the operand verdicts, combined status, and required action.
Probe representative decision branches and forbidden upstream transitions.

Before cost-bearing provider acquisition or fitting, exercise standalone R
validators with fixtures that preserve provider classes, names, dimnames, and
aggregation shapes. Decide field by field which attributes are semantic and
normalize only incidental ones; follow the metadata-attribute guidance in
[`r-test-hygiene`](../../r-test-hygiene/references/diagnostic-regressions.md#metadata-attributes).

When a checkpoint stores primary per-observation floating evidence and a
redundant aggregate, validate the primary values and calibrate aggregate
consistency to plausible reduction roundoff and the metric's smallest meaningful
resolution. Include the intended row scale or a constructed summation-order
witness when a tiny smoke fixture cannot expose the difference.

## Multi-artifact Output Preflight

Treat every active destination of a multi-artifact evidence command as one
pre-execution contract. Require each explicit path to be a non-missing,
non-empty scalar; define a final-component symlink policy; canonicalize through
existing parents; and reject lexical, relative/absolute, or symlink-parent
aliases before collection or the first write.

Path spelling is not sufficient. Compare platform-appropriate filesystem-object
identity for existing outputs, including hard links, and evaluate prospective
case-fold collisions against the actual destination filesystem rather than the
operating-system name. Any filesystem probe must be private, removed before
collection, and behavior-neutral. Exercise every active-output pairing plus
distinct-file and case-sensitive controls. Rejected configurations must perform
no evidence work and leave files and standard output untouched.

Before an expensive heterogeneous grid, run a tiny representative Cartesian
micro-grid containing every optional schema family through the same final bind,
partition, summary, serialization, persisted-input derivation, and manifest
finalization path as the evidence run. Keep this assembly smoke separate from
scientific evidence; per-mapping smoke tests do not exercise aggregate-only
failures.

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

When a derived artifact controls a decision or is reported by byte hash, retain
the executable transformation and make the persisted primary artifact—not a
higher-precision pre-serialization object—its input. Freeze explicit ordering,
precision, and serialization policy, record the producing command, and rerun
the transformation to check byte identity when that identity is part of the
claim. An output hash identifies the file; it does not preserve its provenance.

## Allocation Evidence

Name the allocation profiler, warmup or JIT policy, and allocation class it can
observe. A zero from warmed `Rprofmem()` means only that the measured run
reported no vector-heap allocation events; it does not prove that R created no
cons cells or performed no allocation work. When a zero is surprising, add a
sanity control that the profiler should detect. If allocation is
decision-critical, select a profiler that observes the relevant class or state
the limitation explicitly.
