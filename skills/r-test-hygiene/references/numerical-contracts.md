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

## Derivative Evidence Before Fixes

For gradients, Hessians, and related analytic derivatives, do not treat one
finite-difference mismatch as proof that the analytic code is wrong. Compare
over several finite-difference step sizes and inspect relative error as well as
absolute error before editing production code.

Large absolute error alone is weak evidence for ill-scaled objectives. Look for
patterns that stay bad across reasonable step sizes, relative-error outliers,
shape or symmetry violations, or failures that are localized to a specific
dimension branch. Record the evidence before changing analytic derivative code.
When a committed test uses a non-default finite-difference scale, keep a short
comment beside the override explaining the relevant scaling or cancellation
issue and why that direction or magnitude was selected. Keep detailed probe
results in the active plan or review record.

## External AD Oracles

When a package with hand-coded gradients or Hessians needs more assurance than
finite differences can provide, consider a separate sibling oracle repository
instead of adding an automatic-differentiation stack to the package test suite.
Use the oracle to implement scalar objectives or residuals independently in a
float64-capable AD backend, derive gradients or Hessians through autograd, and
compare against the source package through optional scripts.

Keep the oracle independent: do not transliterate the package's analytic
derivative code or copy branch logic verbatim. Share only stable problem
definitions, input cases, tolerances, and comparison reports. Treat oracle
scripts as supplemental evidence; the source package should still keep
lightweight finite-difference checks and contract tests for routine CI.
