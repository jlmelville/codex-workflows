# Documentation Contracts

Use this when R package documentation must distinguish current behavior from
history, describe backend controls, or explain inspectable scientific results.

## NEWS Chronology

Before editing NEWS, establish the last user-available baseline: a release,
pushed development state, or operator-specified boundary. Check every named item
in a mixed bullet separately. Omit add/remove cycles that occurred entirely
after that boundary, retain removal of previously available behavior, and scan
adjacent entries after correcting chronology.

## Current Supported Contract

State the current supported contract in help pages, READMEs, and articles. Do
not narrate removed options, conventional validator guarantees, prose that
merely paraphrases an adjacent formula, or ordinary invariants merely because
they once regressed. Preserve regression mechanics in tests or internal history.
Include historical detail in NEWS or migration guides only when it conveys
user-visible behavior, compatibility impact, or action.

When a basic user choice requires a multi-control recipe or several caveats,
document only the non-obvious current contract and record a separate API-design
follow-up instead of expanding the help indefinitely.

For an integration article or optional backend, establish the declared minimum
dependency version and verify examples and inspectable result claims against
that published release, not only an adjacent development checkout. If the
needed contract exists only in development, either provide a compatibility path
that distinguishes native, conditional, and derived fields or sequence the
dependency release before publishing the article. Do not present a derived
replacement as a native dependency field.

After a package-wide documentation search, assign each fact one primary
surface. Function help owns exact non-obvious argument and return contracts,
articles own comparisons and cross-family consequences, and README owns the
shortest useful task path. Link across surfaces instead of copying full
explanations, then make a final conciseness pass that removes repeated validator
prose and catalogs of obvious invalid inputs.

When a task-oriented article recommends changing a control because its default
materially affects the task, state that default beside the recommendation
through its consequence: what the API observes, permits, or concludes, and
what the reader should do as a result. Keep the exhaustive formals inventory
on the function-reference surface rather than making readers derive the action
from a compact list of defaults.

For that shortest useful task, inspect whether the package defaults to a
stochastic or approximate route. Prefer a deterministic exact route when it is
practical for the small example. If the approximate route is essential, show
its seed, worker, or other reproducibility controls. Do not publish an exact
numeric reference result until the configured example is deterministic or
repeated executions establish that the documented path is stable.

When prose recommends fair comparisons for a stochastic API, make adjacent
executable comparison examples enact the complete reproducibility recipe:
reset the seed immediately before every sampled call and keep thread or worker
settings identical. Review the prose and examples as one contract.

When documentation promises callback execution, lazy calculation, caching, or
convergence work under a hard resource cap, audit nearby unconditional claims
such as "will calculate" or "always evaluates" against every applicable guard.
Exercise the zero-budget boundary when the interaction is not obvious, and
qualify the promise with the governing cap even when a separate budget section
already states the limit correctly.

## Third-Party Media

Before publishing documentation that reproduces third-party images, icons,
fonts, maps, or other media, inventory the actual distributed artifact.
Distinguish raw or reusable payloads from static derived illustrations, and
record the authoritative source, known license or terms, requested attribution,
and relationship to the package license. Do not infer that the package license
grants rights to embedded media or that small size or transformation alone
establishes permission.

Follow clear source terms. When the publication basis remains ambiguous,
surface the bounded risk and request a user or appropriate legal-owner decision
before release. Do not assert legal clearance, but also do not unilaterally
delete or redesign a useful technical figure without that decision. Keep raw
data and reacquirable caches out of the package unless their distribution is
intentional and supported.

## Reference Values And Locations

For paired reference values and locations, state their correspondence first.
Then document the configuration where the pair applies, whether values are
recalculated, and whether either field applies more broadly. Do not compare a
reference value with an initialization default unless initialization is part of
the reference contract.

## Backend Controls

When an exported function accepts nontrivial backend controls through `...`,
keep the parameter entry short and add a user-oriented section grouping
supported controls by backend. State meanings, package-level defaults,
constraints, useful backend links, and exact routing or fallback effects.
Distinguish route-forcing controls, value-based thresholds, and non-routing
diagnostics. Verify routing claims through the exported function and avoid
validator jargon such as allowlists or ownership.

## Inspectable Results

Before documenting an inspectable result object, trace each public value through
validation, canonicalization, backend selection, and result construction.
Distinguish literal input, canonical selector, and effective backend. Name
meaningful nested fields and define their scales or identities.

For an optional table whose schema grows during execution, document column
absence for an inapplicable run, type-specific missing cells before first
production, and populated values as separate states. Put the complete field
vocabulary and interpretation rules on one primary result topic and link other
exported producers or summaries to it. Describe ownership at the broadest public
abstraction shared by every producing route rather than naming a narrower
internal implementation.

For non-unique numerical representations, document the identifiable value or
subspace instead of promising unique vectors. Do not dismiss supported public
diagnostics as maintainer-only data.
