#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-skill-smoke.XXXXXX")"
tmp_root="$(cd "${tmp_root}" && pwd -P)"
trap 'rm -rf "${tmp_root}"' EXIT

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required for skill script smoke tests" >&2
    return 1
  fi
}

assert_usage_error() {
  local label="$1"
  local expected="$2"
  local stdout_file="${tmp_root}/${label}.stdout"
  local stderr_file="${tmp_root}/${label}.stderr"
  local command_status
  shift 2

  if "$@" >"${stdout_file}" 2>"${stderr_file}"; then
    echo "${label} invalid invocation unexpectedly succeeded" >&2
    return 1
  else
    command_status=$?
  fi

  if [[ "${command_status}" -ne 2 ]]; then
    echo "${label} invalid invocation should exit 2, got ${command_status}" >&2
    return 1
  fi
  if [[ -s "${stdout_file}" ]]; then
    echo "${label} invalid invocation should not write standard output" >&2
    return 1
  fi
  if ! grep -Fq -- "${expected}" "${stderr_file}" || ! grep -Fq "Usage:" "${stderr_file}"; then
    echo "${label} invalid invocation did not print its diagnostic and usage" >&2
    return 1
  fi
  if grep -Fq "OptionParser::" "${stderr_file}"; then
    echo "${label} invalid invocation exposed an OptionParser exception" >&2
    return 1
  fi
}

run_notebook_smoke() {
  local script="${repo_dir}/skills/notebook-inspection/scripts/notebook_inspect.py"
  local notebook="${tmp_root}/tiny.ipynb"
  local malformed="${tmp_root}/malformed.ipynb"
  local stdout_file="${tmp_root}/notebook.stdout"
  local stderr_file="${tmp_root}/notebook.stderr"

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
  printf '%s\n' '{"cells": [' >"${malformed}"

  python3 "${script}" --help >/dev/null
  python3 "${script}" validate "${notebook}" >/dev/null
  python3 "${script}" stats "${notebook}" >/dev/null
  python3 "${script}" cells --type all "${notebook}" >/dev/null
  python3 "${script}" search --type all alpha "${notebook}" >/dev/null
  if python3 "${script}" search missing "${notebook}" >/dev/null; then
    echo "notebook_inspect.py search should exit 1 when no match is found" >&2
    return 1
  fi
  if python3 "${script}" stats "${notebook}" "${malformed}" \
    >"${stdout_file}" 2>"${stderr_file}"; then
    echo "notebook_inspect.py stats should fail after a partial parse" >&2
    return 1
  fi
  grep -Fq "${notebook}" "${stdout_file}"
  grep -Fq "parse failed" "${stderr_file}"
  if python3 "${script}" search --type all alpha "${tmp_root}" \
    >"${stdout_file}" 2>"${stderr_file}"; then
    echo "notebook_inspect.py search should fail after a partial parse" >&2
    return 1
  fi
  grep -Fq "alpha notes" "${stdout_file}"
  grep -Fq "failed to parse notebook" "${stderr_file}"
  if python3 "${script}" outputs --limit 0 "${notebook}" \
    >"${stdout_file}" 2>"${stderr_file}"; then
    echo "notebook_inspect.py outputs should reject a nonpositive limit" >&2
    return 1
  fi
  [[ ! -s "${stdout_file}" ]]
  grep -Fq "must be a positive integer" "${stderr_file}"
}

run_benchmark_smoke() {
  local script="${repo_dir}/skills/r-performance-workflow/scripts/benchmark-evidence.R"
  local smoke_dir="${tmp_root}/benchmark"
  local cases="${smoke_dir}/cases.R"
  local out_prefix="${smoke_dir}/evidence"
  local alias_cases="${smoke_dir}/alias-cases.R"
  local alias_prefix="${smoke_dir}/alias-evidence"
  local sentinel="${smoke_dir}/evidence-work-started"
  local stdout_file="${smoke_dir}/alias.stdout"
  local stderr_file="${smoke_dir}/alias.stderr"

  require_command Rscript
  require_command ln
  mkdir -p "${smoke_dir}"
  cat >"${cases}" <<'RS'
benchmark_metadata <- list(scope = "smoke")
benchmark_cases <- list(
  base = function() {
    Sys.sleep(0.01)
    sum(1:3)
  }
)
RS
  cat >"${alias_cases}" <<'RS'
sentinel <- Sys.getenv("BENCHMARK_SMOKE_SENTINEL")
if (nzchar(sentinel)) {
  writeLines("sourced", sentinel)
}
benchmark_cases <- list(base = function() sum(1:3))
RS

  Rscript --vanilla "${script}" --help >/dev/null
  Rscript --vanilla "${script}" "${cases}" --reps 1 --out "${out_prefix}" >/dev/null
  if Rscript --vanilla "${script}" "${cases}" --baseline missing --out "${out_prefix}-missing" >/dev/null 2>&1; then
    echo "benchmark-evidence.R should fail for an unknown baseline" >&2
    return 1
  fi
  [[ -s "${out_prefix}.csv" ]]
  [[ -s "${out_prefix}.md" ]]

  printf '%s\n' 'preserved' >"${alias_prefix}.csv"
  ln "${alias_prefix}.csv" "${alias_prefix}.md"
  if BENCHMARK_SMOKE_SENTINEL="${sentinel}" \
    Rscript --vanilla "${script}" "${alias_cases}" --out "${alias_prefix}" \
    >"${stdout_file}" 2>"${stderr_file}"; then
    echo "benchmark-evidence.R should reject aliased output files" >&2
    return 1
  fi
  [[ ! -e "${sentinel}" ]]
  [[ ! -s "${stdout_file}" ]]
  grep -Fq "existing outputs alias the same filesystem object" "${stderr_file}"
  [[ "$(<"${alias_prefix}.csv")" == "preserved" ]]
  [[ "$(<"${alias_prefix}.md")" == "preserved" ]]

  if BENCHMARK_SMOKE_SENTINEL="${sentinel}" \
    Rscript --vanilla "${script}" "${alias_cases}" --out "" \
    >"${stdout_file}" 2>"${stderr_file}"; then
    echo "benchmark-evidence.R should reject an empty output prefix" >&2
    return 1
  fi
  [[ ! -e "${sentinel}" ]]
  [[ ! -s "${stdout_file}" ]]
  grep -Fq -- "--out must be a non-empty path prefix" "${stderr_file}"
}

run_architecture_audit_smoke() {
  local map_script="${repo_dir}/skills/r-architecture-audit/scripts/r-architecture-map.R"
  local diff_script="${repo_dir}/skills/r-architecture-audit/scripts/r-architecture-diff.R"
  local trace_script="${repo_dir}/skills/r-architecture-audit/scripts/r-value-family-trace.R"

  require_command Rscript
  Rscript --vanilla "${map_script}" --help >/dev/null
  Rscript --vanilla "${map_script}" --self-test >/dev/null
  Rscript --vanilla "${diff_script}" --help >/dev/null
  Rscript --vanilla "${diff_script}" --self-test >/dev/null
  Rscript --vanilla "${trace_script}" --help >/dev/null
  Rscript --vanilla "${trace_script}" --self-test >/dev/null
}

