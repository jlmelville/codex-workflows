#!/usr/bin/env bash
set -euo pipefail

workflow_dir="${1:-.github/workflows}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-${TMPDIR:-/tmp}/uv-cache}"
export UV_TOOL_DIR="${UV_TOOL_DIR:-${TMPDIR:-/tmp}/uv-tools}"

if [[ ! -d "${workflow_dir}" ]]; then
  echo "audit-actions.sh: no workflow directory at ${workflow_dir}" >&2
  exit 0
fi

status=0

echo "Checking for unpinned action refs..."
found_unpinned=false
while IFS= read -r match; do
  ref="$(printf '%s\n' "${match}" | sed -E 's/.*uses:[[:space:]]*[^#]+@([^[:space:]#]+).*/\1/')"
  if [[ ! "${ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' "${match}"
    found_unpinned=true
    status=1
  fi
done < <(grep -RInE 'uses:[[:space:]]*[^#]+@[^[:space:]#]+' "${workflow_dir}" || true)

if [[ "${found_unpinned}" == false ]]; then
  echo "No non-SHA action refs found."
fi

echo "Checking checkout credential persistence..."
while IFS= read -r match; do
  file="${match%%:*}"
  rest="${match#*:}"
  line_no="${rest%%:*}"
  context="$(sed -n "${line_no},$((line_no + 12))p" "${file}")"
  if ! printf '%s\n' "${context}" | grep -q 'persist-credentials:[[:space:]]*false'; then
    echo "${file}:${line_no}: checkout step may be missing persist-credentials: false" >&2
    status=1
  fi
done < <(grep -RInE 'uses:[[:space:]]*actions/checkout@' "${workflow_dir}" || true)

if command -v actionlint >/dev/null 2>&1; then
  actionlint
else
  echo "actionlint not found; skipped syntax check." >&2
fi

if command -v uvx >/dev/null 2>&1; then
  if ! uvx zizmor "${workflow_dir}"; then
    echo "zizmor reported issues for ${workflow_dir}." >&2
    status=1
  fi
else
  echo "uvx not found; skipped zizmor." >&2
fi

exit "${status}"
