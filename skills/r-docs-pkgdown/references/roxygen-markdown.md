# Roxygen Markdown Modernization

Use this when auditing or converting R package roxygen comments after
`Roxygen: list(markdown = TRUE)` is present or being added.

## Completion Rule

Treat enabling `Roxygen: list(markdown = TRUE)` as a docs-modernization
commitment, not a local cleanup. Either complete the full roxygen markdown
conversion immediately or record a required follow-up chunk before moving on to
formatting, lint, pkgdown, CI, or structural refactors.

## Source-First Audit

Prefer the bundled helper over hand-typed searches when it is available:

```sh
${CODEX_HOME:-$HOME/.codex}/skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh --all
```

Use individual modes such as `--raw-rd`, `--md-overrides`, `--odd-backticks`,
`--check-rd`, and `--idempotence` when a full `--all` run is too broad for the
current chunk. In the `codex-workflows` source repo, the helper lives at
`skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh`.

Audit source roxygen before generated output:

1. Check `DESCRIPTION` for `Roxygen: list(markdown = TRUE)`.
2. Search only roxygen comments for markdown overrides and raw Rd macros:

   ```sh
   rg -n "^#'\\s*@(md|noMd)\\b" R
   rg -n "^#'.*\\\\(code|link|url|href|itemize|item|emph|strong|describe|dontrun|donttest|dontshow|eqn|deqn|Sexpr|tabular)" R
   ```

3. Classify intentional raw Rd separately, especially `\eqn{}` and `\deqn{}`
   math and example wrappers such as `\dontrun{}`.
4. Treat ordinary `#` comments from broader source searches as source cleanup
   candidates, not RDoc markdown evidence.
5. Treat `man/*.Rd` macros as expected generated output. Search generated Rd
   only when checking source/generated drift after `roxygen2::roxygenise()`.

## Conversion Review

Convert old `\code{}`, `\emph{}`, `\link{}`, `\doi{}`, and list markup to
markdown. Preserve raw Rd only when markdown is not an equivalent replacement,
such as some math or example-control wrappers.

For inline algebra in markdown roxygen, prefer Rd-friendly plain forms such as
`D^(-1/2)` over TeX-like text in backticks such as `D^{-1/2}`. After
regenerating, inspect `man/*.Rd` for awkward formula rendering, not just the
roxygen source.

For nested list conversions, keep continuation paragraphs indented under the
intended parent bullet. Inspect generated Rd for changed `\itemize{` and `}`
boundaries; successful roxygen generation can still hide list-structure drift.

## Post-Conversion Checks

After a package-wide conversion:

1. Rerun the roxygen-only macro searches and classify intentional leftovers.
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
5. Run `devtools::check(document = FALSE, args = c("--no-manual"))` before
   handing off the docs chunk.