run_manifest_smoke() {
  local script="${repo_dir}/skills/local-r-dataset-manifest/scripts/validate_manifest.R"
  local smoke_dir="${tmp_root}/manifest"
  local manifest="${smoke_dir}/manifest.tsv"
  local draft="${smoke_dir}/draft.tsv"
  local outside_manifest="${smoke_dir}/outside.tsv"
  local outside_draft="${smoke_dir}/outside-draft.tsv"
  local before="${smoke_dir}/manifest.before"
  local stdout_file="${smoke_dir}/manifest.stdout"
  local stderr_file="${smoke_dir}/manifest.stderr"

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

outside_root <- paste0(root, "-outside")
dir.create(outside_root)
outside_bundle <- file.path(outside_root, "tinyl.Rda")
save(tiny, file = outside_bundle)
outside_manifest <- manifest
outside_manifest$path <- outside_bundle
write.table(
  outside_manifest,
  file = file.path(root, "outside.tsv"),
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

  cp "${manifest}" "${before}"
  if Rscript --vanilla "${script}" \
    --manifest "${manifest}" \
    --draft "${smoke_dir}/partial.tsv" \
    --max-rows 1 \
    --replace >"${stdout_file}" 2>"${stderr_file}"; then
    echo "validate_manifest.R should reject partial replacement" >&2
    return 1
  fi
  cmp -s "${manifest}" "${before}"
  [[ ! -e "${smoke_dir}/partial.tsv" ]]
  grep -Fq -- "--replace cannot be combined with --max-rows" "${stderr_file}"

  if Rscript --vanilla "${script}" \
    --manifest "${outside_manifest}" \
    --draft "${outside_draft}" >"${stdout_file}" 2>"${stderr_file}"; then
    echo "validate_manifest.R should reject a sibling-prefix bundle path" >&2
    return 1
  fi
  grep -Fq "path is outside data root" "${stdout_file}"
  [[ ! -e "${outside_draft}" ]]

  Rscript --vanilla "${script}" \
    --manifest "${manifest}" \
    --draft "${smoke_dir}/replacement.tsv" \
    --replace >"${stdout_file}"
  grep -Fq "replaced ${manifest}" "${stdout_file}"
  Rscript --vanilla "${script}" --manifest "${manifest}" --draft "${draft}" >/dev/null

  cp "${manifest}" "${before}"
  chmod a-w "${smoke_dir}"
  local write_failure_status=0
  if Rscript --vanilla "${script}" \
    --manifest "${manifest}" \
    --draft "${tmp_root}/manifest-write-failure-draft.tsv" \
    --replace >"${tmp_root}/manifest-write-failure.stdout" \
    2>"${tmp_root}/manifest-write-failure.stderr"; then
    write_failure_status=0
  else
    write_failure_status=$?
  fi
  chmod u+w "${smoke_dir}"
  if [[ "${write_failure_status}" -eq 0 ]]; then
    echo "validate_manifest.R should preserve the manifest on staging failure" >&2
    return 1
  fi
  cmp -s "${manifest}" "${before}"
  grep -Fq "failed to stage replacement beside manifest" \
    "${tmp_root}/manifest-write-failure.stderr"
}

run_roxygen_smoke() {
  local script="${repo_dir}/skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh"
  local pkg_dir="${tmp_root}/roxygen-pkg"
  local idempotence_dir="${tmp_root}/roxygen-idempotence"
  local fake_bin="${tmp_root}/fake-rscript-bin"

  require_command Rscript
  require_command git
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

  mkdir -p "${idempotence_dir}/man" "${fake_bin}"
  cat >"${idempotence_dir}/DESCRIPTION" <<'EOF_IDEMPOTENCE_DESCRIPTION'
Package: tiny
Version: 0.0.0
Title: Tiny Package
Description: Tiny package.
License: MIT
Encoding: UTF-8
EOF_IDEMPOTENCE_DESCRIPTION
  cat >"${idempotence_dir}/man/tiny.Rd" <<'EOF_IDEMPOTENCE_RD'
\name{tiny}
\title{Tiny}
EOF_IDEMPOTENCE_RD
  cat >"${fake_bin}/Rscript" <<'EOF_FAKE_RSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "--vanilla" && "$2" == "-e" ]]; then
  cat >man/tiny.Rd <<'EOF_FAKE_RD'
\name{tiny}
\title{Tiny changed}
EOF_FAKE_RD
  exit 0
fi

echo "unexpected Rscript invocation: $*" >&2
exit 1
EOF_FAKE_RSCRIPT
  chmod +x "${fake_bin}/Rscript"
  (
    cd "${idempotence_dir}"
    git init >/dev/null 2>&1
    if PATH="${fake_bin}:${PATH}" "${script}" --idempotence >/dev/null 2>&1; then
      echo "roxygen idempotence should detect untracked generated-file content changes" >&2
      exit 1
    fi
  )
}

run_document_validation_smoke() {
  local script="${repo_dir}/skills/r-docs-pkgdown/scripts/validate-document.R"
  local smoke_dir="${tmp_root}/document-validation"
  local dependency_sources="${smoke_dir}/dependency-sources"
  local dependency_library="${smoke_dir}/dependency-library"
  local package_dir="${smoke_dir}/tinyarticle"
  local stdout_file="${smoke_dir}/document-validation.stdout"

  require_command R
  require_command Rscript
  mkdir -p \
    "${dependency_sources}/rmarkdown/R" \
    "${dependency_sources}/pkgdown/R" \
    "${dependency_library}" \
    "${package_dir}/R" \
    "${package_dir}/inst/doc" \
    "${package_dir}/vignettes"

  cat >"${dependency_sources}/rmarkdown/DESCRIPTION" <<'EOF_RMARKDOWN_DESCRIPTION'
Package: rmarkdown
Type: Package
Title: Smoke-Test R Markdown Stub
Version: 0.0.0
Authors@R: person("Skill", "Smoke", email = "smoke@example.invalid", role = c("aut", "cre"))
Description: Minimal render implementation for repository smoke tests.
License: MIT
Encoding: UTF-8
EOF_RMARKDOWN_DESCRIPTION
  printf '%s\n' 'export(render)' >"${dependency_sources}/rmarkdown/NAMESPACE"
  cat >"${dependency_sources}/rmarkdown/R/render.R" <<'EOF_RMARKDOWN_R'
render <- function(input, output_dir, envir, quiet) {
  stopifnot(file.exists(input), is.environment(envir), isTRUE(quiet))
  stopifnot(requireNamespace("tinyarticle", quietly = TRUE))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(output_dir, paste0(tools::file_path_sans_ext(basename(input)), ".html"))
  writeLines(as.character(tinyarticle::tiny_value()), output)
  normalizePath(output, mustWork = TRUE)
}
EOF_RMARKDOWN_R

  cat >"${dependency_sources}/pkgdown/DESCRIPTION" <<'EOF_PKGDOWN_DESCRIPTION'
Package: pkgdown
Type: Package
Title: Smoke-Test pkgdown Stub
Version: 0.0.0
Authors@R: person("Skill", "Smoke", email = "smoke@example.invalid", role = c("aut", "cre"))
Description: Minimal article implementation for repository smoke tests.
License: MIT
Encoding: UTF-8
EOF_PKGDOWN_DESCRIPTION
  printf '%s\n' 'export(build_article)' >"${dependency_sources}/pkgdown/NAMESPACE"
  cat >"${dependency_sources}/pkgdown/R/build-article.R" <<'EOF_PKGDOWN_R'
build_article <- function(name, pkg, new_process, override, quiet) {
  stopifnot(
    identical(name, "tiny"),
    dir.exists(pkg),
    identical(new_process, FALSE),
    isTRUE(quiet),
    requireNamespace("tinyarticle", quietly = TRUE)
  )
  destination <- override$destination
  article_dir <- file.path(destination, "articles")
  dir.create(article_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(article_dir, "tiny.html")
  writeLines(as.character(tinyarticle::tiny_value()), output)
  invisible(output)
}
EOF_PKGDOWN_R

  cat >"${package_dir}/DESCRIPTION" <<'EOF_PACKAGE_DESCRIPTION'
Package: tinyarticle
Type: Package
Title: Tiny Article Package
Version: 0.0.0
Authors@R: person("Skill", "Smoke", email = "smoke@example.invalid", role = c("aut", "cre"))
Description: Minimal package for document-validation smoke tests.
License: MIT
Encoding: UTF-8
EOF_PACKAGE_DESCRIPTION
  printf '%s\n' 'export(tiny_value)' >"${package_dir}/NAMESPACE"
  printf '%s\n' 'tiny_value <- function() 1L' >"${package_dir}/R/tiny.R"
  printf '%s\n' 'installed proof' >"${package_dir}/inst/doc/proof.txt"
  printf '%s\n' '---' 'title: Tiny' '---' 'Smoke test.' >"${package_dir}/vignettes/tiny.Rmd"

  R CMD INSTALL --library="${dependency_library}" \
    "${dependency_sources}/rmarkdown" >/dev/null 2>&1
  R CMD INSTALL --library="${dependency_library}" \
    "${dependency_sources}/pkgdown" >/dev/null 2>&1

  Rscript --vanilla "${script}" --help >/dev/null
  assert_usage_error \
    "document-validation-missing-mode" \
    "choose exactly one of --rmarkdown or --pkgdown" \
    Rscript --vanilla "${script}"
  assert_usage_error \
    "document-validation-artifact-without-build" \
    "--expect-installed-doc requires --build-source" \
    Rscript --vanilla "${script}" \
      --rmarkdown vignettes/tiny.Rmd \
      --expect-installed-doc proof.txt

  (
    cd "${package_dir}"
    R_LIBS_USER="${dependency_library}" \
      Rscript --vanilla "${script}" \
        --rmarkdown vignettes/tiny.Rmd \
        --build-source \
        --expect-installed-doc proof.txt >"${stdout_file}"
  )
  grep -Fq \
    "Validated rmarkdown target vignettes/tiny.Rmd using a temporary install of the built source tarball." \
    "${stdout_file}"
  [[ ! -e "${package_dir}/tiny.html" ]]

  (
    cd "${package_dir}"
    R_LIBS_USER="${dependency_library}" \
      Rscript --vanilla "${script}" --pkgdown tiny >"${stdout_file}"
  )
  grep -Fq \
    "Validated pkgdown target tiny using a temporary install of the source directory." \
    "${stdout_file}"
  [[ ! -d "${package_dir}/docs" ]]
}

run_shell_script_smoke() {
  "${repo_dir}/skills/r-package-workflow/scripts/check-r-package.sh" --help >/dev/null
  "${repo_dir}/skills/r-package-workflow/scripts/audit-generated-r-files.sh" >/dev/null
  "${repo_dir}/skills/github-actions-hardening/scripts/check-action-tag-comments.sh" --help >/dev/null
}

run_long_process_observer_smoke() {
  local script="${repo_dir}/skills/r-package-workflow/scripts/observe-long-r-process.sh"
  local state_dir="${tmp_root}/long-process-state"
  local output="${tmp_root}/long-process.stdout"
  local stderr_file="${tmp_root}/long-process.stderr"
  local sleep_pid
  local command_status

  mkdir -p "${state_dir}"
  printf '%s\n' old >"${state_dir}/old-checkpoint.rds"
  printf '%s\n' new >"${state_dir}/new-checkpoint.rds"

  "${script}" --help >/dev/null
  assert_usage_error \
    "long-process-invalid-pid" \
    "PID must be a positive integer" \
    "${script}" 0
  assert_usage_error \
    "long-process-missing-root" \
    "state root is not a directory" \
    "${script}" "$$" --state-root "${state_dir}/missing"

  sleep 30 &
  sleep_pid=$!
  if ! "${script}" "${sleep_pid}" --state-root "${state_dir}" >"${output}"; then
    kill "${sleep_pid}" 2>/dev/null || true
    wait "${sleep_pid}" 2>/dev/null || true
    return 1
  fi
  kill "${sleep_pid}" 2>/dev/null || true
  wait "${sleep_pid}" 2>/dev/null || true
  grep -Eq $'^snapshot_utc\t[0-9]{4}-[0-9]{2}-[0-9]{2}T' "${output}"
  grep -Fq $'parent\t'"${sleep_pid}"$'\t' "${output}"
  grep -Fq $'descendant_count\t0' "${output}"
  grep -Fq $'state_root\t'"${state_dir}" "${output}"
  grep -Fq $'filesystem_kib\t' "${output}"
  grep -Fq 'new-checkpoint.rds' "${output}"

  "${script}" "$$" >"${output}"
  grep -Eq $'^descendant_count\t[1-9][0-9]*$' "${output}"

  if "${script}" 999999999 >"${output}" 2>"${stderr_file}"; then
    echo "observe-long-r-process.sh should reject an unavailable process" >&2
    return 1
  else
    command_status=$?
  fi
  [[ "${command_status}" -eq 1 ]]
  [[ ! -s "${output}" ]]
  grep -Fq 'process is not running or not visible: 999999999' "${stderr_file}"
}

run_r_package_check_smoke() {
  local script="${repo_dir}/skills/r-package-workflow/scripts/check-r-package.sh"
  local pkg_dir="${tmp_root}/r-package-check"
  local empty_dir="${tmp_root}/r-package-check-empty"
  local fake_bin="${tmp_root}/r-package-check-bin"
  local log="${tmp_root}/r-package-check.log"
  local audit_output
  local command_status

  mkdir -p \
    "${pkg_dir}/R" "${pkg_dir}/src" "${pkg_dir}/.github/workflows" \
    "${empty_dir}" "${fake_bin}"
  printf '%s\n' 'Package: tiny' 'Version: 0.0.0' >"${pkg_dir}/DESCRIPTION"
  printf '%s\n' '# generated fixture' >"${pkg_dir}/R/RcppExports.R"
  cat >"${pkg_dir}/.github/workflows/check.yml" <<'EOF_WORKFLOW'
name: check
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF_WORKFLOW

  for command_name in Rscript air actionlint zizmor; do
    cat >"${fake_bin}/${command_name}" <<'EOF_COMMAND'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$0") $*" >>"${SMOKE_LOG}"
EOF_COMMAND
    chmod +x "${fake_bin}/${command_name}"
  done

  : >"${log}"
  (
    cd "${pkg_dir}"
    PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" fast >/dev/null
  )
  [[ "$(wc -l <"${log}")" -eq 2 ]]
  grep -Fq 'Rscript -e Rcpp::compileAttributes()' "${log}"
  grep -Fq 'Rscript -e testthat::test_local()' "${log}"

  rm "${pkg_dir}/R/RcppExports.R"
  printf '%s\n' '# generated cpp11 R fixture' >"${pkg_dir}/R/cpp11.R"
  printf '%s\n' '// generated cpp11 C++ fixture' >"${pkg_dir}/src/cpp11.cpp"
  : >"${log}"
  (
    cd "${pkg_dir}"
    PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" fast >/dev/null
  )
  [[ "$(wc -l <"${log}")" -eq 2 ]]
  grep -Fq 'Rscript -e cpp11::cpp_register()' "${log}"
  grep -Fq 'Rscript -e testthat::test_local()' "${log}"

  git -C "${pkg_dir}" init >/dev/null 2>&1
  audit_output="$(cd "${pkg_dir}" && \
    "${repo_dir}/skills/r-package-workflow/scripts/audit-generated-r-files.sh")"
  grep -Fq 'R/cpp11.R' <<<"${audit_output}"
  grep -Fq 'src/cpp11.cpp' <<<"${audit_output}"

  printf '%s\n' '# generated Rcpp fixture' >"${pkg_dir}/R/RcppExports.R"
  : >"${log}"
  if (
    cd "${pkg_dir}" &&
      PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" fast \
        >/dev/null 2>"${tmp_root}/r-package-mixed.stderr"
  ); then
    echo "check-r-package.sh should reject mixed binding families" >&2
    return 1
  fi
  [[ ! -s "${log}" ]]
  grep -Fq 'both Rcpp and cpp11 generated bindings are present' \
    "${tmp_root}/r-package-mixed.stderr"
  rm "${pkg_dir}/R/RcppExports.R"

  : >"${log}"
  (
    cd "${pkg_dir}"
    PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" full >/dev/null
  )
  [[ "$(wc -l <"${log}")" -eq 5 ]]
  grep -Fq 'air format . --check' "${log}"
  grep -Fq 'lintr::lint_package()' "${log}"
  grep -Fq \
    'Rscript -e devtools::check(document = FALSE, args = c("--no-manual"), error_on = "note")' \
    "${log}"

  mv "${fake_bin}/air" "${fake_bin}/air.saved"
  : >"${log}"
  if (
    cd "${pkg_dir}" &&
      PATH="${fake_bin}:/usr/bin:/bin" SMOKE_LOG="${log}" "${script}" full \
        >/dev/null 2>"${tmp_root}/r-package-air.stderr"
  ); then
    command_status=0
  else
    command_status=$?
  fi
  mv "${fake_bin}/air.saved" "${fake_bin}/air"
  if [[ "${command_status}" -eq 0 ]]; then
    echo "check-r-package.sh full should require Air" >&2
    return 1
  fi
  [[ "${command_status}" -eq 2 ]]
  [[ ! -s "${log}" ]]
  grep -Fq 'air is required for full mode' \
    "${tmp_root}/r-package-air.stderr"

  : >"${log}"
  (
    cd "${pkg_dir}"
    PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" ci >/dev/null
  )
  grep -Fq 'actionlint ' "${log}"
  grep -Fq 'zizmor -qq --no-progress .github/workflows' "${log}"

  if (cd "${pkg_dir}" && "${script}" unknown >/dev/null 2>&1); then
    echo "check-r-package.sh should reject an unknown mode" >&2
    return 1
  fi
  if (cd "${empty_dir}" && "${script}" fast >/dev/null 2>&1); then
    echo "check-r-package.sh should require DESCRIPTION" >&2
    return 1
  fi
}

run_audit_actions_smoke() {
  local script="${repo_dir}/skills/github-actions-hardening/scripts/audit-actions.sh"
  local workflow_dir="${tmp_root}/audit-actions-commented-only"
  local fake_bin="${tmp_root}/audit-actions-fake-bin"
  local uvx_fake_bin="${tmp_root}/audit-actions-uvx-fake-bin"
  local output

  mkdir -p "${workflow_dir}" "${fake_bin}" "${uvx_fake_bin}"
  cat >"${workflow_dir}/commented.yml" <<'EOF_COMMENTED_WORKFLOW'
name: commented
jobs:
  test:
    steps:
      # - uses: actions/checkout@v4
      # - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567
      - run: echo ok
EOF_COMMENTED_WORKFLOW
  cat >"${fake_bin}/actionlint" <<'EOF_FAKE_ACTIONLINT'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_FAKE_ACTIONLINT
  cat >"${fake_bin}/zizmor" <<'EOF_FAKE_ZIZMOR'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_FAKE_ZIZMOR
  chmod +x "${fake_bin}/actionlint" "${fake_bin}/zizmor"

  PATH="${fake_bin}:${PATH}" "${script}" "${workflow_dir}" >/dev/null
  output="$(PATH="${fake_bin}:${PATH}" "${script}" --quiet "${workflow_dir}")"
  [[ "${output}" == "GitHub Actions audit completed." ]]

  if "${script}" --bogus "${workflow_dir}" >/dev/null 2>&1; then
    echo "audit-actions.sh should reject an unknown option" >&2
    return 1
  fi

  cat >"${uvx_fake_bin}/actionlint" <<'EOF_FAKE_ACTIONLINT'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_FAKE_ACTIONLINT
  cat >"${uvx_fake_bin}/uvx" <<'EOF_FAKE_UVX'
#!/usr/bin/env bash
set -euo pipefail

filtered_args=()
for arg in "$@"; do
  case "${arg}" in
    --quiet | --no-progress) ;;
    *) filtered_args+=("${arg}") ;;
  esac
done
set -- "${filtered_args[@]}"

case "${FAKE_UVX_MODE:-}" in
  launcher)
    exit 1
    ;;
  findings)
    if [[ "${1:-}" == "zizmor" && "${2:-}" == "--version" ]]; then
      echo "zizmor 1.0.0"
      exit 0
    fi
    echo "warning[audit]: representative analyzer finding" >&2
    exit 1
    ;;
  *)
    echo "unexpected fake uvx mode" >&2
    exit 2
    ;;
