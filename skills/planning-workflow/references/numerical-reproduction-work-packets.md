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
