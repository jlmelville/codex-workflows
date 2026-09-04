# Numerical Reproduction Work Packets

Use this reference when reproducing a layered numerical research method whose
failure could arise from transcription, solver algebra, operators, geometry,
regularization, estimated intermediate fields, or the published finite model.

## Map The Implemented Method Boundary

Trace the selected public method through resolution, initialization, callback
budgets, transitions, recovery, finalization, caches, and returned state. Mark
each phase owning a formula or callback and apply equation and resource oracles
there. Treat unused mathematical terms and unexplained norm or scale changes as
transcription signals; an unmapped owning phase leaves the audit incomplete.
When a harness adds an external convergence witness while preserving
criterion-owned best-point restoration, use that witness to select a compatible
restored point. Keep endpoints optimized for another property separately named
for continuation or audit rather than silently returning them as solved.

## Separate Numerical Policy Layers

Keep raw algebra, the implementation selected by the current public policy,
safeguarded variants, approximate methods, and later globalization in distinct
evidence packets. Invoke the actual selected implementation for policy evidence
rather than copying its fallback logic into a probe. Seed or capture required
callbacks once, account for diagnostic work outside benchmark cost, and retain
one row for every upstream-eligible point even when a narrower raw operation is
unavailable. Compare layers only where both objects exist; record unavailable
comparison explicitly.

When the real implementation returns a reason that collapses materially
different internal branches, preserve its result and replay only the smallest
pure deterministic predicate that owns the distinction on the exact captured,
validated input. Do not replay provider callbacks, repairs, or the full fallback
algorithm, and record discriminator work separately. Before assigning a cause,
enumerate the reachable histories that map to the observed predicate and final
reason. If later finalization makes that mapping non-unique, keep primary-result
validity separate and report causal provenance as unavailable or ambiguous.

## Publication-First Source Comparison

For an inherited numerical method, preserve behavior with independent oracles.
Before inspecting other implementations, map the publication's states,
equations, invariants, and derivable formulas, and freeze a tentative target.