esac
EOF_FAKE_UVX
  chmod +x "${uvx_fake_bin}/actionlint" "${uvx_fake_bin}/uvx"

  if ! output="$(
    PATH="${uvx_fake_bin}:/usr/bin:/bin" CI=false FAKE_UVX_MODE=launcher \
      "${script}" --quiet "${workflow_dir}" 2>&1
  )"; then
    printf '%s\n' "${output}" >&2
    echo "audit-actions.sh should tolerate an empty uvx launcher failure outside CI" >&2
    return 1
  fi
  grep -Fq 'uvx could not execute zizmor' <<<"${output}"
  if grep -Fq 'zizmor reported issues' <<<"${output}"; then
    echo "audit-actions.sh should not label an empty uvx launcher failure as a zizmor finding" >&2
    return 1
  fi

  if output="$(
    PATH="${uvx_fake_bin}:/usr/bin:/bin" CI=true FAKE_UVX_MODE=launcher \
      "${script}" --quiet "${workflow_dir}" 2>&1
  )"; then
    echo "audit-actions.sh should reject an empty uvx launcher failure in CI" >&2
    return 1
  fi
  grep -Fq 'uvx could not execute zizmor' <<<"${output}"
  grep -Fq 'zizmor execution is required to succeed in CI' <<<"${output}"

  if output="$(
    PATH="${uvx_fake_bin}:/usr/bin:/bin" FAKE_UVX_MODE=findings \
      "${script}" --quiet "${workflow_dir}" 2>&1
  )"; then
    echo "audit-actions.sh should fail when zizmor reports findings" >&2
    return 1
  fi
  grep -Fq 'representative analyzer finding' <<<"${output}"
  grep -Fq 'zizmor reported issues' <<<"${output}"
}

