# Numerical Reproduction Work Packets

Use this reference when reproducing a layered numerical research method whose
failure could arise from transcription, solver algebra, operators, geometry,
regularization, estimated intermediate fields, or the published finite model.

## Map The Implemented Method Boundary

Before comparing code with a publication, trace the public method profile
through default and alias resolution, first and later initialization,
callback-budget ownership, transition engines, recovery, finalization, caches,
and returned state. Mark every phase that owns a defining formula or callback,
then apply equation and resource oracles to the implementation actually
selected by the public path. Treat computed-but-unused mathematical terms and
unexplained norm or scaling substitutions as transcription signals. Do not
claim the method is audited while an owning lifecycle phase remains unmapped.

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

For an inherited numerical method, preserve supported behavior with independent
oracles, then map the publication's states, equations, invariants, and
independently derivable formulas before inspecting additional reference
implementations. Fix a tentative target design at that boundary so a later
source cannot silently become the structural template.

Afterward, classify every retained difference as publication-specified,
publication-derivable, standard numerical safeguard, implementation choice,
compatibility behavior, extension, or unresolved. Source disagreement is not a
defect without a mathematical, safety, or supported-contract witness. Separate
characterization, behavior-neutral restructuring, and any correctness change
into reviewable packets. Use the
[legacy numerical oracle firewall](../../r-test-hygiene/references/numerical-contracts.md#legacy-numerical-oracle-firewalls)
for migration evidence without preserving obsolete implementation expression.

## Decompose Before Tuning

Inventory the defining equations, solver, kernel scale, graph topology,
regularization, intermediate-field estimator, sampling and noise regime, and
finite objective. Give each phase one causal question, hold every other layer
fixed, name the local invariant that answers it, and predeclare its stop gate.
Plots and global association are supporting evidence, not substitutes for
local residuals or compatibility conditions.

Before a multi-point oracle runs, materialize its complete deterministic
candidate universe in a selection manifest separate from the numerical result
table. Record provenance, eligibility and exclusion bases, optimizer-return
metadata, and exact or predeclared deduplication semantics. Run the oracle only
on eligible unique points and preserve a stable join key from every result back
to the manifest. Probe early termination, duplicate returns, and rejected or
inapplicable references without creating fake result rows.

## Review-Complete Checkpoints

Before an expensive numerical run, derive the checkpoint schema from the claims
and review questions it must support. Distinguish a restart cache from an
independent-review packet. The latter should retain frozen settings, stable data
identity or bounded regeneration inputs, upstream graph or intermediate
witnesses, downstream diagnostics, deterministic selections, and artifact
paths needed by a fresh process. Keep large reacquirable inputs disposable.

Immediately read the persisted checkpoint through the intended review path and
validate its fields before discarding live state. A successful write or a cache
that can resume computation does not establish that an independent reviewer can
audit the recorded claims.

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

When a dense generalized-eigen oracle has a known null under a positive
diagonal mass, form the symmetric mass-scaled operator and the transformed
null `M^(1/2) v0`, restrict the solve to that null's orthogonal complement,
and only then map retained vectors back. Do not identify and drop one vector
from the full decomposition by alignment when low modes may cluster. Check
generalized residuals, mass-weighted centering and orthogonality, the map-back
identity, and invariant-span agreement.

Record negative results in the active plan so later work cannot reopen a ruled-
out cause without new evidence. An outcome-dependent gate should say whether to
repair the current reproduction, stop because an upstream precondition failed,
or start a separately identified method-development decision.

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

For multi-control decisions, name each comparator's role before defining gates.
Require a positive outcome to satisfy both material relative improvement and
any absolute adequacy precondition; define harm against the primary trusted
baseline rather than every stress or ablation control. Keep mechanism or
availability classification separate from evidence strength, and make final
statuses ordered and exhaustive.

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
