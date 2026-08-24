# Hardened GitHub Actions Patterns for R Packages

## Shared Hardening

Apply `$github-actions-hardening` for action pins, nearby version comments,
permissions, checkout credentials, concurrency, pull-request safety,
Dependabot, and the shared workflow audit. This reference covers only the R
package semantics that generic workflow tooling cannot validate.

## R Setup

Use the same pinned SHA for `r-lib/actions` actions in a workflow when possible:

```yaml
- uses: r-lib/actions/setup-r@<full-sha>
  with:
    use-public-rspm: true
- uses: r-lib/actions/setup-r-dependencies@<full-sha>
```

## Optional Dependency Coverage

When one `Suggests` package is intentionally unavailable, do not let an ignore
rule hide all optional-path coverage. Use explicitly named jobs with distinct
dependency modes:

- `hard-only` uses `dependencies: '"hard"'` to exercise the package without
  suggested dependencies.
- `available-optional` uses `dependencies: '"all"'`, lists an unavailable
  suggestion as `<package>=?ignore` in `extra-packages`, and sets
  `_R_CHECK_FORCE_SUGGESTS_: false` only where that exception is intentional.

After dependency setup, make the available-optional job fail when any expected
installable suggestion is absent, for example with `requireNamespace()` checks.
Log the ignored package and rationale beside the exception so the reduced
coverage is visible in the job output. `actionlint`, zizmor, and pin audits
validate workflow structure, not hosted dependency resolution; require a
GitHub-hosted run before claiming this matrix is exercised.

## External Source Health

For packages that download external datasets or assets, keep endpoint health
monitoring separate from pull-request tests and `R CMD check`. Use a dedicated
read-only workflow with `workflow_dispatch` and a low-frequency schedule.
Scheduled runs should be advisory by default; a manual input may opt into
strict failure when a maintainer wants a hard availability check.

- Probe a curated manifest of canonical download assets instead of scraping
  README, article, or citation links.
- When the manifest repeats package downloader defaults or URL constants, run
  a cheap local preflight before network work. Check required fields, empty or
  malformed values, duplicate asset identities and URLs, and correspondence
  with source-derived expected URLs so the manifest cannot silently become a
  second source of truth.
- Try `HEAD` first, then fall back to a one-byte range GET for servers that do
  not implement `HEAD` reliably. Use short timeouts and no retries by default;
  allow at most one bounded retry when the host warrants it.
- Pin actions, retain read-only permissions, disable persisted checkout
  credentials, and publish an endpoint-status table in the step summary.

Treat unreachable sources as upstream service state, not package-regression
evidence. Validate workflow structure and exercise parser or manifest behavior
without network access; only a live probe can establish current reachability.

## R CMD Check Vignettes

Static workflow checks do not validate the package semantics of
`r-lib/actions/check-r-package` inputs. When a workflow intentionally skips
vignettes, especially PDF vignettes, check both `rcmdcheck` layers:

- `with.args` passes arguments to `R CMD check`.
- `with.build_args` passes arguments to `R CMD build`.

If the policy is "do not build vignettes" and no `inst/doc` output is expected,
use this shape:

```yaml
- uses: r-lib/actions/check-r-package@<full-sha>
  with:
    args: 'c("--no-manual", "--ignore-vignettes")'
    build_args: 'c("--no-manual", "--no-build-vignettes")'
```

Validate the exact action inputs locally when diagnosing failures:

```sh
Rscript -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--ignore-vignettes"), build_args = c("--no-manual", "--no-build-vignettes"), error_on = "never")'
```

Treat `--no-build-vignettes` in `args` without matching `build_args` as
suspicious: it can leave `R CMD build` free to rebuild vignettes while
`actionlint`, `zizmor`, and action-pin audits still pass.

## Manual R-hub Diagnostics

Static workflow validation does not establish that sanitizer, Valgrind, or
recent-compiler diagnostics actually ran. Before dispatching a manual R-hub
matrix, verify authenticated access without exposing credential values and,
when the workflow requires them, confirm the expected environment and secret
names are configured. Confirm that the dispatch branch contains both the
intended commit and the intended workflow definition.

Dispatch explicit platform inputs and capture the exact resulting run identity;
do not infer it later from whichever run happens to be newest. Wait for every
dynamically resolved platform job, including post-job steps, to reach a terminal
state. Setup success or the first green job is not matrix completion.