run_action_tag_comment_smoke() {
  local script="${repo_dir}/skills/github-actions-hardening/scripts/check-action-tag-comments.sh"
  local sha="0123456789abcdef0123456789abcdef01234567"
  local workflow_dir="${tmp_root}/action-tags"
  local verify_dir="${tmp_root}/action-tags-verify"
  local fake_bin="${tmp_root}/fake-git-bin"
  local peeled_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  local output

  mkdir -p "${workflow_dir}"

  cat >"${workflow_dir}/inline.yml" <<EOF_INLINE
name: inline
jobs:
  test:
    steps:
      - uses: actions/checkout@${sha} # v4
EOF_INLINE
  "${script}" --require-tag "${workflow_dir}" >/dev/null
  "${script}" --require-tag "${workflow_dir}/inline.yml" >/dev/null
  output="$("${script}" --quiet --require-tag "${workflow_dir}/inline.yml")"
  [[ -z "${output}" ]]

  if "${script}" --require-tag "${workflow_dir}/missing.yml" >/dev/null 2>&1; then
    echo "an invalid explicit workflow target should fail" >&2
    return 1
  fi

  local no_workflow_dir="${tmp_root}/action-tags-no-default"
  mkdir -p "${no_workflow_dir}"
  (cd "${no_workflow_dir}" && "${script}" --require-tag >/dev/null 2>&1)

  cat >"${workflow_dir}/preceding.yml" <<EOF_PRECEDING
name: preceding
jobs:
  test:
    steps:
      - name: Checkout
        # Pinned to actions/checkout v4.
        uses: actions/checkout@${sha}
EOF_PRECEDING
  "${script}" --require-tag "${workflow_dir}" >/dev/null

  cat >"${workflow_dir}/nested.yml" <<EOF_NESTED
name: nested
jobs:
  test:
    steps:
      - name: Setup R
        # Pinned to r-lib/actions/setup-r v2.
        uses: r-lib/actions/setup-r@${sha}
EOF_NESTED
  if ! output="$("${script}" --require-tag "${workflow_dir}")"; then
    echo "nested action path smoke test failed unexpectedly" >&2
    return 1
  fi
  if [[ "${output}" != *"r-lib/actions/setup-r@${sha}"* ]]; then
    echo "nested action path was not reported by check-action-tag-comments.sh" >&2
    return 1
  fi

  cat >"${workflow_dir}/reason-comment.yml" <<EOF_REASON
name: reason-comment
jobs:
  test:
    steps:
      - name: Checkout
        # Pinned to a full-length SHA for immutability.
        uses: actions/checkout@${sha}
EOF_REASON
  "${script}" --require-comment "${workflow_dir}" >/dev/null
  if "${script}" --require-tag "${workflow_dir}" >/dev/null 2>&1; then
    echo "tag-required mode should fail on reason-only comments" >&2
    return 1
  fi

  mkdir -p "${verify_dir}" "${fake_bin}"
  cat >"${fake_bin}/git" <<'EOF_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" != "ls-remote" ]]; then
  echo "unexpected git command: $*" >&2
  exit 1
fi
if [[ "$3" != "https://github.com/r-lib/actions.git" ]]; then
  echo "nested action should resolve against r-lib/actions, got: $3" >&2
  exit 1
fi

printf '%s\trefs/tags/v1\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
printf '%s\trefs/tags/v1^{}\n' "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
EOF_GIT
  chmod +x "${fake_bin}/git"
  cat >"${verify_dir}/annotated.yml" <<EOF_ANNOTATED
name: annotated
jobs:
  test:
    steps:
      - name: Setup R
        # Pinned to r-lib/actions/setup-r v1.
        uses: r-lib/actions/setup-r@${peeled_sha}
EOF_ANNOTATED
  PATH="${fake_bin}:${PATH}" "${script}" --require-tag --verify-remote "${verify_dir}" >/dev/null

  cat >"${workflow_dir}/missing-comment.yml" <<EOF_MISSING
name: missing-comment
jobs:
  test:
    steps:
      - uses: actions/checkout@${sha}
EOF_MISSING
  if "${script}" --require-comment "${workflow_dir}" >/dev/null 2>&1; then
    echo "comment-required mode should fail when a pin has no nearby comment" >&2
    return 1
  fi

  local commented_only_dir="${tmp_root}/action-tags-commented-only"
  mkdir -p "${commented_only_dir}"
  cat >"${commented_only_dir}/commented.yml" <<EOF_COMMENTED
name: commented
jobs:
  test:
    steps:
      # - uses: actions/checkout@${sha}
      - run: echo ok
EOF_COMMENTED
  "${script}" --require-tag "${commented_only_dir}" >/dev/null
}

