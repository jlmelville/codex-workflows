#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-skill-smoke.XXXXXX")"
trap 'rm -rf "${tmp_root}"' EXIT

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required for skill script smoke tests" >&2
    return 1
  fi
}

run_notebook_smoke() {
  local script="${repo_dir}/skills/notebook-inspection/scripts/notebook_inspect.py"
  local notebook="${tmp_root}/tiny.ipynb"

  require_command python3
  python3 - "${notebook}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "cells": [
        {"cell_type": "markdown", "metadata": {}, "source": ["alpha notes\n"]},
        {"cell_type": "code", "metadata": {}, "source": ["x = 1\n"], "outputs": []},
    ],
    "metadata": {},
    "nbformat": 4,
    "nbformat_minor": 5,
}), encoding="utf-8")
PY

  python3 "${script}" --help >/dev/null
  python3 "${script}" validate "${notebook}" >/dev/null
  python3 "${script}" stats "${notebook}" >/dev/null
  python3 "${script}" cells --type all "${notebook}" >/dev/null
  python3 "${script}" search --type all alpha "${notebook}" >/dev/null
  if python3 "${script}" search missing "${notebook}" >/dev/null; then
    echo "notebook_inspect.py search should exit 1 when no match is found" >&2
    return 1
  fi
}

run_benchmark_smoke() {
  local script="${repo_dir}/skills/r-performance-workflow/scripts/benchmark-evidence.R"
  local smoke_dir="${tmp_root}/benchmark"
  local cases="${smoke_dir}/cases.R"
  local out_prefix="${smoke_dir}/evidence"

  require_command Rscript
  mkdir -p "${smoke_dir}"
  cat >"${cases}" <<'RS'
benchmark_metadata <- list(scope = "smoke")
benchmark_cases <- list(
  base = function() sum(1:3)
)
RS

  Rscript --vanilla "${script}" --help >/dev/null
  Rscript --vanilla "${script}" "${cases}" --reps 1 --out "${out_prefix}" >/dev/null
  [[ -s "${out_prefix}.csv" ]]
  [[ -s "${out_prefix}.md" ]]
}

run_manifest_smoke() {
  local script="${repo_dir}/skills/local-r-dataset-manifest/scripts/validate_manifest.R"
  local smoke_dir="${tmp_root}/manifest"
  local manifest="${smoke_dir}/manifest.tsv"
  local draft="${smoke_dir}/draft.tsv"

  require_command Rscript
  mkdir -p "${smoke_dir}"
  Rscript --vanilla - "${smoke_dir}" <<'RS'
args <- commandArgs(TRUE)
root <- args[[1L]]

tiny <- list(
  X = matrix(1:4, nrow = 2),
  Y = 1:2,
  nn = list(
    idx = matrix(1L, nrow = 2, ncol = 150),
    dist = matrix(0, nrow = 2, ncol = 150)
  )
)
bundle <- file.path(root, "tinyl.Rda")
save(tiny, file = bundle)

manifest <- data.frame(
  file = "tiny",
  path = bundle,
  basename = "tinyl.Rda",
  X_nrow = 2,
  X_ncol = 2,
  Y_nrow = 2,
  Y_ncol = "",
  Y_length = 2,
  Y_class = "integer",
  Y_colnames = "",
  color_by = "",
  nn_idx_dim = "2x150",
  nn_dist_dim = "2x150",
  nn_k = 150,
  notes = "",
  check.names = FALSE,
  stringsAsFactors = FALSE
)
write.table(
  manifest,
  file = file.path(root, "manifest.tsv"),
  sep = "\t",
  quote = TRUE,
  row.names = FALSE,
  na = ""
)
RS

  Rscript --vanilla "${script}" --help >/dev/null
  Rscript --vanilla "${script}" \
    --manifest "${manifest}" \
    --draft "${draft}" \
    --max-rows 1 >/dev/null
  [[ -s "${draft}" ]]
}

run_roxygen_smoke() {
  local script="${repo_dir}/skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh"
  local pkg_dir="${tmp_root}/roxygen-pkg"

  require_command Rscript
  require_command rg
  mkdir -p "${pkg_dir}/R" "${pkg_dir}/man"
  cat >"${pkg_dir}/DESCRIPTION" <<'EOF_DESCRIPTION'
Package: tiny
Version: 0.0.0
Title: Tiny Package
Description: Tiny package.
License: MIT
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
EOF_DESCRIPTION
  cat >"${pkg_dir}/R/tiny.R" <<'EOF_R'
#' Tiny
#'
#' A tiny function.
#' @return The number 1.
#' @export
tiny <- function() 1
EOF_R
  cat >"${pkg_dir}/man/tiny.Rd" <<'EOF_RD'
\name{tiny}
\alias{tiny}
\title{Tiny}
\usage{tiny()}
\description{Tiny.}
\value{The number 1.}
\keyword{internal}
EOF_RD

  "${script}" --help >/dev/null
  (
    cd "${pkg_dir}"
    "${script}" \
      --check-description \
      --md-overrides \
      --raw-rd \
      --odd-backticks \
      --check-rd >/dev/null
  )
}

run_shell_script_smoke() {
  "${repo_dir}/skills/r-package-workflow/scripts/check-r-package.sh" --help >/dev/null
  "${repo_dir}/skills/r-package-workflow/scripts/audit-generated-r-files.sh" >/dev/null
  "${repo_dir}/skills/github-actions-hardening/scripts/check-action-tag-comments.sh" --help >/dev/null
}

run_skill_index_smoke() {
  ruby "${repo_dir}/scripts/list-skills.rb" >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" --markdown >/dev/null
}

run_notebook_smoke
run_benchmark_smoke
run_manifest_smoke
run_roxygen_smoke
run_shell_script_smoke
run_skill_index_smoke

echo "Skill script smoke tests passed."
