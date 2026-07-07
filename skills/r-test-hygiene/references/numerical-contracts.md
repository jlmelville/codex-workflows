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

## Derivative Evidence Before Fixes

For gradients, Hessians, and related analytic derivatives, do not treat one
finite-difference mismatch as proof that the analytic code is wrong. Compare
over several finite-difference step sizes and inspect relative error as well as
absolute error before editing production code.

Large absolute error alone is weak evidence for ill-scaled objectives. Look for
patterns that stay bad across reasonable step sizes, relative-error outliers,
shape or symmetry violations, or failures that are localized to a specific
dimension branch. Record the evidence before changing analytic derivative code.

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
