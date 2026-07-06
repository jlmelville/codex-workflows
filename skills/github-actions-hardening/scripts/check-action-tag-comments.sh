#!/usr/bin/env bash
set -euo pipefail

workflow_dir=".github/workflows"
verify_remote=false

usage() {
  cat <<'USAGE'
Usage: check-action-tag-comments.sh [--verify-remote] [WORKFLOW_DIR]

Check SHA-pinned GitHub Actions uses: entries for nearby version/tag comments.

By default this is an offline parse check. With --verify-remote, each detected
tag such as v4 or v4.1.2 is resolved with git ls-remote over public HTTPS and
compared to the pinned SHA.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --verify-remote)
      verify_remote=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      workflow_dir="$1"
      shift
      ;;
  esac
done

if [[ ! -d "${workflow_dir}" ]]; then
  echo "check-action-tag-comments.sh: no workflow directory at ${workflow_dir}" >&2
  exit 0
fi

if [[ "${verify_remote}" == true ]] && ! command -v git >/dev/null 2>&1; then
  echo "git is required for --verify-remote" >&2
  exit 2
fi

extract_tag() {
  local comment="$1"
  local tag

  if [[ "${comment}" =~ (^|[^[:alnum:]_.-])(v[0-9][[:alnum:]_.-]*) ]]; then
    tag="${BASH_REMATCH[2]}"
    while [[ "${tag: -1}" == "." || "${tag: -1}" == "," || "${tag: -1}" == ":" || "${tag: -1}" == ";" ]]; do
      tag="${tag%?}"
    done
    printf '%s\n' "${tag}"
  fi
}

resolve_tag_sha() {
  local action="$1"
  local tag="$2"
  local output

  output="$(
    GIT_CONFIG_GLOBAL=/dev/null \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_TERMINAL_PROMPT=0 \
      git ls-remote --tags "https://github.com/${action}.git" "refs/tags/${tag}"
  )"
  if [[ -z "${output}" ]]; then
    return 1
  fi

  printf '%s\n' "${output%%$'\t'*}"
}

nearby_comment() {
  local -n lines_ref="$1"
  local index="$2"
  local line="${lines_ref[${index}]}"
  local comment=""
  local previous

  if [[ "${line}" == *"#"* ]]; then
    comment="${line#*#}"
  fi

  if [[ -z "${comment//[[:space:]]/}" ]]; then
    for previous in "$((index - 1))" "$((index - 2))"; do
      if ((previous < 0)); then
        continue
      fi
      if [[ "${lines_ref[${previous}]}" =~ ^[[:space:]]*#(.*)$ ]]; then
        comment="${BASH_REMATCH[1]}"
        break
      fi
      if [[ "${lines_ref[${previous}]}" =~ [^[:space:]] ]]; then
        break
      fi
    done
  fi

  printf '%s\n' "${comment}"
}

status=0
found=false

while IFS= read -r -d '' file; do
  mapfile -t lines <"${file}"
  for index in "${!lines[@]}"; do
    line="${lines[${index}]}"
    if [[ ! "${line}" =~ uses:[[:space:]]*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-fA-F]{40}) ]]; then
      continue
    fi

    found=true
    action="${BASH_REMATCH[1]}"
    sha="${BASH_REMATCH[2]}"
    line_no=$((index + 1))
    comment="$(nearby_comment lines "${index}")"
    tag="$(extract_tag "${comment}")"

    if [[ -z "${tag}" ]]; then
      echo "${file}:${line_no}: ${action}@${sha} has no nearby tag/version comment" >&2
      status=1
      continue
    fi

    echo "${file}:${line_no}: ${action}@${sha} comment tag ${tag}"

    if [[ "${verify_remote}" != true ]]; then
      continue
    fi

    if ! remote_sha="$(resolve_tag_sha "${action}" "${tag}")"; then
      echo "${file}:${line_no}: could not resolve ${action} tag ${tag}" >&2
      status=1
    elif [[ "${remote_sha}" != "${sha}" ]]; then
      echo "${file}:${line_no}: ${action} ${tag} resolves to ${remote_sha}, not ${sha}" >&2
      status=1
    fi
  done
done < <(find "${workflow_dir}" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

if [[ "${found}" == false ]]; then
  echo "No full-SHA GitHub Actions uses: entries found."
fi

exit "${status}"
