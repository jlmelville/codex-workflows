# Diagnostic Regressions

Use this for focused tests that must preserve warning behavior, diagnostic
direction, metadata attributes, or useful table-driven failure labels.

## Partial-Match Warnings

For R partial-match warnings, fix the source by using exact `[[...]]` access for
optional list fields instead of suppressing the warning. Add a focused
regression with `options(warnPartialMatchDollar = TRUE)`, restore options with
`on.exit()`, and assert `expect_warning(..., NA)` around the behavior that
previously emitted the partial match.

## Paired Validation Branches

Test both directions and assert diagnostic direction through public APIs.
Examples include sparse versus dense inputs, logical versus numeric storage,
reference versus query data, and model versus newdata compatibility. Prefer
expectations that distinguish which side is wrong; a loose substring can
preserve an inverted user-facing error.

## Metadata Attributes

When canonical metadata gains names, classes, or other attributes, rerun the
raw parser/spec boundary with tiny local fixtures. `identical()` compares
attributes as well as values, so normalize with `unname()` or a similarly
explicit value-only comparison when raw attributes are not part of the
contract, while preserving canonical attributes in result expectations.

When adding names or dimnames to a public matrix, inventory downstream
operations that can propagate those attributes into derived summaries. Decide
the attribute contract field by field, and pair positive matrix-attribute
expectations with explicit no-name checks for diagnostics that must remain
unnamed.

For result lists whose field order is not public behavior, assert the exact
field-name set without enforcing insertion order. For example,
`expect_named(..., ignore.order = TRUE)` still rejects missing or extra fields
while accepting permutations; use order-sensitive checks only when ordering is
part of the documented contract.

For value-only numerical symmetry, use
`isSymmetric(x, check.attributes = FALSE, ...)` explicitly: the base default
also compares dimnames. Preserve and return the original object rather than
stripping attributes. Pair a labelled symmetric positive control with a truly
asymmetric numeric negative control.

## Warning Suppression

Treat an explicit warning-suppression option as condition handling, not as a
second computation path. Run default and suppressed modes on the same valid
input and require identical values. For a warning-producing input, require the
default to warn, the suppressed mode to stay silent, and both modes to return
the same value, including `NaN` or another documented result.

## Looped Diagnostics

Not every testthat expectation accepts `info` consistently across installed
versions. For table-driven comparison diagnostics, prefer
`expect_true(<comparison>, info = case$name)` when the case label matters, and
smoke-run the focused test immediately after adding diagnostic arguments.

## Multi-Condition Streams

Under testthat edition 3, `expect_message()` and `expect_warning()` capture at
most one matching condition; later or non-matching conditions bubble outside
the expectation. For a short sequence where every condition is part of the
contract, nest one expectation per condition. Use `expect_snapshot()` when the
combined output and conditions form the stable review surface. When the return
value and complete ordered condition stream both matter, capture the stream
with `withCallingHandlers()`, muffle every intended condition, then assert the
value, count, order, and distinguishing content. Do not suppress important
conditions merely to keep a passing reporter quiet.

## Optional Progress Diagnostics

For an algorithm-specific progress field, record categorical provenance at the
final owner of the realized value. A later safeguard that replaces a provisional
result must also replace its provenance. Propagate the already-computed label
through the ordinary detailed result without replaying callbacks or
reconstructing the branch downstream.

Treat progress history as a typed sparse schema. Backfill rows before first
production with a type-appropriate missing value, such as `NA_real_` or
`NA_character_`, and omit the field when the algorithm does not own it at all.
Through the exported API, cover every supported producer label, the initial
pre-production row, an unrelated-method control, final replacement behavior,
and unchanged callback counts.

## Detailed And Convenience Results

When an exported API offers both a convenience value and a detailed diagnostic
result, construct the status and result once and assign condition ownership at
the public boundary. The convenience path may warn or error for actionable
statuses; the detailed path should preserve status, messages, and diagnostics
without duplicating them as conditions.

Test the modes as a pair through the public API. Cover successful, warning, and
invalid statuses on the convenience path, then assert that detailed mode stays
silent and exposes the same diagnostic state for inspection.
