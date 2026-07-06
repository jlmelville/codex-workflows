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
