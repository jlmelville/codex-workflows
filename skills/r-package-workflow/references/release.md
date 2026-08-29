# CRAN Release Lifecycle

Use this after development checks for a CRAN candidate. Follow current
[CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html)
when requirements differ from remembered practice.

## Freeze The Candidate

1. Reconcile the version across `DESCRIPTION`, NEWS, generated files, and
   `cran-comments.md`. Classify old remote findings against their exact archive.
2. Run `roxygen2::needs_roxygenize()` on the exact candidate. Resolve drift in
   isolation or an authorized documentation phase, inspect generated surfaces,
   require an idempotent second pass, and classify metadata-only churn.
3. Build with current R-patched or R-release; inspect the archive's identity,
   contents, licenses, and documentation.

## Validate The Archive

- Run the final CRAN-style check on the archive. A hosted `--no-manual` lane does
  not establish manual or artifact coverage; record their completion.
- Before that check, probe PDF and HTML manual tools independently. Treat missing
  styles or obsolete binaries as host prerequisites only when package evidence
  agrees. Prefer a user-writable toolchain when needed, verify discovery, run
  `R CMD Rd2pdf`, and rerun exact; host fixes are platform-specific, not source edits.
- Complete material external checks and `revdepcheck`, using
  [revdepcheck.md](revdepcheck.md) first for sensitive dependency universes.
- Report incomplete remote service state separately. Promptly retain expiring
  status, environment, and material text; keep binaries only for diagnosis.

## Prepare Submission Evidence

Keep `cran-comments.md` to release purpose, completed results, and needed
diagnostics. For corrections, name the affected version, result and flavors,
bounded diagnostic, and fix. Keep unrun checks, setup failures, and process
detail in the handoff; it is not new public documentation without user approval.

## Submit And Close

Submit through the current form or supported helper and confirm by email. Do not
upload while pending; after correction, update version and evidence as required
and await the prior outcome before resubmitting.

After acceptance, tag the exact source, publish the release note, restore the
development version and NEWS heading, and monitor CRAN and downstream status
for publication-only failures.
