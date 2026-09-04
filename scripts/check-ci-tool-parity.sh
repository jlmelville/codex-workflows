#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_file="${repo_dir}/.github/workflows/validate.yml"
requirements_file="${repo_dir}/.github/requirements.txt"
strict=false
quiet=false
status=0

if [[ "${CI:-false}" == "true" ]]; then
  strict=true
fi

usage() {
  echo "Usage: $0 [--strict|--advisory] [--quiet]" >&2
}

while (($# > 0)); do
  case "$1" in
    --strict) strict=true ;;
    --advisory) strict=false ;;
    --quiet) quiet=true ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

expected_actionlint="$(
  sed -nE 's/^[[:space:]]*ACTIONLINT_VERSION:[[:space:]]*v?([^[:space:]#]+).*$/\1/p' "${workflow_file}" |
    head -n 1
)"

requirement_version() {
  local package="$1"

  sed -n "s/^${package}==\([^[:space:]#]*\).*$/\1/p" "${requirements_file}" |
    head -n 1
}

expected_zizmor="$(requirement_version zizmor)"

for expected in "${expected_actionlint}" "${expected_zizmor}"; do
  if [[ -z "${expected}" ]]; then
    echo "CI tool parity: could not read every expected version from repository pins." >&2
    exit 1
  fi
done

tool_version() {
  local tool="$1"
  local version=""

  if ! command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi

  case "${tool}" in
    actionlint)
      version="$(actionlint -version 2>/dev/null | sed -n '1{s/[[:space:]].*$//;p;}' || true)"
      ;;
    zizmor)
      version="$(zizmor --version 2>/dev/null | sed -n '1{s/^[^[:space:]]*[[:space:]]*//;s/[[:space:]].*$//;p;}' || true)"
      ;;
  esac

  printf '%s\n' "${version#v}"
}

check_tool() {
  local tool="$1"
  local expected="$2"
  local actual
  local resolved_tool

  resolved_tool="$(command -v "${tool}" 2>/dev/null || true)"
  actual="$(tool_version "${tool}")"
  if [[ -z "${actual}" ]]; then
    echo "CI tool parity: ${tool} is unavailable; CI expects ${expected}." >&2
    status=1
  elif [[ "${actual}" != "${expected#v}" ]]; then
    echo "CI tool parity: ${tool} ${actual} is installed at ${resolved_tool}; CI expects ${expected#v}." >&2
    status=1
  elif [[ "${quiet}" == false ]]; then
    echo "CI tool parity: ${tool} ${actual} matches CI (${resolved_tool})."
  fi
}

check_tool actionlint "${expected_actionlint}"
check_tool zizmor "${expected_zizmor}"

if [[ "${status}" -ne 0 && "${strict}" == false ]]; then
  echo "CI tool parity: advisory mismatch; rerun with --strict before claiming CI-equivalent validation." >&2
  exit 0
fi

exit "${status}"
