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

## Looped Diagnostics

Not every testthat expectation accepts `info` consistently across installed
versions. For table-driven comparison diagnostics, prefer
`expect_true(<comparison>, info = case$name)` when the case label matters, and
smoke-run the focused test immediately after adding diagnostic arguments.
