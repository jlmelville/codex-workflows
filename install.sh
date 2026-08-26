#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agents_home="${HOME}/.agents"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
source_dir="${repo_dir}/skills"
target_dir="${agents_home}/skills"
repo_skill_dir="${repo_dir}/.agents/skills"
manifest_path="${agents_home}/codex-workflows-managed-skills.tsv"
legacy_target_dir="${codex_home}/skills"
legacy_manifest_path="${codex_home}/codex-workflows-managed-skills.tsv"
global_learning_helper="${repo_dir}/scripts/manage-global-learning.rb"
global_learning_asset="${source_dir}/skill-retro/assets/global-agents-learning.md"
ruby_policy_checker="${repo_dir}/scripts/check-ruby-runtime.sh"
ruby_version_file="${repo_dir}/.ruby-version"
manifest_version="# codex-workflows-managed-skills v1"
lock_dir="${agents_home}/.codex-workflows-install.lock"
mode="install"
lock_acquired=0
lock_token=""
stage_root=""
status=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check | --dry-run]

Sync user-scoped repository-owned skills into $HOME/.agents/skills, and manage
the canonical global learning instructions in the active Codex instruction
file. Skills linked from .agents/skills remain available only inside this
repository.

When a managed manifest exists in the legacy Codex-home location, a normal
install migrates only the skills named by that manifest and preserves all
unrelated installed skills.

Options:
  --check    Validate skill scopes, manifests, modes, and global instructions.
  --dry-run  Report planned skill and global-instruction changes.
  --help     Show this help.
EOF
}

die() {
  echo "install.sh: $*" >&2
  exit 1
}

