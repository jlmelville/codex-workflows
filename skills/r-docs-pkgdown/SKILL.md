---
name: r-docs-pkgdown
description: R package documentation workflow for README, NEWS, roxygen comments, man pages, vignettes/articles, pkgdown configuration, website metadata, and pkgdown GitHub Pages setup. Use when Codex edits or reviews user-facing docs, generated Rd files, _pkgdown.yml, DESCRIPTION documentation metadata, or pkgdown scaffolding in an R package.
---

# R Docs and pkgdown

Use this for documentation and pkgdown work in R packages.

## Documentation Rules

- Keep README focused on installation, quick start, and links.
- Move long method explanations, literature notes, and extended examples into
  pkgdown articles.
- Record behavior changes and notable infrastructure changes in `NEWS.md`.
- Prefer roxygen source edits over direct `man/*.Rd` edits, then regenerate.
- Treat `man/*.Rd` and `NAMESPACE` as generated unless intentionally refreshed.
- Keep generated `man/*.Rd` changes in the same chunk or commit as the roxygen
  source change that produced them. Avoid unrelated generated churn.
- After `roxygen2::roxygenise()`, inspect `git diff -- DESCRIPTION`
  separately. Restore roxygen metadata churn, such as `RoxygenNote` being
  replaced by `Config/roxygen2/version`, unless metadata modernization is
  explicitly in scope.
- Do not enable `Roxygen: list(markdown = TRUE)` as an opportunistic partial
  change. Once roxygen markdown is enabled, complete the markdown conversion in
  the same docs-modernization chunk or add an explicit required follow-up chunk
  before formatting, lint, pkgdown, CI, or structural refactors.
- When converting nested `\itemize{}` blocks to markdown bullets, indent
  continuation paragraphs under the parent bullet and inspect generated
  `man/*.Rd` diffs for changed `\itemize{` and `}` boundaries. Roxygen command
  success does not prove list structure was preserved.
- Avoid broad roxygen churn during narrow correctness phases.

## Roxygen Markdown Audits

When asked whether roxygen markdown is complete or partial, audit source before
generated output:

1. Check `DESCRIPTION` for `Roxygen: list(markdown = TRUE)`.
2. Use roxygen-only searches for markdown overrides and raw Rd macros:

   ```sh
   rg -n "^#'\\s*@(md|noMd)\\b" R
   rg -n "^#'.*\\\\(code|link|url|href|itemize|item|emph|strong|describe|dontrun|donttest|dontshow|eqn|deqn|Sexpr|tabular)" R
   ```

3. Classify intentional raw Rd in examples separately, such as `\dontrun{}`.
4. Treat ordinary `#` comments from broader source searches as source cleanup
   candidates, not RDoc markdown evidence.
5. Treat `man/*.Rd` macros as expected generated output. Search generated Rd
   only when checking source/generated drift after `roxygen2::roxygenise()`.

## Roxygen Markdown Conversions

After a package-wide roxygen markdown conversion:

1. Rerun the roxygen-only macro searches. Classify intentionally retained raw
   Rd separately, especially `\eqn{}` and `\deqn{}` math and example wrappers
   such as `\dontrun{}`.
2. Check odd backtick counts in roxygen lines after multiline `\code{}`
   rewrites. Include `man-roxygen/*.R` when present:

   ```sh
   perl -ne 'if (/^#\x27/ && (tr/`// % 2)) { print "$ARGV:$.:$_" }' R/*.R
   ```

   Avoid literal `#'` inside single-quoted shell programs; use `#\x27`, a
   checked-in helper, or another quoting-safe approach.
3. Run `tools::checkRd` over generated Rd files:

   ```sh
   Rscript -e 'invisible(lapply(list.files("man", pattern = "\\.Rd$", full.names = TRUE), tools::checkRd))'
   ```

4. Run `roxygen2::roxygenise()` a second time and confirm it makes no
   additional `NAMESPACE` or `man/*.Rd` changes.

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
5. Run pkgdown and workflow checks.

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
