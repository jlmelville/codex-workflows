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

For non-unique numerical representations, document the identifiable value or
subspace instead of promising unique vectors. Do not dismiss supported public
diagnostics as maintainer-only data.
