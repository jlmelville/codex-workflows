#!/usr/bin/env bash
set -euo pipefail

workflow_dir=".github/workflows"
require_mode="tag"
verify_remote=false
uses_pattern="^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*['\"]?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*)@([0-9a-fA-F]{40})['\"]?([[:space:]#]|$)"

usage() {
  cat <<'USAGE'
Usage: check-action-tag-comments.sh [--require-comment|--require-tag] [--verify-remote] [WORKFLOW_DIR]

Check SHA-pinned GitHub Actions uses: entries for nearby version/tag comments.

By default this requires a nearby tag-like comment such as v4 or v4.1.2. Use
--require-comment to accept any nearby non-empty comment. With --verify-remote,
each detected tag is resolved with git ls-remote over public HTTPS and compared
to the pinned SHA.
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
    --require-comment)
      require_mode="comment"
      shift
      ;;
    --require-tag)
      require_mode="tag"
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
  local repo="$1"
  local tag="$2"
  local fallback=""
  local output
  local ref
  local sha

  if ! output="$(
    GIT_CONFIG_GLOBAL=/dev/null \
      GIT_CONFIG_NOSYSTEM=1 \
      GIT_TERMINAL_PROMPT=0 \
      git ls-remote --tags "https://github.com/${repo}.git" \
        "refs/tags/${tag}" \
        "refs/tags/${tag}^{}"
  )"; then
    return 1
  fi
  if [[ -z "${output}" ]]; then
    return 1
  fi

  while IFS=$'\t' read -r sha ref; do
    if [[ "${ref}" == "refs/tags/${tag}^{}" ]]; then
      printf '%s\n' "${sha}"
      return 0
    fi
    if [[ "${ref}" == "refs/tags/${tag}" && -z "${fallback}" ]]; then
      fallback="${sha}"
    fi
  done <<<"${output}"

  if [[ -n "${fallback}" ]]; then
    printf '%s\n' "${fallback}"
    return 0
  fi

  return 1
}

action_repo() {
  local action="$1"
  local owner
  local repo

  IFS=/ read -r owner repo _ <<<"${action}"
  printf '%s/%s\n' "${owner}" "${repo}"
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
    if [[ ! "${line}" =~ ${uses_pattern} ]]; then
      continue
    fi

    found=true
    action="${BASH_REMATCH[2]}"
    sha="${BASH_REMATCH[4]}"
    line_no=$((index + 1))
    comment="$(nearby_comment lines "${index}")"
    tag="$(extract_tag "${comment}")"

    if [[ -z "${comment//[[:space:]]/}" ]]; then
      echo "${file}:${line_no}: ${action}@${sha} has no nearby version/reason comment" >&2
      status=1
      continue
    fi

    if [[ "${require_mode}" == "tag" && -z "${tag}" ]]; then
      echo "${file}:${line_no}: ${action}@${sha} has no nearby tag/version comment" >&2
      status=1
      continue
    fi

    if [[ -n "${tag}" ]]; then
      echo "${file}:${line_no}: ${action}@${sha} comment tag ${tag}"
    else
      echo "${file}:${line_no}: ${action}@${sha} nearby comment present"
    fi

    if [[ "${verify_remote}" != true || -z "${tag}" ]]; then
      continue
    fi

    repo="$(action_repo "${action}")"
    if ! remote_sha="$(resolve_tag_sha "${repo}" "${tag}")"; then
      echo "${file}:${line_no}: could not resolve ${action} tag ${tag} in ${repo}" >&2
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