For each resolved job, retain the platform or job name, URL, conclusion,
timestamps or runtime, and package-check summary. Inspect both annotations and
logs even when the run is green: annotations may omit package notes, diagnostic
summaries, or nonfatal infrastructure messages.

Classify findings as package behavior, dependency behavior, or R-hub/CI
infrastructure. Preserve package warnings and notes in the acceptance summary;
do not turn a cache race or other post-job service message into a package
failure. After a package fix, rerun the affected diagnostics and re-establish
terminal evidence instead of relying on the earlier matrix.

## Pkgdown

When `usethis::use_pkgdown_github_pages()` rewrites a pkgdown workflow, keep
useful remote Pages/homepage side effects but restore the hardened workflow
shape below. Confirm publishing state through `$r-docs-pkgdown`; actionlint,
zizmor, and SHA audits do not prove that GitHub Pages is enabled or that the
repo homepage points at the pkgdown site.

Hardened shape:

```yaml
name: pkgdown

permissions:
  contents: read

concurrency:
  group: pkgdown-${{ github.event_name != 'pull_request' || github.run_id }}

jobs:
  build-site:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@<full-sha>
        with:
          persist-credentials: false
      - uses: r-lib/actions/setup-pandoc@<full-sha>
      - uses: r-lib/actions/setup-r@<full-sha>
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@<full-sha>
        with:
          extra-packages: any::pkgdown, local::.
          needs: website
      - name: Build site
        run: Rscript -e 'pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)'
      - name: Upload site artifact
        if: github.event_name != 'pull_request'
        uses: actions/upload-artifact@<full-sha>
        with:
          name: pkgdown-site
          path: docs
          if-no-files-found: error

  deploy-site:
    if: github.event_name != 'pull_request'
    needs: build-site
    runs-on: ubuntu-latest
    permissions:
      contents: write # zizmor: ignore[undocumented-permissions] required to publish docs
    steps:
      - uses: actions/checkout@<full-sha>
        with:
          persist-credentials: false
      - uses: actions/download-artifact@<full-sha>
        with:
          name: pkgdown-site
          path: docs
      - uses: JamesIves/github-pages-deploy-action@<full-sha>
        with:
          clean: false
          branch: gh-pages
          folder: docs
```

## Coverage

Treat coverage measurement, report generation, external upload, and badge
display as separate outcomes. A green job proves publication only when the
uploader itself succeeded; direct `covr::codecov()` calls may return a rejected
HTTP response without failing the R step. When a badge disagrees with a recent
job, inspect the job's computed package coverage and terminal upload diagnostic,
then use a local `covr` line map for gap triage while allowing for platform and
compiler instrumentation differences.

When reliable Codecov publication matters, generate a portable report with
`covr`, then upload it through a maintained SHA-pinned action that receives its
token only at the upload step and fails on rejection. `covr::to_cobertura()`
loads `xml2` directly, so install both namespaces explicitly rather than relying
on ambient local packages:

```yaml
- uses: r-lib/actions/setup-r-dependencies@<full-sha>
  with:
    extra-packages: |
      any::covr
      any::xml2
      local::.
    needs: coverage
- name: Generate coverage report
  run: Rscript -e 'cov <- covr::package_coverage(type = "tests"); print(cov); covr::to_cobertura(cov, filename = "cobertura.xml")'
- name: Upload coverage report
  if: >-
    github.actor != 'dependabot[bot]' &&
    (github.event_name != 'pull_request' ||
    github.event.pull_request.head.repo.full_name == github.repository)
  uses: codecov/codecov-action@<full-sha> # v5
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./cobertura.xml
    fail_ci_if_error: true
```

State an explicit policy for actors that cannot receive repository secrets.
Skipping uploads for Dependabot and fork pull requests is often appropriate;
keep report generation active when it still supplies useful test evidence.
Tokenless public upload may remain a deliberate policy when its observed
reliability and failure signaling are acceptable. Add `.covrignore` only for
intentional exclusions.

## Dependabot

Dependabot policy is owned by `$github-actions-hardening`; use its
[Dependabot guidance](../../github-actions-hardening/SKILL.md#dependabot) rather
than maintaining an R-specific copy here.
