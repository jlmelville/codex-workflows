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
  if ! grep -Fq "${expected}" "${stderr_file}" || ! grep -Fq "Usage:" "${stderr_file}"; then
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
  base = function() {
    Sys.sleep(0.01)
    sum(1:3)
  }
)
RS

  Rscript --vanilla "${script}" --help >/dev/null
  Rscript --vanilla "${script}" "${cases}" --reps 1 --out "${out_prefix}" >/dev/null
  if Rscript --vanilla "${script}" "${cases}" --baseline missing --out "${out_prefix}-missing" >/dev/null 2>&1; then
    echo "benchmark-evidence.R should fail for an unknown baseline" >&2
    return 1
  fi
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

run_shell_script_smoke() {
  "${repo_dir}/skills/r-package-workflow/scripts/check-r-package.sh" --help >/dev/null
  "${repo_dir}/skills/r-package-workflow/scripts/audit-generated-r-files.sh" >/dev/null
  "${repo_dir}/skills/github-actions-hardening/scripts/check-action-tag-comments.sh" --help >/dev/null
}

run_r_package_check_smoke() {
  local script="${repo_dir}/skills/r-package-workflow/scripts/check-r-package.sh"
  local pkg_dir="${tmp_root}/r-package-check"
  local empty_dir="${tmp_root}/r-package-check-empty"
  local fake_bin="${tmp_root}/r-package-check-bin"
  local log="${tmp_root}/r-package-check.log"

  mkdir -p "${pkg_dir}/R" "${pkg_dir}/.github/workflows" "${empty_dir}" "${fake_bin}"
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

  : >"${log}"
  (
    cd "${pkg_dir}"
    PATH="${fake_bin}:${PATH}" SMOKE_LOG="${log}" "${script}" full >/dev/null
  )
  [[ "$(wc -l <"${log}")" -eq 5 ]]
  grep -Fq 'air format . --check' "${log}"
  grep -Fq 'lintr::lint_package()' "${log}"
  grep -Fq 'devtools::check(document = FALSE' "${log}"

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

  ruby "${repo_dir}/scripts/list-skills.rb" >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" --markdown >/dev/null
  assert_usage_error \
    "list-skills-invalid-option" \
    "list-skills.rb: invalid option: --bogus" \
    ruby "${repo_dir}/scripts/list-skills.rb" --bogus
  assert_usage_error \
    "list-skills-extra-argument" \
    "list-skills.rb: unexpected argument: extra" \
    ruby "${repo_dir}/scripts/list-skills.rb" extra

  mkdir -p "${fixture}/scripts" "${fixture}/skills/example/agents"
  cp "${repo_dir}/scripts/list-skills.rb" "${fixture_script}"
  cat >"${fixture}/skills/example/SKILL.md" <<'EOF_SKILL_INDEX'
---
name: example
description: Exercise skill index metadata errors.
---

# Example
EOF_SKILL_INDEX
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

  mkdir -p "${fixture}/skills/example/agents"
  cat >"${fixture}/skills/example/SKILL.md" <<'EOF_SKILL'
---
name: example
description: Validate metadata fixture behavior.
---

# Example
EOF_SKILL
  cat >"${agents}" <<'EOF_AGENTS'
interface:
  display_name: "Example"
  short_description: "Validate a metadata fixture"
  default_prompt: "Use $example to exercise metadata validation."
EOF_AGENTS

  ruby "${script}" "${fixture}" >/dev/null
  mv "${agents}" "${agents}.missing"
  if ruby "${script}" "${fixture}" >/dev/null 2>&1; then
    echo "skill metadata validator should require agents/openai.yaml" >&2
    return 1
  fi
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
  local audit="${smoke_dir}/audit.md"
  local candidate_path
  local papercut_path
  local papercut_id
  local audit_path

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
  if [[ -x /usr/bin/ruby ]]; then
    /usr/bin/ruby "${script}" self-test >/dev/null
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

  for ruby_command in "$(command -v ruby)" /usr/bin/ruby; do
    [[ -x "${ruby_command}" ]] || continue
    if (
      cd "${smoke_dir}/repo" && "${ruby_command}" "${script}" \
        --include-untracked new-test.R \
        --include-untracked new-test.R \
        >"${stdout_file}" 2>"${stderr_file}"
    ); then
      echo "patch-identity.rb should reject duplicate included paths under ${ruby_command}" >&2
      return 1
    else
      command_status=$?
    fi
    [[ "${command_status}" -eq 1 ]]
    [[ ! -s "${stdout_file}" ]]
    grep -Fq 'duplicate included path: "new-test.R"' "${stderr_file}"
  done

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
run_manifest_smoke
run_roxygen_smoke
run_shell_script_smoke
run_r_package_check_smoke
run_audit_actions_smoke
run_action_tag_comment_smoke
run_skill_index_smoke
run_skill_metadata_smoke
run_ci_tool_parity_smoke
run_retro_state_smoke
run_patch_identity_smoke

echo "Skill script smoke tests passed."
