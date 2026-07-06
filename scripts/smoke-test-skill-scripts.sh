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

run_audit_actions_smoke() {
  local script="${repo_dir}/skills/github-actions-hardening/scripts/audit-actions.sh"
  local workflow_dir="${tmp_root}/audit-actions-commented-only"
  local fake_bin="${tmp_root}/audit-actions-fake-bin"

  mkdir -p "${workflow_dir}" "${fake_bin}"
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
  ruby "${repo_dir}/scripts/list-skills.rb" >/dev/null
  ruby "${repo_dir}/scripts/list-skills.rb" --markdown >/dev/null
}

run_notebook_smoke
run_benchmark_smoke
run_manifest_smoke
run_roxygen_smoke
run_shell_script_smoke
run_audit_actions_smoke
run_action_tag_comment_smoke
run_skill_index_smoke

echo "Skill script smoke tests passed."
