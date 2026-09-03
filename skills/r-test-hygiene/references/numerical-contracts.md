# Numerical Contract Tests

Use this for numerical packages where ordinary line coverage can still miss
stale scientific metadata, dispatch inconsistencies, or derivative bugs.

## Returned Scientific Metadata

When public functions return known minima, optima, reference values, or problem
metadata, test those contracts through the public object:

- evaluate returned `xmin` or equivalent parameters with the returned objective
  and compare to `fmin` or the documented reference value;
- check that dimensions, names, bounds, and parameter counts match the object
  returned by the factory or dispatch wrapper;
- exercise variable-dimension edge cases, not only default benchmark sizes;
- verify returned callable components such as `fn`, `gr`, `fg`, or `he` are
  dimensionally coherent with the problem they came from.

Prefer these user-visible contracts over hand-maintained local fixtures when
the fixture can drift away from the package's own metadata.

When a variable-dimension contract specifies minimum, default, and next
structurally valid sizes, encode that matrix as a table-driven test. Include the
first size that activates guarded, neighbor-dependent, or otherwise skipped
loops, and exercise every returned callback at every size. Check objective
shape, gradient length, finite Hessian dimensions, and `fg` agreement when
those components exist; minimum-size coverage alone does not exercise a loop
that starts at the next size.

## Variant Equivalence Invariants

When a numerical algorithm exposes multiple update recipes or formula variants
that should coincide under idealized conditions, test that mathematical
invariant separately from broad nonlinear benchmark coverage. Use a small exact
fixture with a known oracle, such as a positive-definite quadratic for conjugate
gradient recipes, and compare each variant with a reference recipe under fixed
starts, tolerances, and deterministic controls.

Assert both the final contract and the trace-level behavior that theory says
should match: iterates, objective values, gradients, directions, step lengths,
update coefficients, or finite-termination counts where relevant. Golden output
on a difficult nonlinear benchmark can cover recipe wiring, but it does not
prove exact-condition equivalence or N-step termination.

Treat adapted diagnostics as part of the same equivalence contract. Inventory
their units, value domains, caps, sentinel or null meanings, and aggregation
domains rather than comparing only field names or headline counts. Use an
adversarial case where a coarse count agrees while an uncapped, basis-limited,
or differently aggregated diagnostic diverges, then compare every promised
diagnostic after adaptation.

## Backend Versions And Legacy Oracle Firewalls

For a numerical backend upgrade, install old and new builds in isolated
libraries. Read primary changelog, reference, and lifecycle guidance; diff the
exported formals used by the adapter; then compare scientific results separately
from trajectories, budgets, callback counts, terminal status, and retained
state. A changed trace is not necessarily a result regression, and an unchanged
result does not prove lifecycle conformance or sufficient observability.

Before replacing port-shaped or legacy code, inventory supported modes and
freeze only their implementation-independent outputs, traces, callback counts,
and invariants. A temporary isolated differential probe may load the prior
implementation, but do not commit it as a dependency or retain tests for
unreachable private modes.

Pin each oracle to the exact paper, routine, version, or port. When credible
lineages differ, add a narrow transition-level discriminator and record whether
the change preserves one lineage or intentionally migrates to another. Treat
source disagreement as a variant choice until a mathematical, safety, or public
contract witness establishes a defect.

## Research Prototype Defaults

Test structural algebra separately from empirical target recovery. Before
selecting a default, use a bounded repeated ground-truth matrix across relevant
seeds and sample sizes with a predeclared criterion; retain alternatives and
limit claims to the exercised regime.

Start with a fixture faithful to the reference challenge. Record material
geometry, scale, boundaries, sampling, neighborhood construction, refinement,
and pipeline stage, and check graph or operator preconditions before blaming the
estimator. Add related generators or stress tests only after understanding the
claimed regime.

## Factorization Repair Contracts

For a fallback that repairs a matrix before factorization, reconstruct the
matrix from the returned factor and compare it with an independently built
repair oracle. Cover exact-boundary, near-boundary, and clearly invalid spectra,
and use a deliberately non-default repair setting to prove the control is
honored. Retain the documented unrecoverable-failure case when relevant.

Pair repair cases with a successful fast-path control whose aggressive repair
setting must not alter the ordinary factorization. Success, non-`NULL` output,
or downstream convergence alone does not establish the repair identity.