run_skill_index_smoke() {
  local fixture="${tmp_root}/list-skills"
  local fixture_script="${fixture}/scripts/list-skills.rb"
  local fixture_error="${fixture}/error"
  local fixture_catalog="${fixture}/catalog"

  ruby "${repo_dir}/scripts/list-skills.rb" --help >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" --markdown >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" --catalog >/dev/null
  assert_usage_error \
    "list-skills-invalid-option" \
    "list-skills.rb: invalid option: --bogus" \
    ruby "${repo_dir}/scripts/list-skills.rb" --bogus
  assert_usage_error \
    "list-skills-extra-argument" \
    "list-skills.rb: unexpected argument: extra" \
    ruby "${repo_dir}/scripts/list-skills.rb" extra

  mkdir -p \
    "${fixture}/scripts" \
    "${fixture}/skills/example/agents" \
    "${fixture}/skills/example/assets" \
    "${fixture}/skills/example/references" \
    "${fixture}/skills/example/scripts"
  cp "${repo_dir}/scripts/list-skills.rb" "${fixture_script}"
  cat >"${fixture}/skills/example/SKILL.md" <<'EOF_SKILL_INDEX'
---
name: example
description: Exercise skill index catalogue and metadata errors.
---

# Example
EOF_SKILL_INDEX
  cat >"${fixture}/skills/example/agents/openai.yaml" <<'EOF_SKILL_INDEX_AGENTS'
interface:
  display_name: "Example Skill"
  short_description: "Exercise capability discovery"
  default_prompt: "Use $example to inspect a tiny fixture."
EOF_SKILL_INDEX_AGENTS
  touch \
    "${fixture}/skills/example/assets/example.txt" \
    "${fixture}/skills/example/references/example.md" \
    "${fixture}/skills/example/scripts/example.rb"
  ruby "${fixture_script}" --catalog >"${fixture_catalog}"
  grep -Fq "Example Skill (\$example)" "${fixture_catalog}"
  grep -Fq 'Does: Exercise capability discovery' "${fixture_catalog}"
  grep -Fq 'Use when: Exercise skill index catalogue and metadata errors.' "${fixture_catalog}"
  grep -Fq "Try: Use \$example to inspect a tiny fixture." "${fixture_catalog}"
  grep -Fq 'Includes: 1 script, 1 reference, 1 asset' "${fixture_catalog}"

  cat >"${fixture}/skills/example/agents/openai.yaml" <<'EOF_SKILL_INDEX_AGENTS'
interface: []
EOF_SKILL_INDEX_AGENTS
  if ruby "${fixture_script}" >/dev/null 2>"${fixture_error}"; then
    echo "skill index accepted a non-mapping interface" >&2
    return 1
  fi
  if ! grep -Fq "interface must be a YAML mapping" "${fixture_error}" ||
    grep -Eq "NoMethodError|TypeError|Psych::" "${fixture_error}"; then
    cat "${fixture_error}" >&2
    echo "skill index did not normalize a metadata shape error" >&2
    return 1
  fi
}

