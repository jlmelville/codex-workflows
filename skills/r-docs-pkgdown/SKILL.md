---
name: r-docs-pkgdown
description: Maintain R package documentation for README, NEWS, roxygen comments, man pages, vignettes, pkgdown config, website metadata, and pkgdown Pages setup. Use when Codex edits or reviews user-facing docs, generated Rd files, _pkgdown.yml, DESCRIPTION metadata, or pkgdown scaffolding.
---

# R Docs and pkgdown

Use this for documentation and pkgdown work in R packages.

## Documentation Rules

- Keep README focused on installation, quick start, and links.
- For GitHub installation instructions in new or refreshed READMEs, prefer
  `pak::pak("owner/repo")` over deprecated `devtools::install_github()`.
- Move long method explanations, literature notes, and extended examples into
  pkgdown articles.
- Record behavior changes and notable infrastructure changes in `NEWS.md`.
- Prefer roxygen source edits over direct `man/*.Rd` edits, then regenerate.
- Treat `man/*.Rd` and `NAMESPACE` as generated unless intentionally refreshed.
- Keep generated `man/*.Rd` changes in the same chunk or commit as the roxygen
  source change that produced them. Avoid unrelated generated churn.
- When roxygen blocks move files without wording changes, regenerate docs and
  classify generated `man/*.Rd` diffs that only update
  `% Please edit documentation in ...` source comments as expected source-path
  churn. Run `roxygen2::roxygenise()` a second time to confirm idempotence.
- After `roxygen2::roxygenise()`, inspect `git diff -- DESCRIPTION`
  separately. Restore roxygen metadata churn, such as `RoxygenNote` being
  replaced by `Config/roxygen2/version`, unless metadata modernization is
  explicitly in scope.
- Do not enable `Roxygen: list(markdown = TRUE)` as an opportunistic partial
  change. Once roxygen markdown is enabled, complete the markdown conversion in
  the same docs-modernization chunk or add an explicit required follow-up chunk
  before formatting, lint, pkgdown, CI, or structural refactors.
- For roxygen markdown audits or package-wide conversions, use
  the bundled `scripts/audit-roxygen-markdown.sh` helper when available, then
  follow [roxygen-markdown.md](references/roxygen-markdown.md).
- Avoid broad roxygen churn during narrow correctness phases.

## Exported API Renames

When exported functions, topics, aliases, or return names are renamed:

1. Edit roxygen sources first and remove stale source references.
2. Run `roxygen2::roxygenise()`, inspect generated additions/deletions, then run
   it a second time to confirm idempotence after topic or export churn.
3. Search for stale public names across `R/`, `tests/`, `vignettes/`,
   `README*`, `NEWS*`, `_pkgdown.yml`, `NAMESPACE`, and `man/`.
4. Run focused tests, examples, or documentation builds that exercise the
   renamed public API.

## pkgdown Workflow

Use complete scaffolding. Either run the relevant `usethis` helper first, or
copy the complete feature bundle from a reference repo.

After `usethis::use_pkgdown_github_pages()` or similar helpers:

1. Inspect all changes, especially `.github/workflows/pkgdown.yaml` and
   `_pkgdown.yml`.
2. Restore or apply hardened GitHub Actions patterns.
3. Verify remote GitHub Pages and repo homepage state when publishing matters.
4. Keep `_pkgdown.yml`, `DESCRIPTION` URL/config, `.Rbuildignore`,
   articles, and workflow in sync.
5. If pkgdown reports `Reference metadata not ok` with a topic missing from
   an explicit `_pkgdown.yml` `reference:` index, decide whether the exported
   topic is public. Add public topics to the index; mark non-public topics
   `@keywords internal` in roxygen and regenerate.
6. Run pkgdown and workflow checks.

See [pkgdown.md](references/pkgdown.md).

## Checks

```sh
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'pkgdown::build_site(new_process = FALSE)'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
```

Network-restricted environments may need approval for pkgdown external assets
or CRAN metadata.