Separate real platform-sensitive numerical witnesses from portable downstream
branch-contract tests. When BLAS, LAPACK, eigensolver, or rounding behavior can
change whether the owning numerical failure occurs, retain the extreme input as
qualified diagnostic evidence. To test downstream fallback, state, or
provenance, narrowly inject only the owning unstable result, pair it with an
adjacent control when that proves overwrite sequencing, and assert the real
downstream implementation. The mock does not validate the numerical kernel;
keep invariant-based kernel fixtures separate.

## Conservative Spectrum And Newton Evidence

For a tolerance-based symmetric spectrum, predeclare the scale and sign
tolerance and classify eigenvalues as resolved positive, resolved negative,
exact zero, or nonzero with unresolved sign. Build exhaustive sign families
from those bins, including negative definite and semidefinite outcomes, and
reserve indefinite for spectra with both resolved signs. Record singularity
orthogonally. Define a magnitude condition estimate only for fully resolved
nonzero spectra, use infinity for exact zero modes, and report it unavailable
for unresolved or failed calculations. Exercise exact classes, both sides of
the sign threshold, large and small finite scaling, and failed calculations.

Treat Newton evidence as an ordered ladder: derivative integrity; spectral and
conditioning eligibility; finite scale-aware residual for `H p = -g`; direction
norm and `g' p` descent; unit-direction quadratic prediction; and only then
selected-step and actual-decrease evidence. A resolved indefinite system may be
useful diagnostic solve evidence, while an accurate solve does not establish
descent, model merit, or optimizer safety. Retain singular, unresolved, and
failed rows with explicit bases instead of dropping them.

At globalization, preserve direction metrics at unit scale but recompute the
selected-step prediction as
`-alpha * g' p - 0.5 * alpha^2 * p' H p`. Form an actual-to-predicted ratio only
when actual reduction and prediction are finite, the prediction is strictly
positive, and a re-evaluated seed slope agrees with the recorded direction
slope. Report selected step, method termination or acceptance, realized
improvement, fallback status, and ratio availability as independent claims;
neither step length nor objective change alone identifies the policy outcome.

## Transformed Eigensolver Coordinates

When an eigensolver operates on a symmetric transformation and maps vectors
back to public coordinates, name the solver and mapped coordinate systems
before implementing diagnostics. Preserve both representations only when the
public result needs that observability. Derive the residual transformation and
scale explicitly, and keep native solver residuals distinct from generalized
residuals rather than silently replacing one with the other.

Test the generalized eigen-equation, weighted orthogonality and centering, and
the map-back identity through the public result. Express structural-subspace
comparisons in the coordinate system—or weighted inner product—where the
compared vectors are mathematically equivalent.
For exact or near-exact subspace equality, use a normalized Frobenius projector
difference or another stable equivalent. Avoid one-minus-averaged-squared-cosine
subtraction near coincidence, and test an identical span before setting a gate.

Include at least one fixture whose effective weight diagonal varies materially,
and assert that nonuniformity before using it to validate weighted null
directions, centering, orthogonality, or elementwise map-back. A symmetric
constant-weight fixture may remain as a separate eigenspace or boundary oracle,
but it cannot distinguish the defining weighted transformations from scalar
rescaling.

When model-construction dimension, displayed output dimension `d`, retained
spectral dimension `m`, and solver candidate width differ, preserve that
vocabulary in result fields and diagnostics. If `m > d`, compute and label both
the displayed `d/(d+1)` and retained `m/(m+1)` boundary evidence, including
scope-specific truncation state. Keep displayed instability visible when the
retained block is stable, and make every suggested remedy name the control that
changes the diagnosed boundary without silently rebuilding the estimator.

Derive solver candidate width from the post-filter evidence contract. Budget
the retained modes, every known direction removed before reporting, and every
additional displayed or retained boundary mode. Exercise the exact minimum
candidate width and maximum retained dimension so structural projection cannot
silently consume the only boundary value.

When a fast path replaces singular values with eigenvalues of a Gram or
covariance matrix, do not assume algebraically related rank cutoffs are
numerically equivalent after the spectrum is squared. If it must preserve a
direct-factorization rank decision, use a multiscale boundary fixture and
compare both rank diagnostics and the owning numerical result. Derive the
cutoff in the transformed domain, and fall back to a better-conditioned
factorization when the transformed evidence is ambiguous.

## Diagnostics After Input Transformation

When a pipeline canonicalizes, filters, deduplicates, drops structural columns,
or otherwise transforms input before computation, derive diagnostics from the
exact effective object consumed downstream. Do not reconstruct downstream
semantics from the raw input merely because it is easier to access.

