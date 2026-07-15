#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
source_dir="${repo_dir}/skills"
target_dir="${codex_home}/skills"
manifest_path="${codex_home}/codex-workflows-managed-skills.tsv"
manifest_version="# codex-workflows-managed-skills v1"
lock_dir="${codex_home}/.codex-workflows-install.lock"
mode="install"
lock_acquired=0
lock_token=""
stage_root=""
status=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check | --dry-run]

Sync repository-owned skills into ${CODEX_HOME:-$HOME/.codex}/skills.

Options:
  --check    Validate managed installed skills, manifest membership, and modes.
  --dry-run  Report planned install changes without mutating the target.
  --help     Show this help.
EOF
}

die() {
  echo "install.sh: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${stage_root}" && -d "${stage_root}" ]]; then
    rm -rf "${stage_root}"
  fi

  if [[ "${lock_acquired}" -eq 1 && -n "${lock_token}" && -d "${lock_dir}" ]]; then
    if [[ -f "${lock_dir}/owner" ]] && [[ "$(cat "${lock_dir}/owner" 2>/dev/null || true)" == "${lock_token}" ]]; then
      rm -f "${lock_dir}/pid" "${lock_dir}/hostname" "${lock_dir}/created_at" "${lock_dir}/owner"
      rmdir "${lock_dir}" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT HUP INT TERM

while (($# > 0)); do
  case "$1" in
    --check)
      [[ "${mode}" == "install" ]] || die "--check cannot be combined with another mode"
      mode="check"
      ;;
    --dry-run)
      [[ "${mode}" == "install" ]] || die "--dry-run cannot be combined with another mode"
      mode="dry-run"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

host_name() {
  hostname 2>/dev/null || uname -n
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

stat_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

relative_find() {
  local root="$1"

  (
    cd "${root}"
    find . -mindepth 1 -print | sed 's#^\./##' | LC_ALL=C sort
  )
}

skill_names_from_source() {
  local skill_dir

  for skill_dir in "${source_dir}"/*; do
    [[ -d "${skill_dir}" ]] || continue
    basename "${skill_dir}"
  done | LC_ALL=C sort
}

manifest_names() {
  local path="$1"

  [[ -f "${path}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    printf '%s\n' "${line}"
  done <"${path}" | LC_ALL=C sort
}

contains_name() {
  local needle="$1"
  local item
  shift

  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

read_source_names() {
  source_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && source_names+=("${name}")
  done < <(skill_names_from_source)
}

read_old_manifest_names() {
  old_manifest_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && old_manifest_names+=("${name}")
  done < <(manifest_names "${manifest_path}")
}

validate_manifest_file() {
  local path="$1"
  local line

  [[ -f "${path}" ]] || return 0
  IFS= read -r line <"${path}" || die "${path}: empty manifest"
  [[ "${line}" == "${manifest_version}" ]] || die "${path}: unsupported manifest version"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    case "${line}" in
      */*|.*|*" "*|*"	"*)
        die "${path}: invalid skill name in manifest: ${line}"
        ;;
    esac
  done <"${path}"
}

