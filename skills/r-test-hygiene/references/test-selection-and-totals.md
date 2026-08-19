# testthat Selection and Totals

Use this reference when focused validation must prove an exact file set or a
review needs compact, complete suite totals.

## Focused File Selection

`testthat::test_local(filter = ...)` treats the filter as a regular expression
over normalized `test-*.R` basenames. Derive patterns from the actual files.
For exactly one file, anchor both ends:

```r
testthat::test_local(filter = "^api$")
```

Use deliberate anchored alternation for a named set. Inspect the reporter and
confirm every intended context ran. A zero exit proves only that the selected
contexts passed; a misspelled alternative can silently omit its intended file
while other matches keep the run green.

## Compact Totals

Record the exact command and whether the reported count comes from structured
testthat results, reporter output, or another validation lane. Do not label a
number exact when its counting convention is unstated.

When expectations live inside named `test_that()` blocks, derive totals from
the structured result:

```r
results <- testthat::test_local(reporter = "silent")
data <- as.data.frame(results)
totals <- c(
  tests = nrow(data),
  expectations = sum(data$nb),
  passed = sum(data$passed),
  failed = sum(data$failed),
  warnings = sum(data$warning),
  skipped = sum(data$skipped),
  errors = sum(data$error)
)
print(totals)
quit(
  status = if (sum(totals[c("failed", "warnings", "errors")]) > 0) 1L else 0L
)
```

The reporter controls test progress, not arbitrary package messages. Report
skips separately from failures and warnings.

Before calling the totals exact, inspect the suite for legacy top-level
expectations. Those may appear in reporter output without a corresponding row
in the structured result. Move them into named blocks when that cleanup is in
scope; otherwise reconcile the reporter with the known baseline and state the
limitation.

Keep top-level reporter markers, package-check examples, snapshot checks, and
other validation lanes separate from the structured result. If two reports
claim different exact totals for the same patch, reproduce both conventions and
reconcile the delta before choosing or repeating either number.

## Completeness Review

If full-suite totals decrease without an intended test change, rerun
unfiltered, inspect the executed contexts, and attribute the delta to a filter,
omitted files, top-level expectations, or an intentional change. A green exit
alone is not evidence that the complete suite ran.