run_skill_metadata_smoke() {
  local script="${repo_dir}/scripts/validate-skill-metadata.rb"
  local fixture="${tmp_root}/skill-metadata"
  local agents="${fixture}/skills/example/agents/openai.yaml"
  local scripts="${fixture}/skills/example/scripts"
  local stderr_file="${fixture}/metadata.stderr"

  mkdir -p "${fixture}/skills/example/agents" "${scripts}"
  cat >"${fixture}/skills/example/SKILL.md" <<'EOF_SKILL'
---
name: example
description: Validate metadata fixture behavior.
---

# Example

Use `scripts/referenced.rb` for the public helper.
EOF_SKILL
  cat >"${agents}" <<'EOF_AGENTS'
interface:
  display_name: "Example"
  short_description: "Validate a metadata fixture"
  default_prompt: "Use $example to exercise metadata validation."
EOF_AGENTS
  printf '%s\n' '# referenced helper' >"${scripts}/referenced.rb"

  ruby "${script}" "${fixture}" >/dev/null
  printf '%s\n' '# orphaned helper' >"${scripts}/orphaned.rb"
  if ruby "${script}" "${fixture}" >/dev/null 2>"${stderr_file}"; then
    echo "skill metadata validator should reject an undiscoverable bundled script" >&2
    return 1
  fi
  grep -Fq \
    'bundled script is not discoverable from owning Markdown: scripts/orphaned.rb' \
    "${stderr_file}"
  printf '%s\n' \
    '# codex-workflows: internal-skill-script: invoked only by the public helper' \
    >"${scripts}/orphaned.rb"
  ruby "${script}" "${fixture}" >/dev/null

  mv "${agents}" "${agents}.missing"
  if ruby "${script}" "${fixture}" >/dev/null 2>&1; then
    echo "skill metadata validator should require agents/openai.yaml" >&2
    return 1
  fi
}

