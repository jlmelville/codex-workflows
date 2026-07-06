#!/usr/bin/env bash
set -euo pipefail
export UV_CACHE_DIR="${UV_CACHE_DIR:-${TMPDIR:-/tmp}/uv-cache}"
export UV_TOOL_DIR="${UV_TOOL_DIR:-${TMPDIR:-/tmp}/uv-tools}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-${TMPDIR:-/tmp}/uv-python}"

run_zizmor() {
  local target_dir="$1"
  local output

  if command -v zizmor >/dev/null 2>&1; then
    if ! zizmor "${target_dir}"; then
      echo "zizmor reported issues for ${target_dir}." >&2
      return 1
    fi
    return 0
  fi

  if ! command -v uvx >/dev/null 2>&1; then
    echo "zizmor and uvx not found; skipped zizmor." >&2
    if [[ "${CI:-false}" == "true" ]]; then
      echo "zizmor or uvx is required in CI." >&2
      return 1
    fi
    return 0
  fi

  output="$(mktemp)"
  if uvx zizmor "${target_dir}" >"${output}" 2>&1; then
    cat "${output}"
    rm -f "${output}"
    return 0
  fi

  cat "${output}" >&2
  if grep -Eiq 'temporary failure|name or service not known|could not resolve|failed to resolve|dns|pypi|no such host|network is unreachable|connection (refused|reset|timed out|error)|failed to fetch|failed to download|error downloading|request failed|error sending request' "${output}"; then
    echo "uvx could not run zizmor because of network/tool download failure; rerun with network approval or use installed zizmor." >&2
    rm -f "${output}"
    if [[ "${CI:-false}" == "true" ]]; then
      echo "zizmor download/tool acquisition is required to succeed in CI." >&2
      return 1
    fi
    return 0
  fi

  rm -f "${output}"
  echo "zizmor reported issues for ${target_dir}." >&2
  return 1
}

usage() {
  cat <<'USAGE'
Usage: check-r-package.sh [fast|full|ci]

Run from an R package root.

Modes:
  fast  Rcpp attributes when relevant, then testthat::test_local()
  full  fast checks plus Air, lintr, and devtools::check(--no-manual)
  ci    full checks plus actionlint and zizmor when workflows exist

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
  if command -v actionlint >/dev/null 2>&1; then
    actionlint
  fi
  run_zizmor .github/workflows
fi