Use a deterministic adversarial fixture where the raw and effective
interpretations intentionally disagree, then assert the observable diagnostic
and condition behavior. For APIs with detailed and convenience modes, follow
[diagnostic-regressions.md](diagnostic-regressions.md#detailed-and-convenience-results)
without inferring causes the diagnostic does not establish.

## Bounded Candidate And Tie Contracts

For top-k or neighbor-search interfaces, distinguish deterministic ordering
within the candidate pool returned by a backend from deterministic membership
across the backend cutoff. A stable distance-and-index sort can canonicalize the
returned pool, but it cannot recover equally ranked candidates that the backend
did not return. Asking for a small number of spare candidates expands that pool;
it does not establish global tie membership unless the backend documents a
complete tie-selection guarantee.

Test exact ordering and de-duplication with a controlled candidate-matrix
fixture where the returned set is specified. When an end-to-end tie can cross
the cutoff, assert membership-independent public invariants such as width,
range, uniqueness, distances, and self handling. Reserve exact-ID golden tests
for fixtures where the complete boundary tie is known to be represented or the
backend explicitly guarantees its selection policy.

When smaller structures are derived by taking prefixes of one maximum-width
row, place every structural index or sentinel required at all scales in a
canonical position that survives the shortest prefix. Apply optional removal
before truncation, and reject precomputed layouts that merely contain the
marker elsewhere. Test an adversarial row whose marker lies outside the
smallest prefix under both retention and removal conventions.

## Undefined Rows And Aggregation

For row-wise numerical metrics, define row validity before invoking a provider
when the mathematical precondition is known. Represent undefined rows
explicitly, then accept returned values only through a scalar numeric finite
predicate; checks such as `!is.nan(value)` can admit `NA` and corrupt an
otherwise defined summary.

Test the row policy and every aggregation denominator together:

- preserve documented result shape and group identities when all rows are
  undefined;
- combine defined and undefined rows and assert that the same valid-row set
  supplies overall and grouped denominators;
- use unequal group sizes and unequal group means so an observation-weighted
  result cannot accidentally pass as an unweighted mean of group summaries.

## Nonfinite Ordering Contracts

When a numerical API accepts `NA`, `NaN`, or infinities, descriptions such as
"unchecked" or "used as supplied" are incomplete if sorting, ranking, or
aggregation imposes a deterministic policy. Trace the comparator and every
consumer to establish missing-value classification and placement, infinity
ordering, stable-order or tie behavior, and whether the policy can return an
ordinary finite scalar rather than an error or missing result.

Use a public fixture containing negative infinity, finite values, positive
infinity, `NA`, `NaN`, and relevant ties. Compare every affected public metric
family with an independent reference oracle that encodes the established policy
without calling the implementation's comparator. Document the same precise
ordering contract after the test evidence establishes it.

For distance- or rank-based metrics, also probe every nonfinite kind by
location, information-free matrices, unlike nonfinite kinds, and simultaneous
row/column relabeling. An ordinary finite score is not evidence of meaningful
semantics. Admit positive infinity as unreachable only when reachability and
tied-unreachable behavior are explicit public contracts.

## Derivative Evidence Before Fixes

For gradients, Hessians, and related analytic derivatives, do not treat one
finite-difference mismatch as proof that the analytic code is wrong. Compare
over several finite-difference step sizes and inspect relative error as well as
absolute error before editing production code.

Large absolute error alone is weak evidence for ill-scaled objectives. Require
persistent multi-scale or relative error, shape or symmetry violations, or a
localized branch failure before editing analytic code. When an optimizer's
step policy may be scale-sensitive, pair the transform `f_c = c f`, `g_c = c g`
for positive `c` with a predeclared expectation: fixed-control invariance or
equivariance under an analytically required control transform such as
`alpha_c = alpha/c`. Compare trajectories or endpoints exactly when justified,
otherwise with a stated tolerance, before attributing sensitivity to a defect.

For staged weights, penalties, normalization, exaggeration, or continuation,
validate each objective-gradient phase before Armijo or Wolfe searches. Treat a
new strict-search failure as possible caller inconsistency before weakening the
backend. Explain non-default finite-difference scales beside the test and keep
detailed probes in the plan or review record.

## External AD Oracles

When hand-coded derivatives need more assurance, consider a separate sibling
oracle instead of adding automatic differentiation to package tests. Implement
the scalar objective or residual independently in a float64-capable backend and
compare through optional scripts; do not transliterate analytic code or branch
logic. Share only stable problem definitions, cases, tolerances, and reports.
Keep lightweight finite-difference and contract tests in routine package CI.