Classify differences as publication-specified, publication-derivable,
safeguard, implementation choice, compatibility behavior, extension, or
unresolved. Source disagreement needs a mathematical, safety, or contract
witness before it is a defect. Separate characterization, neutral
restructuring, and correctness changes; use the
[legacy numerical oracle firewall](../../r-test-hygiene/references/numerical-contracts.md#backend-versions-and-legacy-oracle-firewalls)
for migration evidence without preserving obsolete implementation expression.

## Decompose Before Tuning

Inventory equations, solver, kernel, topology, regularization, intermediate
estimator, sampling and noise, objective, and resource model. For each phase,
hold other layers fixed and name one causal question, local invariant, and stop
gate. Plots do not replace local residuals or compatibility conditions.

Before a multi-point oracle runs, materialize its candidate universe in a
selection manifest separate from results. Record provenance, eligibility,
exclusions, optimizer metadata, and deduplication; run only eligible unique
points with stable join keys. Probe early stops and inapplicable references
without fake result rows.

## Review-Complete Checkpoints

Before an expensive run, derive checkpoint fields from its claims and review
questions. Distinguish restart caches from review packets; the latter retain
frozen settings, stable identity or bounded regeneration, upstream witnesses,
downstream diagnostics, deterministic selections, and reviewable artifact
paths. Keep large reacquirable inputs disposable.

Read the checkpoint through its intended review path before discarding live
state. A successful write or resumable cache does not prove that another
process can audit the claims.

For frozen sparse local-block topology, enumerate exact allowed support before
solves and forecast candidate and intermediate allocations from it. Account
separately for source payload, checkpoints, graph, buffers, sparse additions,
and solver workspace; label remaining heuristics. Calibrate timing and
convergence per material operator class; baseline projections cover only the
exercised class. Rank-, nullity-, or conditioning-changing constructions need a
representative smoke point or explicitly unverified runtime classification.

## Oracle Ladder

Move from the most algebraic component outward:

| Phase | Controlled witness | Gate |
| --- | --- | --- |
| Equation equivalence | Independent transcription or residual identity | Stop on algebra mismatch |
| Minimal one-dimensional oracle | Exact geometry and intermediate fields | Stop on solver or sign failure |
| Structured multidimensional oracle | Exact grid, graph, and fields | Local invariants must survive dimension |
| Kernel and regularization controls | One parameter family at a time | Continue only after scale is identified |
| Unstructured oracle | Exact fields on irregular samples | Separate geometry from estimation |
| Graph corruption | Controlled topology defects | Attribute sensitivity before repair |
| Estimated intermediate fields | Fixed verified downstream pipeline | Stop if the estimator violates its own preconditions |
| Sample and noise scaling | Predeclared bounded matrix | Limit claims to the exercised regime |

For a dense generalized-eigen oracle with known null under positive diagonal
mass, form the symmetric operator and transformed null `M^(1/2) v0`, solve in
its orthogonal complement, then map back. Do not drop one aligned vector when
low modes may cluster. Check generalized residuals, mass centering and
orthogonality, map-back, and invariant-span agreement.

Before scoring an exact-null control, check identifiability and truth membership.
Remove structural nulls, compare remaining nullity with target dimension, and
preserve excess-null cases as underidentified or invalid. Do not score an
arbitrary basis or tune the fixture toward a favorable representative.

Record negative results; each gate chooses repair, an upstream-precondition
stop, or a separate method-development decision.

## Audit Generalized Mass Semantics

For `B y = lambda M y` with positive diagonal `M`, separate the symmetric
transform from mass meaning. If `B = R'R` has method-owned invariant-indexed
rows, inventory interpretable row equation changes and column masses, classify
numerator versus mass changes before a sweep, and never transfer those semantics
to an arbitrary factorization. Derive Rayleigh constraints, interpret symmetric
and mapped-back coordinates, and test masses under scaling, reweighting, support,
and permutation before claiming an observation measure.

Call `M` graph degree only when a nonnegative affinity or equivalent graph
construction derives that diagonal. Likewise, require a corresponding model
derivation before describing it as continuum, density, quadrature, likelihood,
or reliability mass. Exact residuals, diagonal equilibration, and a familiar
normalized operator do not establish those semantics by themselves.

## Calibrate Scientific Metric Gates

Before applying an evaluation metric as a scientific or product stop on opaque
data, state the claim the metric is meant to test and score at least one
known-good oracle and one known-bad control that exercise that claim. Compare
plausible reference geometries and inspect the relevant scales or intrinsic
directions when a scalar can hide local failure or domination by one direction.

If the metric family ranks the controls contrary to the intended claim, treat it
as measuring its stated reference objective rather than generic quality. Narrow
the interpretation or replace the gate before using it to stop the real-data
workflow. A correctly computed frozen metric does not validate the decision
contract by itself.

Before freezing a decision matrix, audit every branch for mathematical
reachability. Combine metric ranges and floors or ceilings with observed or
anticipated control values, comparison direction, strict versus non-strict
operators, and conjunctions across required strata. If a positive branch is
unreachable, either replace it with a predeclared boundary-aware criterion such
as noninferiority plus degraded-regime improvement, or label the rule as a
conservative continuation policy rather than a discriminating test.

Treat the arithmetic implementing the gate as part of the same contract. Use
scale-first norm or residual reductions, choose algebraically equivalent
evaluation orders that keep intermediates representable, and require every
derived product, residual, scale, normalized value, allowance, and threshold to
be finite before comparison. Include an extreme-but-finite incorrect control
and a case whose mathematical result is representable even though a naive
intermediate overflows or underflows.

Freeze comparator roles before defining multi-control gates. When cases differ
in truth or interpretability, predeclare each role and allowed inference before
outcomes. Keep validity universal, behavior all-case, and utility role-aware: a
null or adverse control qualifies claims but does not veto a structure-bearing
sentinel for lacking low-dimensional truth. Require material relative
improvement plus any adequacy floor, define harm against the trusted baseline,
separate mechanism from evidence strength, and exhaust statuses.

For method-family work, assign every gate to the claim layer it governs:
algebraic legitimacy and the numerical contract; behavioral non-equivalence
and public interpretability; or comparative task performance. Require
superiority only when the proposed contract asserts it. A failed comparison
must not invalidate a coherent endpoint or close an adjacent construction
family that the experiment did not exercise.

Label novelty and family-continuation gates as incremental when they require
endpoint distinctness, recurrence, breadth, or comparator closure. Those
conditions cannot judge the endpoints that define the family. Calibrate
established or literature-adjacent anchors separately and describe a negative
result as failure of the frozen continuation protocol, not as a general verdict
on method legitimacy or utility.

## Nested Baseline Closure

When a proposed extension contains a trusted baseline at an equality, zero, or
other limiting setting, make that reduction the first gate. Compare local
objects, the assembled operator, and the selected output or subspace where
those layers exist; handle sign, basis, and repeated-eigenspace invariance
explicitly instead of relying on one final plot.

After closure, retain the baseline at its original parameter, the baseline
under the proposed parameter change without the new mechanism, the equality
control, and the actual extension. Treat one favorable setting as diagnostic
only. Require stable results across fixed replicates and adjacent predeclared
settings before optimization, compiled implementation, or public API work.

For cross-configuration spectral comparisons, first determine whether the
varied argument changes only the extracted eigenspace or rebuilds the estimator
or operator. Compare invariant spans with principal angles or canonical
correlations before aligning pointwise coordinates, and use an admissible
Procrustes map before interpreting axes. When a qualitative comparison remains,
show the same observed representatives in both views, selected from their joint
aligned structure rather than labels, residual extremes, or a favorable score.
Distinguish an alternative low-dimensional slice of shared structure from
recovery of unique information.

When reporting a minimum candidate eigengap, give its case, configuration, and
mode pair, then classify the gap as internal to, crossing, or beyond the
retained invariant subspace. Also report the retained-boundary gap,
multiplicity-block dimension, candidate and retained counts, and the
invariant-span comparison used for sign-off. A small internal gap does not show
that a retained plane is unstable when its boundary remains separated.

Before interpreting retained eigenvector views, measure whether each mode is
globally supported, for example with participation-ratio support or
top-fraction energy. Treat localization as distinct from convergence,
eigengaps, graph connectedness, and local-rank validity. When robust plot limits
exclude observations, report the window and omitted count and do not infer
global semantic structure from a converged but highly localized mode.

## Local Chart Validity Across Noise Scales

When a method claims to recover manifold coordinates, align the output under
the method's admissible affine or subspace symmetry and predeclare local
injectivity and conditioning witnesses. Use neighborhood-fitted Jacobian
determinant signs, lower-tail singular values, condition-number tails, and,
when latent triangulation is available, signed simplex orientation. Global
association, affine error, and a plausible scatterplot remain secondary.

Compare observation noise with sample spacing before interpreting point-scale
simplex reversals. When tangential noise can reorder neighbors, use simplex
orientation as a point-order diagnostic rather than a pure injectivity gate;
construct a favorable oracle that unfolds while retaining the relevant
displacement, then compare fitted Jacobians over declared physical scales,
including boundary, interior, and spatial-coherence summaries. If the favorable
or exact upstream oracle fails the local gate, stop downstream tuning. If only
the raw point-scale statistic fails, reopen evaluation rather than silently
changing the algorithm or the prior stop decision.

## Favorable Hypothesis-Class Oracles

When a proposed repair changes the selector but retains a fixed candidate
representation, test that hypothesis class before building the deployable
selector. Freeze the representation, give a bounded selector favorable access
to truth or exact local invariants, predeclare the searched family and the local
property that motivated the repair, and retain every declared result.

Use the outcome as a boundary, not an impossibility claim. A positive oracle
localizes the remaining problem to practical unsupervised selection. A negative
oracle closes only the exercised representation-objective pair. If untested
nonlinear objectives or representations remain plausible, state that scope
explicitly before opening a separate method-development plan.

## Hard-to-Soft Constraint Closure

When a finite method replaces a hard constraint with a quadratic penalty,
construct or characterize the constrained limit before tuning the multiplier.
First validate that the constraint operator represents the intended continuum
object; a finite stencil's exact nullspace may be smaller than the continuum
kernel.

Diagnose the penalty where the optimizer is decided. Track overlap with the
constrained solution, constraint and base energies, the relevant eigengap,
smallest positive penalty modes, and low-mode Rayleigh-quotient crossings.
Whole-operator norm matching does not prove that the constraint is active in
the low spectrum.

When a rank-one penalty only needs to move a known null beyond the requested
low spectrum, choose its scale from a cheap certified upper bound, such as an
induced matrix norm or Gershgorin bound. Do not add an auxiliary iterative
largest-eigenvalue solve when exact spectral-edge estimation is unnecessary.
Keep null removal, target-solve convergence, retained-boundary separation, and
generalized residuals as the acceptance contract.

Use this outcome table:

| Observation | Decision |
| --- | --- |
| Constrained limit fails | Stop; repair algebra, operator, or upstream geometry |
| Constraint operator violates its oracle | Stop before stronger enforcement |
| Constrained limit works but finite penalty does not | Run a bounded diagnostic continuation |
| Only an isolated large multiplier works | Do not promote it as a default |
| A predeclared finite regime matches the limit | Continue to downstream robustness checks |

Label continuation explicitly as diagnosis or parameter selection. Do not turn
an unsuccessful reproduction into a newly invented method without opening a
separate decision, evidence question, and plan boundary.