run_markdown_reference_smoke() {
  local script="${repo_dir}/scripts/validate-markdown-references.rb"
  local fixture="${tmp_root}/markdown-references"
  local stderr_file="${tmp_root}/markdown-references.stderr"
  local command_status

  mkdir -p "${fixture}/docs" "${fixture}/skills/example"
  cat >"${fixture}/README.md" <<'EOF_MARKDOWN_README'
# Root Heading

[Same-file heading](#root-heading)
[Cross-file heading](docs/target.md#target-heading)
EOF_MARKDOWN_README
  printf '%s\n' '# Repository Instructions' >"${fixture}/AGENTS.md"
  printf '%s\n' '# Target Heading' >"${fixture}/docs/target.md"
  printf '%s\n' '# Example Skill' >"${fixture}/skills/example/SKILL.md"

  "${script}" --help >/dev/null
  assert_usage_error \
    "markdown-reference-unknown-option" \
    "unknown option: --bogus" \
    "${script}" --bogus
  "${script}" "${fixture}"

  printf '%s\n' '[Broken fragment](target.md#missing-heading)' \
    >"${fixture}/docs/broken.md"
  if "${script}" "${fixture}" >/dev/null 2>"${stderr_file}"; then
    echo "validate-markdown-references.rb should reject a missing fragment" >&2
    return 1
  else
    command_status=$?
  fi
  [[ "${command_status}" -eq 1 ]]
  grep -Fq \
    'docs/broken.md: markdown link fragment not found: target.md#missing-heading' \
    "${stderr_file}"
}

run_ci_tool_parity_smoke() {
  local fixture="${tmp_root}/ci-tool-parity"
  local script="${fixture}/scripts/check-ci-tool-parity.sh"
  local system_bin="${fixture}/system-bin"
  local stale_venv_bin="${fixture}/.venv/bin"
  local output="${fixture}/output"

  mkdir -p "${fixture}/scripts" "${fixture}/.github/workflows" "${system_bin}" "${stale_venv_bin}"
  cp "${repo_dir}/scripts/check-ci-tool-parity.sh" "${script}"
  cat >"${fixture}/.github/workflows/validate.yml" <<'EOF_PARITY_WORKFLOW'
env:
  ACTIONLINT_VERSION: v1.7.12
EOF_PARITY_WORKFLOW
  cat >"${fixture}/.github/requirements.txt" <<'EOF_PARITY_REQUIREMENTS'
zizmor==1.29.0
EOF_PARITY_REQUIREMENTS
  cat >"${system_bin}/actionlint" <<'EOF_PARITY_ACTIONLINT'
#!/usr/bin/env bash
echo "1.7.12"
EOF_PARITY_ACTIONLINT
  cat >"${system_bin}/zizmor" <<'EOF_PARITY_ZIZMOR'
#!/usr/bin/env bash
echo "zizmor 1.29.0"
EOF_PARITY_ZIZMOR
  cat >"${stale_venv_bin}/actionlint" <<'EOF_PARITY_STALE_ACTIONLINT'
#!/usr/bin/env bash
echo "0.0.0"
EOF_PARITY_STALE_ACTIONLINT
  cat >"${stale_venv_bin}/zizmor" <<'EOF_PARITY_STALE_ZIZMOR'
#!/usr/bin/env bash
echo "zizmor 0.0.0"
EOF_PARITY_STALE_ZIZMOR
  chmod +x "${script}" "${system_bin}/actionlint" "${system_bin}/zizmor" \
    "${stale_venv_bin}/actionlint" "${stale_venv_bin}/zizmor"

  PATH="${system_bin}:/usr/bin:/bin" "${script}" --strict >"${output}"
  grep -Fq "actionlint 1.7.12 matches CI (${system_bin}/actionlint)" "${output}"
  grep -Fq "zizmor 1.29.0 matches CI (${system_bin}/zizmor)" "${output}"
}

run_retro_state_smoke() {
  local script="${repo_dir}/skills/skill-retro/scripts/retro-state.rb"
  local smoke_dir="${tmp_root}/retro-state"
  local state_root="${smoke_dir}/state"
  local candidate="${smoke_dir}/candidate.md"
  local fallback="${smoke_dir}/fallback.md"
  local papercut="${smoke_dir}/papercut.md"
  local papercut_fallback="${smoke_dir}/papercut-fallback.md"
  local verification="${smoke_dir}/verification.md"
  local verification_fallback="${smoke_dir}/verification-fallback.md"
  local verification_text
  local audit="${smoke_dir}/audit.md"
  local candidate_path
  local papercut_path
  local papercut_id
  local audit_path
  local guard_stdout="${smoke_dir}/guard.stdout"
  local guard_stderr="${smoke_dir}/guard.stderr"
  local system_ruby_version

  require_command ruby
  mkdir -p "${smoke_dir}"
  "${script}" --help >/dev/null
  assert_usage_error \
    "retro-state-invalid-option" \
    "retro-state.rb: invalid option: --bogus" \
    "${script}" init --bogus
  assert_usage_error \
    "retro-state-extra-argument" \
    "retro-state.rb: invalid argument: unexpected argument: extra" \
    "${script}" init extra
  assert_usage_error \
    "retro-state-unknown-command" \
    "retro-state.rb: unknown command: unknown" \
    "${script}" unknown
  assert_usage_error \
    "retro-state-inapplicable-option" \
    "retro-state.rb: invalid option: --file is not valid for validate" \
    "${script}" validate --file ignored
  assert_usage_error \
    "retro-state-inapplicable-threshold" \
    "retro-state.rb: invalid option: --archive-threshold is not valid for validate" \
    "${script}" validate --archive-threshold 10
  "${script}" template candidate >"${candidate}"
  "${script}" template papercut >"${papercut}"
  "${script}" template papercut-repair | rg -q 'record_type: papercut-repair'
  verification_text="$("${script}" template verification)"
  printf '%s\n' "${verification_text//SCR-YYYYMMDD-abcdef/SCR-20260715-abcdef}" >"${verification}"
  "${script}" template verification-decision | rg -q 'record_type: verification-decision'
  "${script}" template audit >"${audit}"

  if (
    unset CODEX_WORKFLOWS_STATE_DIR
    "${script}" route --file "${candidate}" >"${fallback}" 2>/dev/null
  ); then
    echo "retro-state route should report fallback when the state root is unset" >&2
    return 1
  else
    local fallback_status=$?
    if [[ "${fallback_status}" -ne 2 ]]; then
      echo "retro-state unset-root fallback should exit 2, got ${fallback_status}" >&2
      return 1
    fi
  fi
  [[ -s "${fallback}" ]]
  rg -q 'record_type: candidate' "${fallback}"
  rg -q 'Short candidate title' "${fallback}"

  if (
    unset CODEX_WORKFLOWS_STATE_DIR
    "${script}" route-verification --file "${verification}" >"${verification_fallback}" 2>/dev/null
  ); then
    echo "retro-state route-verification should report fallback when the state root is unset" >&2
    return 1
  else
    local verification_fallback_status=$?
    if [[ "${verification_fallback_status}" -ne 2 ]]; then
      echo "retro-state verification fallback should exit 2, got ${verification_fallback_status}" >&2
      return 1
    fi
  fi
  rg -q 'record_type: verification-proposal' "${verification_fallback}"

  if (
    unset CODEX_WORKFLOWS_STATE_DIR
    "${script}" record-papercut --file - <"${papercut}" >"${papercut_fallback}" 2>/dev/null
  ); then
    echo "retro-state record-papercut should report fallback when the state root is unset" >&2
    return 1
  else
    local papercut_fallback_status=$?
    if [[ "${papercut_fallback_status}" -ne 2 ]]; then
      echo "retro-state papercut fallback should exit 2, got ${papercut_fallback_status}" >&2
      return 1
    fi
  fi
  rg -q 'record_type: papercut' "${papercut_fallback}"

  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" init >/dev/null
  candidate_path="$(CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" route --file "${candidate}")"
  [[ -s "${candidate_path}" ]]
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" pending | rg -q 'Atomic routing|Short candidate title'
  papercut_path="$(CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" record-papercut --file "${papercut}")"
  [[ -s "${papercut_path}" ]]
  papercut_id="$(basename "${papercut_path}" .md)"
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" papercuts | rg -q "${papercut_id}"
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" close-papercut \
    --id "${papercut_id}" --outcome no-action --rationale "Pilot smoke test." >/dev/null
  if CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" papercuts | rg -q "${papercut_id}"; then
    echo "closed papercut should not remain in the default listing" >&2
    return 1
  fi
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" papercuts --archive | rg -q "${papercut_id}"
  audit_path="$(CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" record-audit --file "${audit}")"
  [[ -s "${audit_path}" ]]
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" audits | rg -q "$(basename "${audit_path}" .md)"
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" artifact-audit-status \
    --archive-threshold 1 | rg -q '^not-due'
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" verification-opportunities \
    --destination skill-retro >/dev/null
  CODEX_WORKFLOWS_STATE_DIR="${state_root}" "${script}" validate >/dev/null
  "${script}" self-test >/dev/null

  mkdir -p "${smoke_dir}/conflicting-ruby"
  printf '%s\n' '0.0.0-unavailable' >"${smoke_dir}/conflicting-ruby/.ruby-version"
  (cd "${smoke_dir}/conflicting-ruby" && "${script}" --help >/dev/null)

  if [[ -x /usr/bin/ruby ]]; then
    system_ruby_version="$(/usr/bin/ruby -e 'print RUBY_VERSION')"
    if [[ "${system_ruby_version}" != "3.3.12" ]]; then
      if /usr/bin/ruby "${script}" --help >"${guard_stdout}" 2>"${guard_stderr}"; then
        echo "retro-state.rb should reject explicit Ruby ${system_ruby_version}" >&2
        return 1
      fi
      [[ ! -s "${guard_stdout}" ]]
      grep -Fq "CRuby 3.3.12 is required; detected" "${guard_stderr}"
      grep -Fq "resolved interpreter:" "${guard_stderr}"
    fi
  fi

  mkdir -p "${smoke_dir}/git-root/.git"
  printf '%s\n' 'ref: refs/heads/main' >"${smoke_dir}/git-root/.git/HEAD"
  if CODEX_WORKFLOWS_STATE_DIR="${smoke_dir}/git-root/state" "${script}" init >/dev/null 2>&1; then
    echo "retro-state should refuse a state root inside a Git worktree" >&2
    return 1
  fi
}

