#!/usr/bin/env bash
set -euo pipefail

status=0
tmp_files=()
roxygen_dirs=()
roxygen_files=()

trap 'if ((${#tmp_files[@]} > 0)); then rm -f "${tmp_files[@]}"; fi' EXIT

usage() {
  cat <<'USAGE'
Usage: audit-roxygen-markdown.sh [mode ...]

Audit roxygen markdown conversion from an R package root.

Modes:
  --check-description  Require DESCRIPTION to enable Roxygen markdown.
  --md-overrides       Find roxygen @md and @noMd overrides.
  --raw-rd             Find raw Rd macros in roxygen comments.
  --odd-backticks      Find roxygen comment lines with odd backtick counts.
  --check-rd           Run tools::checkRd over generated man/*.Rd files.
  --idempotence        Run roxygen2::roxygenise() and compare generated state.
  --all                Run every mode above.
  --help               Show this help.

The --idempotence and --all modes may update generated documentation.
USAGE
}

require_command() {
  local command_name="$1"

  if command -v "${command_name}" >/dev/null 2>&1; then
    return 0
  fi

  echo "${command_name} is required for this check." >&2
  status=1
  return 1
}

load_roxygen_dirs() {
  roxygen_dirs=()
  [[ -d R ]] && roxygen_dirs+=(R)
  [[ -d man-roxygen ]] && roxygen_dirs+=(man-roxygen)

  if ((${#roxygen_dirs[@]} == 0)); then
    echo "No R or man-roxygen directory found; no roxygen source to audit."
    return 1
  fi

  return 0
}

load_roxygen_files() {
  local search_dirs=()

  roxygen_files=()
  [[ -d R ]] && search_dirs+=(R)
  [[ -d man-roxygen ]] && search_dirs+=(man-roxygen)

  if ((${#search_dirs[@]} == 0)); then
    echo "No R or man-roxygen directory found; no roxygen source to audit."
    return 1
  fi

  while IFS= read -r -d '' file; do
    roxygen_files+=("${file}")
  done < <(
    find "${search_dirs[@]}" -type f -name '*.R' -print0
  )

  if ((${#roxygen_files[@]} == 0)); then
    echo "No R source files found under R or man-roxygen."
    return 1
  fi

  return 0
}

run_rg_audit() {
  local label="$1"
  local pattern="$2"
  local rc

  if ! require_command rg; then
    return
  fi
  if ! load_roxygen_dirs; then
    return
  fi

  echo "Checking ${label}..."
  if rg -n "${pattern}" "${roxygen_dirs[@]}"; then
    echo "${label} found; classify or convert before treating markdown conversion as complete." >&2
    status=1
  else
    rc=$?
    if [[ "${rc}" -eq 1 ]]; then
      echo "No ${label} found."
    else
      echo "rg failed while checking ${label}." >&2
      status=1
    fi
  fi
}

check_description() {
  echo "Checking DESCRIPTION roxygen markdown setting..."
  if [[ ! -f DESCRIPTION ]]; then
    echo "DESCRIPTION not found; run this from an R package root." >&2
    status=1
    return
  fi

  if grep -Eq '^Roxygen:[[:space:]]*list\(markdown[[:space:]]*=[[:space:]]*TRUE\)' DESCRIPTION; then
    echo "DESCRIPTION enables Roxygen markdown."
  else
    echo "DESCRIPTION does not contain Roxygen: list(markdown = TRUE)." >&2
    status=1
  fi
}

check_md_overrides() {
  run_rg_audit \
    "roxygen markdown override tags" \
    "^#'\\s*@(md|noMd)\\b"
}

check_raw_rd() {
  run_rg_audit \
    "raw Rd macros in roxygen comments" \
    "^#'.*\\\\(code|link|url|href|itemize|item|emph|strong|describe|dontrun|donttest|dontshow|eqn|deqn|Sexpr|tabular)"
}

check_odd_backticks() {
  local output

  if ! require_command perl; then
    return
  fi
  if ! load_roxygen_files; then
    return
  fi

  echo "Checking odd backtick counts in roxygen comment lines..."
  if ! output="$(perl -ne 'if (/^#\x27/ && (tr/`// % 2)) { print "$ARGV:$.:$_" }' "${roxygen_files[@]}")"; then
    echo "perl failed while checking odd backtick counts." >&2
    status=1
    return
  fi

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${output}"
    status=1
  else
    echo "No odd roxygen backtick counts found."
  fi
}

check_rd() {
  if ! require_command Rscript; then
    return
  fi

  echo "Running tools::checkRd over generated Rd files..."
  if [[ ! -d man ]]; then
    echo "No man directory found; no generated Rd files to check."
    return
  fi

  if ! Rscript --vanilla -e '
    files <- list.files("man", pattern = "[.]Rd$", full.names = TRUE)
    if (!length(files)) {
      message("No generated Rd files found.")
      quit(status = 0L)
    }

    status <- 0L
    for (path in files) {
      issues <- tools::checkRd(path)
      if (length(issues)) {
        cat(path, ":\n", sep = "")
        print(issues)
        status <- 1L
      }
    }
    quit(status = status)
  '; then
    status=1
  fi
}

checksum_file() {
  local path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum "${path}"
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum "${path}"
  else
    cksum "${path}"
  fi
}

snapshot_generated_checksums() {
  local generated_paths=()
  local path

  for path in DESCRIPTION NAMESPACE man; do
    [[ -e "${path}" ]] && generated_paths+=("${path}")
  done

  if ((${#generated_paths[@]} == 0)); then
    return
  fi

  find "${generated_paths[@]}" -type f -print 2>/dev/null |
    LC_ALL=C sort |
    while IFS= read -r path; do
      checksum_file "${path}"
    done
}

snapshot_generated_state() {
  printf '## git status\n'
  git status --porcelain -- DESCRIPTION NAMESPACE man
  printf '## git diff\n'
  git diff --no-ext-diff -- DESCRIPTION NAMESPACE man
  printf '## generated file checksums\n'
  snapshot_generated_checksums
}

check_idempotence() {
  local before
  local after

  if ! require_command git; then
    return
  fi
  if ! require_command Rscript; then
    return
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "--idempotence requires a git worktree for before/after comparison." >&2
    status=1
    return
  fi

  before="$(mktemp)"
  after="$(mktemp)"
  tmp_files+=("${before}" "${after}")

  snapshot_generated_state >"${before}"

  echo "Running roxygen2::roxygenise() for idempotence check..."
  if ! Rscript --vanilla -e 'roxygen2::roxygenise()'; then
    status=1
    return
  fi

  snapshot_generated_state >"${after}"
  if cmp -s "${before}" "${after}"; then
    echo "roxygenise generated no additional DESCRIPTION, NAMESPACE, or man file changes."
  else
    echo "roxygenise changed generated documentation state." >&2
    git status --short -- DESCRIPTION NAMESPACE man || true
    git diff --stat -- DESCRIPTION NAMESPACE man || true
    status=1
  fi
}

if (($# == 0)); then
  usage
  exit 0
fi

modes=()
for arg in "$@"; do
  case "${arg}" in
    --help)
      usage
      exit 0
      ;;
    --all)
      modes=(
        --check-description
        --md-overrides
        --raw-rd
        --odd-backticks
        --check-rd
        --idempotence
      )
      ;;
    --check-description | --md-overrides | --raw-rd | --odd-backticks | --check-rd | --idempotence)
      modes+=("${arg}")
      ;;
    *)
      echo "Unknown mode: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for mode in "${modes[@]}"; do
  case "${mode}" in
    --check-description) check_description ;;
    --md-overrides) check_md_overrides ;;
    --raw-rd) check_raw_rd ;;
    --odd-backticks) check_odd_backticks ;;
    --check-rd) check_rd ;;
    --idempotence) check_idempotence ;;
  esac
done

exit "${status}"
