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

Audit GitHub Actions workflows and sibling dependabot.yml/.yaml files, including
repositories with Dependabot but no workflows. Use --quiet to suppress progress and successful
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
  local target_label="$*"
  local output
  local version_output
  local zizmor_args=(--no-progress)
  local uvx_args=(--no-progress zizmor --no-progress)

  if [[ "${quiet}" == true ]]; then
    zizmor_args=(-qq --no-progress)
    uvx_args=(--quiet --quiet --no-progress zizmor -qq --no-progress)
  fi

  zizmor_args+=("--collect=workflows,dependabot" --strict-collection)
  uvx_args+=("--collect=workflows,dependabot" --strict-collection)

  if command -v zizmor >/dev/null 2>&1; then
    if [[ "${quiet}" == true ]]; then
      output="$(mktemp)"
      if zizmor "${zizmor_args[@]}" "$@" >"${output}" 2>&1; then
        rm -f "${output}"
        return 0
      fi
      cat "${output}" >&2
      rm -f "${output}"
      echo "zizmor reported issues for ${target_label}." >&2
      return 1
    fi
    if ! zizmor "${zizmor_args[@]}" "$@"; then
      echo "zizmor reported issues for ${target_label}." >&2
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
  if uvx "${uvx_args[@]}" "$@" >"${output}" 2>&1; then
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
    echo "zizmor reported issues for ${target_label}." >&2
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

# Preserve NUL-delimited discovery output and check each producer before use.
audit_tmp="$(mktemp -d "${TMPDIR:-/tmp}/actions-audit.XXXXXX")"
trap 'rm -rf "${audit_tmp}"' EXIT
status=0
workflow_files=()
zizmor_targets=()

if [[ -d "${workflow_dir}" ]]; then
  if ! find "${workflow_dir}" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 >"${audit_tmp}/files"; then
    echo "audit-actions.sh: workflow discovery failed for ${workflow_dir}" >&2
    exit 1
  fi
  while IFS= read -r -d '' file; do
    workflow_files+=("${file}")
  done <"${audit_tmp}/files"
  if ((${#workflow_files[@]} > 0)); then
    zizmor_targets+=("${workflow_dir}")
  fi
elif [[ -e "${workflow_dir}" || -L "${workflow_dir}" ]]; then
  echo "audit-actions.sh: expected a workflow directory: ${workflow_dir}" >&2
  exit 2
fi

config_dir="$(dirname "${workflow_dir%/}")"
for config in "${config_dir}/dependabot.yml" "${config_dir}/dependabot.yaml"; do
  if [[ -e "${config}" || -L "${config}" ]]; then
    if [[ ! -f "${config}" || ! -r "${config}" ]]; then
      echo "audit-actions.sh: unreadable Dependabot file: ${config}" >&2
      exit 2
    fi
    zizmor_targets+=("${config}")
  fi
done

checked_grep() {
  local pattern="$1"
  local destination="$2"
  local grep_status
  if grep -HnE "${pattern}" "${workflow_files[@]}" >"${destination}"; then
    return 0
  else
    grep_status=$?
  fi
  if [[ "${grep_status}" -eq 1 ]]; then
    return 0
  fi
  echo "audit-actions.sh: grep failed while scanning workflows (status ${grep_status})" >&2
  return 1
}

if ((${#workflow_files[@]} > 0)); then
  progress "Checking for unpinned action refs..."
  found_unpinned=false
  if checked_grep '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^#]+@[^[:space:]#]+' "${audit_tmp}/refs"; then
    while IFS= read -r match; do
      ref="$(printf '%s\n' "${match}" | sed -E 's/.*uses:[[:space:]]*[^#]+@([^[:space:]#]+).*/\1/')"
      if [[ ! "${ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
        printf '%s\n' "${match}"
        found_unpinned=true
        status=1
      fi
    done <"${audit_tmp}/refs"
    if [[ "${found_unpinned}" == false && "${quiet}" == false ]]; then
      echo "No non-SHA action refs found."
    fi
  else
    status=1
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
  if checked_grep '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*actions/checkout@' "${audit_tmp}/checkouts"; then
    while IFS= read -r match; do
      file="${match%%:*}"
      rest="${match#*:}"
      line_no="${rest%%:*}"
      if ! sed -n "${line_no},$((line_no + 12))p" "${file}" >"${audit_tmp}/context"; then
        echo "audit-actions.sh: could not read checkout context in ${file}" >&2
        status=1
        continue
      fi
      if ! grep -q 'persist-credentials:[[:space:]]*false' "${audit_tmp}/context"; then
        echo "${file}:${line_no}: checkout step may be missing persist-credentials: false" >&2
        status=1
      fi
    done <"${audit_tmp}/checkouts"
  else
    status=1
  fi

  if command -v actionlint >/dev/null 2>&1; then
    if ! actionlint "${workflow_files[@]}"; then
      status=1
    fi
  else
    echo "actionlint not found; skipped syntax check." >&2
    if [[ "${CI:-false}" == "true" ]]; then
      echo "actionlint is required in CI." >&2
      status=1
    fi
  fi
fi

if ((${#zizmor_targets[@]} > 0)); then
  if ! run_zizmor "${zizmor_targets[@]}"; then
    status=1
  fi
else
  if [[ ! -d "${workflow_dir}" && "${target_explicit}" == true && "${workflow_dir%/}" != ".github/workflows" ]]; then
    echo "audit-actions.sh: no workflow directory at ${workflow_dir}" >&2
    exit 2
  fi
  echo "audit-actions.sh: no workflow YAML or Dependabot configuration found" >&2
  exit 0
fi

if [[ "${status}" -eq 0 && "${quiet}" == true ]]; then
  echo "GitHub Actions audit completed."
fi

exit "${status}"
