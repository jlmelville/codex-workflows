# Variadic Backend Controls

Use this when an exported R API forwards `...` through wrappers to one of
several numerical or computational backends.

## Public Boundary

Inventory the controls actually supported by each wrapper and validate them at
the exported boundary before neighbor search, matrix assembly, or other
expensive work. Require names, reject duplicates, unknown controls, and
controls owned by a different selected backend, and protect controls whose
values would suppress output vectors required by downstream code.

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

## Public Tests

Exercise accepted controls for every backend and reject unnamed, duplicate,
unknown, wrong-backend, and required-output-disabling inputs. Test each routing
category independently, including no controls, small-problem fallback, and
requested-versus-actual backend metadata. Keep the semantic classification in
package code and its public tests; it is package-specific and does not warrant
a generic validator.
