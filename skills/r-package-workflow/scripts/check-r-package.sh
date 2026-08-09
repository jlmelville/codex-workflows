#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
actions_audit="${script_dir}/../../github-actions-hardening/scripts/audit-actions.sh"

usage() {
  cat <<'USAGE'
Usage: check-r-package.sh [fast|full|ci]

Run from an R package root.

Modes:
  fast  Rcpp attributes when relevant, then testthat::test_local()
  full  fast checks plus Air, lintr, and devtools::check(--no-manual)
  ci    full checks plus the shared GitHub Actions audit when workflows exist

Rcpp attributes may update R/RcppExports.R or src/RcppExports.cpp.
USAGE
}

mode="${1:-fast}"
if [[ "${mode}" == "-h" || "${mode}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${mode}" != "fast" && "${mode}" != "full" && "${mode}" != "ci" ]]; then
  echo "check-r-package.sh: unknown mode '${mode}'" >&2
  usage >&2
  exit 2
fi

if [[ ! -f DESCRIPTION ]]; then
  echo "check-r-package.sh: run from an R package root with DESCRIPTION" >&2
  exit 2
fi

has_rcpp=false
if [[ -f src/RcppExports.cpp || -f R/RcppExports.R ]]; then
  has_rcpp=true
fi

if [[ "${has_rcpp}" == true ]]; then
  Rscript -e 'Rcpp::compileAttributes()'
fi

Rscript -e 'testthat::test_local()'

if [[ "${mode}" == "fast" ]]; then
  exit 0
fi

if command -v air >/dev/null 2>&1; then
  air format . --check
else
  echo "air not found; skipped Air format check." >&2
fi

Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'

if [[ "${mode}" == "full" ]]; then
  exit 0
fi

if [[ -d .github/workflows ]]; then
  if [[ ! -x "${actions_audit}" ]]; then
    echo "check-r-package.sh: shared workflow audit not found: ${actions_audit}" >&2
    exit 2
  fi
  "${actions_audit}" .github/workflows
fi
