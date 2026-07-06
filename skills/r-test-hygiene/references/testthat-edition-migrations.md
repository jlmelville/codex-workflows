# testthat Edition Migrations

Use this when opting an existing R package into
`Config/testthat/edition: 3`, especially when the initial migration exposes
broad numerical fallout.

1. Remove deprecated `context()` calls and update `DESCRIPTION`/`Suggests`
   deliberately.
2. Run the full suite immediately. If testthat's failure cap hides the pattern,
   rerun
   `Rscript -e 'testthat::set_max_fails(Inf); testthat::test_local()'`.
3. Record the complete failure set before editing expectations.
4. After replacing deprecated `tol =` with `tolerance =`, do not assume the
   comparison semantics are unchanged. Edition 3 uses waldo-style comparison,
   and relative tolerance can expose small rounded optimizer or simulation trace
   differences.
5. Prefer explicit tolerances, near-zero thresholds, optimizer invariants, or
   success properties over production changes.
6. Do not globally shadow `expect_equal()`. If rounded trace fixtures
   intentionally need absolute tolerance, use a clearly named narrow helper
   such as `expect_equal_abs()` for those assertions and keep regular
   `expect_equal()` elsewhere.
7. Do not change production behavior unless the migration exposes a real bug
   with independent evidence.
8. Rerun full tests, then broaden to format, lint, or package checks according
   to blast radius.
