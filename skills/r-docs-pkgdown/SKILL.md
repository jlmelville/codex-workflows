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
- When an article or vignette labels a chunk self-contained or copy-paste-ready,
  run that bounded chunk in a fresh environment containing only its declared
  setup. A successful full render does not prove independence when earlier
  chunks can supply mutable objects or state.
- For bounded fresh-session checks, semantic witnesses for generated claims,
  technical-article editorial integrity, precomputed stochastic figures, or
  figure-led articles with long reproduction code, follow
  [validation.md](references/validation.md).
- When creating, reviewing, simplifying, or adding interactions to
  documentation figures, use [figure-style.md](references/figure-style.md) for
  semantic mappings, preservation, accessibility, and final-width review.
- Treat audit suggestions for new tutorials, comparison tables, examples, or
  plots as hypotheses rather than completion requirements. Require a named user
  task and a confirmed coverage gap, account for dataset, dependency,
  execution, plotting, and maintenance costs, and prefer a localized edit to an
  existing surface. Public-contract corrections remain completion work; stop
  when the quick start and specialist-document routing support the intended
  task, and defer speculative enrichment as a separate content project.
- Use `NEWS.md` for user-visible behavior, compatibility impact, or required
  action. Keep internal CI, implementation, diagnostic, and maintenance activity
  out unless it crosses that user-visible threshold.
- For user-visible behavior changes, search roxygen and generated help,
  `README*`, `NEWS*`, vignettes or articles, and relevant pkgdown navigation
  for affected names and contract wording. Classify matches as current public
  behavior, history, or internal detail; do not infer that removing an
  internal field removes a similarly named public control. Regenerate help and
  render each changed article.
- For NEWS chronology, current-contract writing, third-party media,
  backend-control documentation, reference values, or inspectable result
  objects, read
  [documentation-contracts.md](references/documentation-contracts.md).
- Prefer roxygen source edits over direct `man/*.Rd` edits, then regenerate.
- Treat `man/*.Rd` and `NAMESPACE` as generated unless intentionally refreshed.
- Keep generated `man/*.Rd` changes in the same chunk or commit as the roxygen
  source change that produced them. Avoid unrelated generated churn.
- When roxygen blocks move files without wording changes, regenerate docs and
  classify generated `man/*.Rd` diffs that only update
  `% Please edit documentation in ...` source comments as expected source-path
  churn. Run `roxygen2::roxygenise()` a second time to confirm idempotence.
- After `roxygen2::roxygenise()`, inspect `git diff -- DESCRIPTION`
  separately. During an intentional documentation rebuild, retain expected
  generator-version metadata from the installed roxygen release unless the
  repository explicitly pins another generator, and revert unrelated
  `DESCRIPTION` changes. Do not accept incidental documentation churn from a
  command when no rebuild was requested merely because roxygen produced it.
- Do not enable `Roxygen: list(markdown = TRUE)` as an opportunistic partial
  change. Once roxygen markdown is enabled, complete the markdown conversion in
  the same docs-modernization chunk or add an explicit required follow-up chunk
  before formatting, lint, pkgdown, CI, or structural refactors.
- For roxygen markdown audits or package-wide conversions, run
  `${HOME}/.agents/skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh`,
  then follow [roxygen-markdown.md](references/roxygen-markdown.md).
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

Choose scaffolding by authority. For local-only setup, run
`usethis::use_pkgdown()` or copy the complete local feature bundle from a
reference repo. Run `usethis::use_pkgdown_github_pages()` only when remote
Pages and repository-homepage changes are explicitly authorized; it is not a
local-only scaffolding helper.

After any scaffolding helper:

1. Inspect all changes, especially `.github/workflows/pkgdown.yaml` and
   `_pkgdown.yml`.
2. Apply `$r-ci-hardening` whenever a pkgdown workflow is created or changed;
   keep generic workflow-hardening policy in that skill.
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
```

These concise commands assume that the current package is loadable by the
render process and that required caches are writable. Before a focused article
build in a fresh or restricted process, use the temporary-install helper in
[validation.md](references/validation.md#fresh-temporary-library-article-builds).

When a pkgdown workflow changes, also run the required checks from
`$r-ci-hardening`.

Network-restricted environments may need approval for pkgdown external assets
or CRAN metadata.
