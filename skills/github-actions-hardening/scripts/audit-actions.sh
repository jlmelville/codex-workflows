#!/usr/bin/env bash
set -euo pipefail

workflow_dir=".github/workflows"
target_explicit=false
quiet=false
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-${TMPDIR:-/tmp}/uv-cache}"
export UV_TOOL_DIR="${UV_TOOL_DIR:-${TMPDIR:-/tmp}/uv-tools}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-${TMPDIR:-/tmp}/uv-python}"

usage() {
  cat <<'USAGE'
Usage: audit-actions.sh [--quiet] [WORKFLOW_DIR]

Audit GitHub Actions workflows. Use --quiet to suppress progress and successful
per-action detail while preserving findings and operational diagnostics.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --quiet)
      quiet=true
      shift
      ;;
    -*)
      echo "audit-actions.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "${target_explicit}" == true ]]; then
        echo "audit-actions.sh: unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      workflow_dir="$1"
      target_explicit=true
      shift
      ;;
  esac
done

progress() {
  if [[ "${quiet}" == false ]]; then
    echo "$*"
  fi
  return 0
}

run_zizmor() {
  local target_dir="$1"
  local output
  local version_output
  local zizmor_args=(--no-progress)
  local uvx_args=(--no-progress zizmor --no-progress)

  if [[ "${quiet}" == true ]]; then
    zizmor_args=(-qq --no-progress)
    uvx_args=(--quiet --quiet --no-progress zizmor -qq --no-progress)
  fi

  if command -v zizmor >/dev/null 2>&1; then
    if [[ "${quiet}" == true ]]; then
      output="$(mktemp)"
      if zizmor "${zizmor_args[@]}" "${target_dir}" >"${output}" 2>&1; then
        rm -f "${output}"
        return 0
      fi
      cat "${output}" >&2
      rm -f "${output}"
      echo "zizmor reported issues for ${target_dir}." >&2
      return 1
    fi
    if ! zizmor "${zizmor_args[@]}" "${target_dir}"; then
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
  if uvx "${uvx_args[@]}" "${target_dir}" >"${output}" 2>&1; then
    if [[ "${quiet}" == false ]]; then
      cat "${output}"
    fi
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

  version_output="$(mktemp)"
  if [[ -s "${output}" ]] &&
    uvx --quiet --quiet --no-progress zizmor --version >"${version_output}" 2>&1; then
    rm -f "${output}" "${version_output}"
    echo "zizmor reported issues for ${target_dir}." >&2
    return 1
  fi

  if [[ -s "${version_output}" ]]; then
    cat "${version_output}" >&2
  fi
  rm -f "${output}" "${version_output}"
  echo "uvx could not execute zizmor; use installed zizmor or retry with fresh writable UV_CACHE_DIR, UV_TOOL_DIR, and UV_PYTHON_INSTALL_DIR." >&2
  if [[ "${CI:-false}" == "true" ]]; then
    echo "zizmor execution is required to succeed in CI." >&2
    return 1
  fi
  return 0
}

if [[ ! -d "${workflow_dir}" ]]; then
  echo "audit-actions.sh: no workflow directory at ${workflow_dir}" >&2
  exit 0
fi

status=0

progress "Checking for unpinned action refs..."
found_unpinned=false
while IFS= read -r match; do
  ref="$(printf '%s\n' "${match}" | sed -E 's/.*uses:[[:space:]]*[^#]+@([^[:space:]#]+).*/\1/')"
  if [[ ! "${ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' "${match}"
    found_unpinned=true
    status=1
  fi
done < <(grep -RInE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^#]+@[^[:space:]#]+' "${workflow_dir}" || true)

if [[ "${found_unpinned}" == false && "${quiet}" == false ]]; then
  echo "No non-SHA action refs found."
fi

progress "Checking nearby action pin comments..."
action_comment_checker="${script_dir}/check-action-tag-comments.sh"
if [[ ! -x "${action_comment_checker}" ]]; then
  action_comment_checker="${script_dir}/../../github-actions-hardening/scripts/check-action-tag-comments.sh"
fi

if [[ -x "${action_comment_checker}" ]]; then
  comment_args=(--require-comment)
  if [[ "${quiet}" == true ]]; then
    comment_args+=(--quiet)
  fi
  if ! "${action_comment_checker}" "${comment_args[@]}" "${workflow_dir}"; then
    status=1
  fi
else
  echo "check-action-tag-comments.sh not found; skipped action pin comment check." >&2
fi

progress "Checking checkout credential persistence..."
while IFS= read -r match; do
  file="${match%%:*}"
  rest="${match#*:}"
  line_no="${rest%%:*}"
  context="$(sed -n "${line_no},$((line_no + 12))p" "${file}")"
  if ! printf '%s\n' "${context}" | grep -q 'persist-credentials:[[:space:]]*false'; then
    echo "${file}:${line_no}: checkout step may be missing persist-credentials: false" >&2
    status=1
  fi
done < <(grep -RInE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*actions/checkout@' "${workflow_dir}" || true)

if command -v actionlint >/dev/null 2>&1; then
  workflow_files=()
  while IFS= read -r -d '' file; do
    workflow_files+=("${file}")
  done < <(
    find "${workflow_dir}" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0
  )
  if ((${#workflow_files[@]} > 0)); then
    if ! actionlint "${workflow_files[@]}"; then
      status=1
    fi
  elif [[ "${quiet}" == false ]]; then
    echo "No workflow YAML files found for actionlint."
  fi
else
  echo "actionlint not found; skipped syntax check." >&2
  if [[ "${CI:-false}" == "true" ]]; then
    echo "actionlint is required in CI." >&2
    status=1
  fi
fi

if ! run_zizmor "${workflow_dir}"; then
  status=1
fi

if [[ "${status}" -eq 0 && "${quiet}" == true ]]; then
  echo "GitHub Actions audit completed."
fi

exit "${status}"
