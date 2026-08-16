# Check Diagnostic Cases

Use these optional capsules only when the default diagnostic-ownership rule and
the relevant mechanics in [checks.md](checks.md#restricted-environment-mechanics)
do not make the next action clear.

## Environment-Owned Diagnostic

- **Situation:** A check cannot verify current time, CRAN metadata, a package
  URL, or emits a system-bus, headless-device, or pre-existing local compiler
  flag diagnostic.
- **Plausible wrong behavior:** Treat the message as a repository regression or
  hide it as harmless environment noise without attribution.
- **Useful witness:** Reproduce the affected path, compare the pre-change
  baseline, and identify whether the emitting operation belongs to repository
  code, the toolchain, or an external service.
- **Clock witness:** For a future-file or bad-clock diagnostic, compare the
  worker clock with provider control-plane timestamps and a same-commit
  independent runner. Inspect the external time source R accepted: a reachable
  but stale HTTP `Date` header is different from an unreachable time service or
  a genuinely future-dated repository file.
- **Related mechanic:** Use the cache or network rerun in
  [checks.md](checks.md#restricted-environment-mechanics) when applicable.

Disable only remote system-clock verification, and only after those witnesses
assign ownership outside the repository. Do not suppress the future-file check
or change package code to accommodate stale external time.

## Planning Artifact During Package Check

- **Situation:** `R CMD check` reports a top-level planning directory such as
  `plans`.
- **Plausible wrong behavior:** Move or delete an active plan merely to silence
  the note.
- **Useful witness:** Record whether the path is tracked, untracked, or ignored
  and whether the package intends to ship it.
- **Related mechanic:** Change plan location or `.Rbuildignore` policy only when
  the user chooses that repository policy.

## Temporary Build-Source Cleanup

- **Situation:** `R CMD build` or `devtools::check()` reports `Removed empty
  directory` for a development directory such as `.agents`, `.codex`, or
  `plans`.
- **Plausible wrong behavior:** Report that the command deleted working-tree
  files.
- **Useful witness:** Check `git status`; treat the message as cleanup in the
  temporary package-build source unless the working tree actually changed.
- **Related mechanic:** None.

## Namespace Visibility Note

- **Situation:** A check NOTE reports a bare `as()` as having no visible global
  definition.
- **Plausible wrong behavior:** Add a roxygen `@importFrom` without checking the
  package's namespace style.
- **Useful witness:** Inspect how the package qualifies other `methods`
  functions and whether it intentionally imports `as`.
- **Related mechanic:** Normally use `methods::as(...)` and declare `methods` in
  `DESCRIPTION`; retain an import only when it is intentional policy.

## Generated Site Output

- **Situation:** `docs/` output is missing or untracked after documentation or
  package validation.
- **Plausible wrong behavior:** Treat it as a package source diff automatically.
- **Useful witness:** Determine whether the repository tracks pkgdown output or
  the task requested a site update.
- **Related mechanic:** Review or generate `docs/` only when one of those
  boundaries applies.