validate_source_tree() {
  local name skill_file

  [[ -d "${source_dir}" ]] || die "source skills directory not found: ${source_dir}"
  read_source_names
  ((${#source_names[@]} > 0)) || die "no source skills found in ${source_dir}"

  for name in "${source_names[@]}"; do
    case "${name}" in
      .*|*/*|*" "*|*"	"*)
        die "invalid source skill directory name: ${name}"
        ;;
    esac
    skill_file="${source_dir}/${name}/SKILL.md"
    [[ -f "${skill_file}" ]] || die "${source_dir}/${name}: missing SKILL.md"
  done
}

compare_trees() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  local rel expected_path actual_path expected_mode actual_mode
  local tmp_dir

  if [[ ! -d "${actual}" ]]; then
    echo "${label}: missing installed directory: ${actual}" >&2
    return 1
  fi

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-workflows-compare.XXXXXX")"
  relative_find "${expected}" >"${tmp_dir}/expected"
  relative_find "${actual}" >"${tmp_dir}/actual"

  if ! cmp -s "${tmp_dir}/expected" "${tmp_dir}/actual"; then
    echo "${label}: file list differs" >&2
    diff -u "${tmp_dir}/expected" "${tmp_dir}/actual" >&2 || true
    rm -rf "${tmp_dir}"
    return 1
  fi

  while IFS= read -r rel || [[ -n "${rel}" ]]; do
    expected_path="${expected}/${rel}"
    actual_path="${actual}/${rel}"
    if [[ -d "${expected_path}" ]]; then
      if [[ ! -d "${actual_path}" ]]; then
        echo "${label}: expected directory at ${rel}" >&2
        rm -rf "${tmp_dir}"
        return 1
      fi
    elif [[ -f "${expected_path}" ]]; then
      if [[ ! -f "${actual_path}" ]]; then
        echo "${label}: expected file at ${rel}" >&2
        rm -rf "${tmp_dir}"
        return 1
      fi
      if ! cmp -s "${expected_path}" "${actual_path}"; then
        echo "${label}: content differs at ${rel}" >&2
        rm -rf "${tmp_dir}"
        return 1
      fi
    else
      echo "${label}: unsupported source entry type at ${rel}" >&2
      rm -rf "${tmp_dir}"
      return 1
    fi

    expected_mode="$(stat_mode "${expected_path}")"
    actual_mode="$(stat_mode "${actual_path}")"
    if [[ "${expected_mode}" != "${actual_mode}" ]]; then
      echo "${label}: mode differs at ${rel}: source ${expected_mode}, installed ${actual_mode}" >&2
      rm -rf "${tmp_dir}"
      return 1
    fi
  done <"${tmp_dir}/expected"

  rm -rf "${tmp_dir}"
  return 0
}

write_manifest() {
  local output="$1"
  local name

  {
    printf '%s\n' "${manifest_version}"
    for name in "${source_names[@]}"; do
      printf '%s\n' "${name}"
    done
  } >"${output}"
}

stage_source() {
  mkdir -p "${codex_home}"
  stage_root="$(mktemp -d "${codex_home}/.codex-workflows-install-stage.XXXXXX")"
  mkdir -p "${stage_root}/skills"

  local name
  for name in "${source_names[@]}"; do
    cp -a "${source_dir}/${name}" "${stage_root}/skills/"
    compare_trees "${source_dir}/${name}" "${stage_root}/skills/${name}" "staged ${name}" >/dev/null
  done
  write_manifest "${stage_root}/manifest"
}

report_lock_owner() {
  echo "install.sh: another install appears to hold ${lock_dir}" >&2
  if [[ -f "${lock_dir}/pid" ]]; then
    echo "  pid: $(cat "${lock_dir}/pid" 2>/dev/null || true)" >&2
  fi
  if [[ -f "${lock_dir}/hostname" ]]; then
    echo "  hostname: $(cat "${lock_dir}/hostname" 2>/dev/null || true)" >&2
  fi
  if [[ -f "${lock_dir}/created_at" ]]; then
    echo "  created_at: $(cat "${lock_dir}/created_at" 2>/dev/null || true)" >&2
  fi
  echo "Remove the lock directory only after confirming no installer is running." >&2
}

acquire_lock() {
  mkdir -p "${codex_home}"
  lock_token="pid=$$ host=$(host_name) created_at=$(now_utc)"
  if ! mkdir "${lock_dir}" 2>/dev/null; then
    report_lock_owner
    exit 1
  fi
  lock_acquired=1
  printf '%s\n' "$$" >"${lock_dir}/pid"
  host_name >"${lock_dir}/hostname"
  now_utc >"${lock_dir}/created_at"
  printf '%s\n' "${lock_token}" >"${lock_dir}/owner"
}

check_install() {
  local name

  validate_source_tree
  validate_manifest_file "${manifest_path}"

  if [[ ! -f "${manifest_path}" ]]; then
    echo "install.sh: missing managed-skill manifest: ${manifest_path}" >&2
    return 1
  fi

  read_old_manifest_names
  for name in "${old_manifest_names[@]}"; do
    if ! contains_name "${name}" "${source_names[@]}"; then
      echo "install.sh: manifest contains stale managed skill absent from source: ${name}" >&2
      status=1
    fi
  done
  for name in "${source_names[@]}"; do
    if ! contains_name "${name}" "${old_manifest_names[@]}"; then
      echo "install.sh: source skill missing from managed manifest: ${name}" >&2
      status=1
    elif ! compare_trees "${source_dir}/${name}" "${target_dir}/${name}" "${name}"; then
      status=1
    fi
  done

  if [[ "${status}" -eq 0 ]]; then
    echo "Managed skills match ${source_dir} in ${target_dir}"
  fi
  return "${status}"
}

dry_run_install() {
  local name

  validate_source_tree
  validate_manifest_file "${manifest_path}"
  read_old_manifest_names
  stage_source

  if [[ ! -f "${manifest_path}" ]]; then
    echo "Would create first managed-skill manifest at ${manifest_path}"
    echo "Would replace current source skills only; unrelated installed skills would be preserved."
  else
    echo "Would update managed-skill manifest at ${manifest_path}"
  fi

  for name in "${source_names[@]}"; do
    if [[ -d "${target_dir}/${name}" ]]; then
      echo "Would replace managed skill: ${name}"
    else
      echo "Would install managed skill: ${name}"
    fi
  done

  if [[ -f "${manifest_path}" ]]; then
    for name in "${old_manifest_names[@]}"; do
      if ! contains_name "${name}" "${source_names[@]}"; then
        echo "Would remove stale managed skill: ${name}"
      fi
    done
  fi
}

install_skills() {
  local name replaced_count=0 fail_after="${CODEX_WORKFLOWS_INSTALL_FAIL_AFTER_REPLACE:-}"

  validate_source_tree
  validate_manifest_file "${manifest_path}"
  read_old_manifest_names
  stage_source
  acquire_lock
  mkdir -p "${target_dir}"

  if [[ -f "${manifest_path}" ]]; then
    for name in "${old_manifest_names[@]}"; do
      if ! contains_name "${name}" "${source_names[@]}"; then
        rm -rf "${target_dir:?}/${name}"
      fi
    done
  fi

  for name in "${source_names[@]}"; do
    rm -rf "${target_dir:?}/${name}"
    cp -a "${stage_root}/skills/${name}" "${target_dir}/"
    replaced_count=$((replaced_count + 1))
    if [[ -n "${fail_after}" && "${replaced_count}" -ge "${fail_after}" ]]; then
      echo "install.sh: simulated failure after replacing ${replaced_count} skill(s)" >&2
      echo "install.sh: runtime may be partially updated; old manifest was retained. Rerun ./install.sh to recover." >&2
      exit 1
    fi
  done

  cp "${stage_root}/manifest" "${manifest_path}"
  echo "Installed managed skills from ${source_dir} to ${target_dir}"
  echo "Managed-skill manifest updated at ${manifest_path}"
}

case "${mode}" in
  check)
    check_install
    ;;
  dry-run)
    dry_run_install
    ;;
  install)
    install_skills
    ;;
esac