run_ruby_preflight() {
  [[ -x "${ruby_policy_checker}" ]] || \
    die "Ruby policy checker is missing or not executable: ${ruby_policy_checker}"
  if ! "${ruby_policy_checker}"; then
    die "Ruby runtime preflight failed before installation changes"
  fi
  IFS= read -r required_ruby_version <"${ruby_version_file}" || \
    die "could not read canonical Ruby version: ${ruby_version_file}"
  export RBENV_VERSION="${required_ruby_version}"
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

run_ruby_preflight

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

skill_names_from_repo_scope() {
  local skill_dir

  [[ -d "${repo_skill_dir}" ]] || return 0
  for skill_dir in "${repo_skill_dir}"/*; do
    [[ -e "${skill_dir}" || -L "${skill_dir}" ]] || continue
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
  local name

  all_source_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && all_source_names+=("${name}")
  done < <(skill_names_from_source)

  repo_local_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && repo_local_names+=("${name}")
  done < <(skill_names_from_repo_scope)

  source_names=()
  for name in "${all_source_names[@]}"; do
    if ! contains_name "${name}" "${repo_local_names[@]}"; then
      source_names+=("${name}")
    fi
  done
}

read_old_manifest_names() {
  old_manifest_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && old_manifest_names+=("${name}")
  done < <(manifest_names "${manifest_path}")
}

read_legacy_manifest_names() {
  legacy_manifest_names=()
  [[ "${legacy_manifest_path}" != "${manifest_path}" ]] || return 0

  while IFS= read -r name; do
    [[ -n "${name}" ]] && legacy_manifest_names+=("${name}")
  done < <(manifest_names "${legacy_manifest_path}")
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
  local name skill_file link_target expected_dir actual_dir

  [[ -d "${source_dir}" ]] || die "source skills directory not found: ${source_dir}"
  [[ -x "${global_learning_helper}" ]] || \
    die "global learning helper is missing or not executable: ${global_learning_helper}"
  [[ -f "${global_learning_asset}" ]] || \
    die "global learning asset not found: ${global_learning_asset}"
  read_source_names
  ((${#all_source_names[@]} > 0)) || die "no source skills found in ${source_dir}"

  for name in "${all_source_names[@]}"; do
    case "${name}" in
      .*|*/*|*" "*|*"	"*)
        die "invalid source skill directory name: ${name}"
        ;;
    esac
    skill_file="${source_dir}/${name}/SKILL.md"
    [[ -f "${skill_file}" ]] || die "${source_dir}/${name}: missing SKILL.md"
  done

  for name in "${repo_local_names[@]}"; do
    case "${name}" in
      .*|*/*|*" "*|*"	"*)
        die "invalid repository-local skill name: ${name}"
        ;;
    esac
    contains_name "${name}" "${all_source_names[@]}" || \
      die "repository-local skill has no canonical source: ${name}"
    [[ -L "${repo_skill_dir}/${name}" ]] || \
      die "repository-local skill must be a symlink: ${repo_skill_dir}/${name}"
    link_target="$(readlink "${repo_skill_dir}/${name}")"
    [[ "${link_target}" != /* ]] || \
      die "repository-local skill symlink must be relative: ${repo_skill_dir}/${name}"
    if ! expected_dir="$(cd "${source_dir}/${name}" && pwd -P)"; then
      die "could not resolve canonical source skill: ${source_dir}/${name}"
    fi
    if ! actual_dir="$(cd "${repo_skill_dir}/${name}" 2>/dev/null && pwd -P)"; then
      die "broken repository-local skill symlink: ${repo_skill_dir}/${name}"
    fi
    [[ "${actual_dir}" == "${expected_dir}" ]] || \
      die "repository-local skill symlink points outside canonical source: ${repo_skill_dir}/${name}"
  done
}

manage_global_learning() {
  local learning_mode="$1"

  "${global_learning_helper}" "${learning_mode}" \
    --asset "${global_learning_asset}" \
    --codex-home "${codex_home}"
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
  stage_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-workflows-install-stage.XXXXXX")"
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

report_lock_creation_failure() {
  echo "install.sh: could not create install lock directory ${lock_dir}" >&2
  if [[ -e "${lock_dir}" || -L "${lock_dir}" ]]; then
    echo "A non-directory path already exists at the lock location." >&2
  else
    echo "Check write permission and filesystem availability for ${agents_home}." >&2
  fi
}

acquire_lock() {
  mkdir -p "${agents_home}"
  lock_token="pid=$$ host=$(host_name) created_at=$(now_utc)"
  if ! mkdir "${lock_dir}" 2>/dev/null; then
    if [[ -d "${lock_dir}" ]]; then
      report_lock_owner
    else
      report_lock_creation_failure
    fi
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
  if [[ "${legacy_manifest_path}" != "${manifest_path}" && -f "${legacy_manifest_path}" ]]; then
    validate_manifest_file "${legacy_manifest_path}"
    echo "install.sh: legacy managed-skill manifest remains: ${legacy_manifest_path}" >&2
    echo "install.sh: run ./install.sh to migrate managed skills into ${target_dir}" >&2
    status=1
  fi

  if [[ ! -f "${manifest_path}" ]]; then
    echo "install.sh: missing managed-skill manifest: ${manifest_path}" >&2
    return 1
  fi

  read_old_manifest_names
  for name in "${old_manifest_names[@]}"; do
    if ! contains_name "${name}" "${source_names[@]}"; then
      echo "install.sh: manifest contains skill outside the user scope: ${name}" >&2
      status=1
    fi
  done
  for name in "${source_names[@]}"; do
    if ! contains_name "${name}" "${old_manifest_names[@]}"; then
      echo "install.sh: user-scoped source skill missing from managed manifest: ${name}" >&2
      status=1
    elif ! compare_trees "${source_dir}/${name}" "${target_dir}/${name}" "${name}"; then
      status=1
    fi
  done
  for name in "${repo_local_names[@]}"; do
    if [[ -e "${target_dir}/${name}" || -L "${target_dir}/${name}" ]]; then
      echo "install.sh: repository-local skill also exists in the user scope: ${name}" >&2
      status=1
    fi
  done

  if ! manage_global_learning check; then
    status=1
  fi

  if [[ "${status}" -eq 0 ]]; then
    echo "Managed user-scoped skills match ${source_dir} in ${target_dir}"
    if ((${#repo_local_names[@]} > 0)); then
      echo "Repository-local skill links are valid in ${repo_skill_dir}"
    fi
  fi
  return "${status}"
}

dry_run_install() {
  local name

  validate_source_tree
  validate_manifest_file "${manifest_path}"
  if [[ "${legacy_manifest_path}" != "${manifest_path}" ]]; then
    validate_manifest_file "${legacy_manifest_path}"
  fi
  read_old_manifest_names
  read_legacy_manifest_names

  if [[ ! -f "${manifest_path}" ]]; then
    echo "Would create first managed-skill manifest at ${manifest_path}"
    echo "Would replace current user-scoped skills only; unrelated installed skills would be preserved."
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

  for name in "${repo_local_names[@]}"; do
    echo "Would use repository-local skill link: ${name}"
  done

  if [[ -f "${manifest_path}" ]]; then
    for name in "${old_manifest_names[@]}"; do
      if ! contains_name "${name}" "${source_names[@]}"; then
        echo "Would remove stale managed skill: ${name}"
      fi
    done
  fi

  if [[ -f "${legacy_manifest_path}" ]]; then
    echo "Would migrate legacy managed skills from ${legacy_target_dir}"
    for name in "${legacy_manifest_names[@]}"; do
      if [[ -e "${legacy_target_dir}/${name}" ]]; then
        echo "Would remove legacy managed skill after migration: ${name}"
      fi
    done
    echo "Would remove legacy managed-skill manifest: ${legacy_manifest_path}"
  fi

  manage_global_learning dry-run
}

install_skills() {
  local name replaced_count=0 fail_after="${CODEX_WORKFLOWS_INSTALL_FAIL_AFTER_REPLACE:-}"

  validate_source_tree
  validate_manifest_file "${manifest_path}"
  if [[ "${legacy_manifest_path}" != "${manifest_path}" ]]; then
    validate_manifest_file "${legacy_manifest_path}"
  fi
  read_old_manifest_names
  read_legacy_manifest_names
  manage_global_learning dry-run >/dev/null
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

  if [[ -f "${legacy_manifest_path}" ]]; then
    for name in "${legacy_manifest_names[@]}"; do
      rm -rf "${legacy_target_dir:?}/${name}"
    done
    rm -f "${legacy_manifest_path}"
    echo "Migrated legacy managed skills out of ${legacy_target_dir}"
  fi

  if ! manage_global_learning install; then
    echo "install.sh: managed skills were updated, but global learning instructions were not." >&2
    echo "install.sh: resolve the reported instruction-file issue and rerun ./install.sh." >&2
    exit 1
  fi

  echo "Installed managed user-scoped skills from ${source_dir} to ${target_dir}"
  echo "Managed-skill manifest updated at ${manifest_path}"
  if ((${#repo_local_names[@]} > 0)); then
    echo "Repository-local skills are available from ${repo_skill_dir}"
  fi
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
