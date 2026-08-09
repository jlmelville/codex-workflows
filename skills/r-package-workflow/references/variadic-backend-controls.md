# Variadic Backend Controls

Use this when an exported R API forwards `...` through wrappers to one of
several numerical or computational backends.

## Public Boundary

Inventory the controls actually supported by each wrapper and validate their
names and ownership at the exported boundary before neighbor search, matrix
assembly, or other expensive work. Require names, reject duplicates, unknown
controls, and controls owned by a different selected backend. Keep a curated
name inventory when any downstream provider might silently ignore an unknown
name.

Validate values only when the wrapper interprets them, routes on them, or must
protect one of its own invariants, such as output vectors required by downstream
code. Pass backend-owned values through unchanged and let the backend own their
coercion, range checks, warnings, and errors; duplicating those checks can
narrow the downstream contract and drift across dependency versions. Keep
wrapper diagnostics short by naming the first offending control and relevant
selected backend, and leave the complete supported inventory in documentation.

Inspect exact argument matching and provider formals before deciding which
controls were supplied. Named formals with defaults can be removed from a
provider's residual `...`, so `length(list(...))` at that layer is not a safe
proxy for the public controls the caller provided.

## Routing Contract

Classify controls explicitly:

- route-required controls force the backend whose behavior they configure;
- threshold controls choose a route from their values;
- diagnostic and other non-routing controls do not change the route.

Preserve the no-control small-problem fallback when it is part of the public
contract. Report requested method and actual backend separately so fallback is
observable rather than mistaken for ignored input.

When selector redesign is explicitly authorized, prefer a dedicated automatic
policy for thresholds and fallback, and make every explicit backend name
literal. Controls should configure the already selected mode rather than select
it implicitly; reject controls owned by another explicit mode. Continue to
report requested policy separately from the effective backend chosen by the
automatic policy.

## Public Tests

Exercise accepted controls for every backend and reject unnamed, duplicate,
unknown, wrong-backend, and required-output-disabling inputs. Test each routing
category independently, including no controls, small-problem fallback, and
requested-versus-actual backend metadata. For an explicit automatic policy,
exercise every automatic route plus literal explicit backends on inputs that
would otherwise cross the automatic threshold. Add a public pass-through probe
that shows backend-owned values reach the selected provider unchanged, without
freezing dependency-specific error text. Keep the semantic classification in
package code and its public tests; it is package-specific and does not warrant
a generic validator.