run_patch_identity_smoke() {
  local script="${repo_dir}/skills/planning-workflow/scripts/patch-identity.rb"
  local smoke_dir="${tmp_root}/patch-identity"
  local stdout_file="${smoke_dir}/stdout"
  local stderr_file="${smoke_dir}/stderr"
  local first_digest
  local second_digest
  local changed_digest
  local command_status
  local newline_name=$'line\nbreak.txt'
  local system_ruby_version

  require_command git
  require_command ruby
  mkdir -p "${smoke_dir}/repo"
  git -C "${smoke_dir}/repo" init -q
  git -C "${smoke_dir}/repo" config user.email smoke@example.invalid
  git -C "${smoke_dir}/repo" config user.name "Smoke Test"
  printf '%s\n' baseline >"${smoke_dir}/repo/tracked.txt"
  git -C "${smoke_dir}/repo" add tracked.txt
  git -C "${smoke_dir}/repo" commit -q -m baseline
  printf '%s\n' modified >"${smoke_dir}/repo/tracked.txt"
  printf '%s\n' new >"${smoke_dir}/repo/new-test.R"
  printf '%s\n' newline >"${smoke_dir}/repo/${newline_name}"
  printf '%s\n' unrelated >"${smoke_dir}/repo/unrelated.md"

  assert_usage_error \
    "patch-identity-extra-argument" \
    "patch-identity.rb: invalid argument: unexpected argument: extra" \
    "${script}" extra

  mkdir -p "${smoke_dir}/conflicting-ruby"
  printf '%s\n' '0.0.0-unavailable' >"${smoke_dir}/conflicting-ruby/.ruby-version"
  (cd "${smoke_dir}/conflicting-ruby" && "${script}" --help >/dev/null)

  if (
    cd "${smoke_dir}/repo" && "${script}" \
      --include-untracked new-test.R \
      --include-untracked new-test.R \
      >"${stdout_file}" 2>"${stderr_file}"
  ); then
    echo "patch-identity.rb should reject duplicate included paths" >&2
    return 1
  else
    command_status=$?
  fi
  [[ "${command_status}" -eq 1 ]]
  [[ ! -s "${stdout_file}" ]]
  grep -Fq 'duplicate included path: "new-test.R"' "${stderr_file}"

  if [[ -x /usr/bin/ruby ]]; then
    system_ruby_version="$(/usr/bin/ruby -e 'print RUBY_VERSION')"
    if [[ "${system_ruby_version}" != "3.3.12" ]]; then
      if /usr/bin/ruby "${script}" --help >"${stdout_file}" 2>"${stderr_file}"; then
        echo "patch-identity.rb should reject explicit Ruby ${system_ruby_version}" >&2
        return 1
      fi
      [[ ! -s "${stdout_file}" ]]
      grep -Fq "CRuby 3.3.12 is required; detected" "${stderr_file}"
      grep -Fq "resolved interpreter:" "${stderr_file}"
    fi
  fi

  if (cd "${smoke_dir}/repo" && "${script}" >"${stdout_file}" 2>"${stderr_file}"); then
    echo "patch-identity.rb should reject uncategorized untracked files" >&2
    return 1
  else
    command_status=$?
  fi
  [[ "${command_status}" -eq 1 ]]
  [[ ! -s "${stdout_file}" ]]
  grep -Fq "uncategorized untracked path" "${stderr_file}"

  first_digest="$({
    cd "${smoke_dir}/repo" && "${script}" \
      --include-untracked new-test.R \
      --include-untracked "${newline_name}" \
      --exclude-untracked unrelated.md
  } 2>"${stderr_file}")"
  [[ "${first_digest}" =~ ^[0-9a-f]{64}$ ]]
  grep -Fq "baseline:" "${stderr_file}"
  grep -Fq 'included untracked: "new-test.R"' "${stderr_file}"
  grep -Fq 'excluded untracked: "unrelated.md"' "${stderr_file}"
  second_digest="$({
    cd "${smoke_dir}/repo" && "${script}" \
      --include-untracked new-test.R \
      --include-untracked "${newline_name}" \
      --exclude-untracked unrelated.md
  } 2>/dev/null)"
  [[ "${second_digest}" == "${first_digest}" ]]

  printf '%s\n' changed >"${smoke_dir}/repo/new-test.R"
  changed_digest="$({
    cd "${smoke_dir}/repo" && "${script}" \
      --include-untracked new-test.R \
      --include-untracked "${newline_name}" \
      --exclude-untracked unrelated.md
  } 2>/dev/null)"
  [[ "${changed_digest}" =~ ^[0-9a-f]{64}$ ]]
  [[ "${changed_digest}" != "${first_digest}" ]]

  git -C "${smoke_dir}/repo" add tracked.txt
  if (
    cd "${smoke_dir}/repo" && "${script}" \
      --include-untracked new-test.R \
      --include-untracked "${newline_name}" \
      --exclude-untracked unrelated.md \
      >"${stdout_file}" 2>"${stderr_file}"
  ); then
    echo "patch-identity.rb should reject a non-clean index" >&2
    return 1
  else
    command_status=$?
  fi
  [[ "${command_status}" -eq 1 ]]
  [[ ! -s "${stdout_file}" ]]
  grep -Fq "the index is not clean" "${stderr_file}"
}

run_notebook_smoke
run_benchmark_smoke
run_architecture_audit_smoke
run_manifest_smoke
run_roxygen_smoke
run_document_validation_smoke
run_shell_script_smoke
run_long_process_observer_smoke
run_r_package_check_smoke
run_audit_actions_smoke
run_action_tag_comment_smoke
run_skill_index_smoke
run_skill_metadata_smoke
run_markdown_reference_smoke
run_ci_tool_parity_smoke
run_retro_state_smoke
run_patch_identity_smoke

echo "Skill script smoke tests passed."
