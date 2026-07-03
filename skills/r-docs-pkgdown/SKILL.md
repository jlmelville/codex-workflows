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
- Avoid broad roxygen churn during narrow correctness phases.

## pkgdown Workflow

Use complete scaffolding. Either run the relevant `usethis` helper first, or
copy the complete feature bundle from a reference repo.

After `usethis::use_pkgdown_github_pages()` or similar helpers:

1. Inspect all changes, especially `.github/workflows/pkgdown.yaml`.
2. Restore or apply hardened GitHub Actions patterns.
3. Keep `_pkgdown.yml`, `DESCRIPTION` URL/config, `.Rbuildignore`,
   articles, and workflow in sync.
4. Run pkgdown and workflow checks.

See [pkgdown.md](references/pkgdown.md).

## Checks

```sh
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'pkgdown::build_site(new_process = FALSE)'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'
actionlint
uvx zizmor .github/workflows
```

Network-restricted environments may need approval for pkgdown external assets
or CRAN metadata.
