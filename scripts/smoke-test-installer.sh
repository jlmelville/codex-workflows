#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-installer-smoke.XXXXXX")"
trap 'rm -rf "${tmp_root}"' EXIT

fail() {
  echo "installer smoke: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -F "${needle}" "${file}" >/dev/null; then
    echo "Expected ${file} to contain: ${needle}" >&2
    echo "--- ${file} ---" >&2
    cat "${file}" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"

  if grep -F "${needle}" "${file}" >/dev/null; then
    echo "Expected ${file} not to contain: ${needle}" >&2
    echo "--- ${file} ---" >&2
    cat "${file}" >&2
    exit 1
  fi
}

path_mode() {
  local path="$1"

  if stat -c '%a' "${path}" >/dev/null 2>&1; then
    stat -c '%a' "${path}"
  else
    stat -f '%Lp' "${path}"
  fi
}

assert_mode() {
  local path="$1"
  local expected="$2"
  local actual

  actual="$(path_mode "${path}")"

  [[ "${actual}" == "${expected}" ]] || fail "${path}: expected mode ${expected}, got ${actual}"
}

snapshot_tree() {
  local root="$1"
  local path relative type detail

  while IFS= read -r path; do
    relative="${path#"${root}"}"
    detail="-"

    if [[ -L "${path}" ]]; then
      type="symlink"
      detail="$(readlink "${path}")"
    elif [[ -d "${path}" ]]; then
      type="directory"
    elif [[ -f "${path}" ]]; then
      type="file"
      detail="$(cksum <"${path}")"
    else
      type="other"
    fi

    printf '%s\t%s\t%s\t%s\n' \
      "${relative}" "${type}" "$(path_mode "${path}")" "${detail}"
  done < <(find "${root}" -print | LC_ALL=C sort)
}

create_skill() {
  local fixture="$1"
  local name="$2"
  local body="$3"

  mkdir -p "${fixture}/skills/${name}/scripts"
  cat >"${fixture}/skills/${name}/SKILL.md" <<EOF_SKILL
---
name: ${name}
description: Smoke skill ${name}.
---

# ${name}

${body}
EOF_SKILL
  cat >"${fixture}/skills/${name}/scripts/run.sh" <<'EOF_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo ok
EOF_SCRIPT
  cat >"${fixture}/skills/${name}/notes.txt" <<EOF_NOTES
${body}
EOF_NOTES
  chmod 755 "${fixture}/skills/${name}/scripts/run.sh"
  chmod 640 "${fixture}/skills/${name}/notes.txt"
}

make_repo_local() {
  local fixture="$1"
  local name="$2"

  mkdir -p "${fixture}/.agents/skills"
  ln -s "../../skills/${name}" "${fixture}/.agents/skills/${name}"
}

create_fixture() {
  local fixture="$1"

  mkdir -p "${fixture}/skills"
  cp -a "${repo_dir}/install.sh" "${fixture}/install.sh"
  create_skill "${fixture}" alpha "alpha v1"
  create_skill "${fixture}" beta "beta v1"
  create_skill "${fixture}" repo-only "repo-only v1"
  make_repo_local "${fixture}" repo-only
}

fixture="${tmp_root}/fixture"
user_home="${tmp_root}/user-home"
agents_home="${user_home}/.agents"
codex_home="${user_home}/.codex"
manifest="${agents_home}/codex-workflows-managed-skills.tsv"
create_fixture "${fixture}"

mkdir -p "${agents_home}/skills/unrelated" "${agents_home}/skills/legacy-stale" "${agents_home}/skills/alpha"
cat >"${agents_home}/skills/unrelated/data.txt" <<'EOF_UNRELATED'
do not touch
EOF_UNRELATED
cat >"${agents_home}/skills/legacy-stale/data.txt" <<'EOF_STALE'
legacy unknown
EOF_STALE
cat >"${agents_home}/skills/alpha/old.txt" <<'EOF_OLD'
old alpha
EOF_OLD
chmod 700 "${agents_home}/skills/unrelated"
chmod 600 "${agents_home}/skills/unrelated/data.txt"

HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
[[ -f "${manifest}" ]] || fail "first run did not write manifest"
assert_file_contains "${manifest}" "# codex-workflows-managed-skills v1"
assert_file_contains "${manifest}" "alpha"
assert_file_contains "${manifest}" "beta"
assert_file_not_contains "${manifest}" "repo-only"
[[ -f "${agents_home}/skills/alpha/SKILL.md" ]] || fail "first run did not replace alpha"
[[ -f "${agents_home}/skills/beta/SKILL.md" ]] || fail "first run did not install beta"
[[ ! -e "${agents_home}/skills/repo-only" ]] || fail "first run installed a repository-local skill globally"
[[ -L "${fixture}/.agents/skills/repo-only" ]] || fail "repository-local skill is not a symlink"
[[ -f "${fixture}/.agents/skills/repo-only/SKILL.md" ]] || fail "repository-local skill symlink does not resolve"
[[ -f "${agents_home}/skills/legacy-stale/data.txt" ]] || fail "first run removed unknown legacy stale skill"
[[ "$(cat "${agents_home}/skills/unrelated/data.txt")" == "do not touch" ]] || fail "unrelated skill content changed"
assert_mode "${agents_home}/skills/unrelated" 700
assert_mode "${agents_home}/skills/unrelated/data.txt" 600
assert_mode "${agents_home}/skills/alpha/scripts/run.sh" 755
assert_mode "${agents_home}/skills/alpha/notes.txt" 640

HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null
mkdir -p "${agents_home}/skills/repo-only"
if HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check did not detect a repository-local skill duplicated in the user scope"
fi
rm -rf "${agents_home}/skills/repo-only"
HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null
before_idempotence="$(snapshot_tree "${agents_home}")"
HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
after_idempotence="$(snapshot_tree "${agents_home}")"
[[ "${before_idempotence}" == "${after_idempotence}" ]] || fail "second install changed paths, types, modes, or content"

echo "drift" >>"${agents_home}/skills/alpha/SKILL.md"
if HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check did not detect managed content drift"
fi
HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
chmod 600 "${agents_home}/skills/alpha/scripts/run.sh"
if HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check did not detect managed mode drift"
fi
HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null

rm -rf "${fixture}/skills/beta"
HOME="${user_home}" CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
[[ ! -e "${agents_home}/skills/beta" ]] || fail "stale managed skill beta was not removed"
[[ -f "${agents_home}/skills/legacy-stale/data.txt" ]] || fail "upgrade removed unrelated legacy stale skill"
if grep -F "beta" "${manifest}" >/dev/null; then
  fail "manifest still lists removed managed skill beta"
fi

scope_fixture="${tmp_root}/scope-fixture"
scope_user_home="${tmp_root}/scope-user-home"
scope_agents_home="${scope_user_home}/.agents"
scope_manifest="${scope_agents_home}/codex-workflows-managed-skills.tsv"
create_fixture "${scope_fixture}"
rm -rf "${scope_fixture}/.agents"
HOME="${scope_user_home}" CODEX_HOME="${scope_user_home}/.codex" "${scope_fixture}/install.sh" >/dev/null
[[ -f "${scope_agents_home}/skills/repo-only/SKILL.md" ]] || fail "scope fixture did not create the old global copy"
assert_file_contains "${scope_manifest}" "repo-only"
make_repo_local "${scope_fixture}" repo-only
HOME="${scope_user_home}" CODEX_HOME="${scope_user_home}/.codex" "${scope_fixture}/install.sh" --dry-run >"${tmp_root}/scope-dry.out"
assert_file_contains "${tmp_root}/scope-dry.out" "Would use repository-local skill link: repo-only"
assert_file_contains "${tmp_root}/scope-dry.out" "Would remove stale managed skill: repo-only"
HOME="${scope_user_home}" CODEX_HOME="${scope_user_home}/.codex" "${scope_fixture}/install.sh" >/dev/null
[[ ! -e "${scope_agents_home}/skills/repo-only" ]] || fail "scope migration retained the old global copy"
assert_file_not_contains "${scope_manifest}" "repo-only"
[[ -f "${scope_fixture}/.agents/skills/repo-only/SKILL.md" ]] || fail "scope migration broke the repository-local skill"
HOME="${scope_user_home}" CODEX_HOME="${scope_user_home}/.codex" "${scope_fixture}/install.sh" --check >/dev/null

lock_user_home="${tmp_root}/lock-user-home"
lock_agents_home="${lock_user_home}/.agents"
create_fixture "${tmp_root}/lock-fixture"
mkdir -p "${lock_agents_home}/.codex-workflows-install.lock"
printf '%s\n' "12345" >"${lock_agents_home}/.codex-workflows-install.lock/pid"
printf '%s\n' "smoke-host" >"${lock_agents_home}/.codex-workflows-install.lock/hostname"
printf '%s\n' "2026-01-02T03:04:05Z" >"${lock_agents_home}/.codex-workflows-install.lock/created_at"
if HOME="${lock_user_home}" CODEX_HOME="${lock_user_home}/.codex" "${tmp_root}/lock-fixture/install.sh" >"${tmp_root}/lock.out" 2>&1; then
  fail "installer succeeded despite existing lock"
fi
assert_file_contains "${tmp_root}/lock.out" "pid: 12345"
assert_file_contains "${tmp_root}/lock.out" "hostname: smoke-host"
assert_file_contains "${tmp_root}/lock.out" "created_at: 2026-01-02T03:04:05Z"
[[ -d "${lock_agents_home}/.codex-workflows-install.lock" ]] || fail "installer removed a lock it did not acquire"

denied_user_home="${tmp_root}/denied-lock-user-home"
denied_agents_home="${denied_user_home}/.agents"
create_fixture "${tmp_root}/denied-lock-fixture"
mkdir -p "${denied_agents_home}"
chmod 500 "${denied_agents_home}"
if HOME="${denied_user_home}" CODEX_HOME="${denied_user_home}/.codex" "${tmp_root}/denied-lock-fixture/install.sh" >"${tmp_root}/denied-lock.out" 2>&1; then
  chmod 700 "${denied_agents_home}"
  fail "installer succeeded despite denied lock creation"
fi
chmod 700 "${denied_agents_home}"
assert_file_contains "${tmp_root}/denied-lock.out" "could not create install lock directory"
assert_file_contains "${tmp_root}/denied-lock.out" "Check write permission and filesystem availability"
assert_file_not_contains "${tmp_root}/denied-lock.out" "another install appears"
[[ ! -e "${denied_agents_home}/.codex-workflows-install.lock" ]] || fail "denied lock fixture created a lock"

partial_fixture="${tmp_root}/partial-fixture"
partial_user_home="${tmp_root}/partial-user-home"
partial_agents_home="${partial_user_home}/.agents"
create_fixture "${partial_fixture}"
rm -rf "${partial_fixture}/skills/beta"
HOME="${partial_user_home}" CODEX_HOME="${partial_user_home}/.codex" "${partial_fixture}/install.sh" >/dev/null
old_manifest="$(cat "${partial_agents_home}/codex-workflows-managed-skills.tsv")"
create_skill "${partial_fixture}" gamma "gamma v1"
printf '\nalpha v2\n' >>"${partial_fixture}/skills/alpha/SKILL.md"
if CODEX_WORKFLOWS_INSTALL_FAIL_AFTER_REPLACE=1 HOME="${partial_user_home}" CODEX_HOME="${partial_user_home}/.codex" "${partial_fixture}/install.sh" >"${tmp_root}/partial.out" 2>&1; then
  fail "simulated partial install unexpectedly succeeded"
fi
assert_file_contains "${tmp_root}/partial.out" "runtime may be partially updated"
[[ "$(cat "${partial_agents_home}/codex-workflows-managed-skills.tsv")" == "${old_manifest}" ]] || fail "partial failure changed old manifest"
if HOME="${partial_user_home}" CODEX_HOME="${partial_user_home}/.codex" "${partial_fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check passed after simulated partial replacement"
fi
HOME="${partial_user_home}" CODEX_HOME="${partial_user_home}/.codex" "${partial_fixture}/install.sh" >/dev/null
HOME="${partial_user_home}" CODEX_HOME="${partial_user_home}/.codex" "${partial_fixture}/install.sh" --check >/dev/null
assert_file_contains "${partial_agents_home}/codex-workflows-managed-skills.tsv" "gamma"

dry_user_home="${tmp_root}/dry-user-home"
create_fixture "${tmp_root}/dry-fixture"
HOME="${dry_user_home}" CODEX_HOME="${dry_user_home}/.codex" "${tmp_root}/dry-fixture/install.sh" --dry-run >"${tmp_root}/dry.out"
[[ ! -e "${dry_user_home}/.agents/skills" ]] || fail "--dry-run created target skills directory"
[[ ! -e "${dry_user_home}/.agents/codex-workflows-managed-skills.tsv" ]] || fail "--dry-run created manifest"
assert_file_contains "${tmp_root}/dry.out" "Would create first managed-skill manifest"

migration_fixture="${tmp_root}/migration-fixture"
migration_user_home="${tmp_root}/migration-user-home"
migration_agents_home="${migration_user_home}/.agents"
migration_codex_home="${migration_user_home}/custom-codex"
create_fixture "${migration_fixture}"
mkdir -p \
  "${migration_codex_home}/skills/alpha" \
  "${migration_codex_home}/skills/beta" \
  "${migration_codex_home}/skills/unrelated"
cat >"${migration_codex_home}/codex-workflows-managed-skills.tsv" <<'EOF_MANIFEST'
# codex-workflows-managed-skills v1
alpha
beta
EOF_MANIFEST
printf '%s\n' "old alpha" >"${migration_codex_home}/skills/alpha/old.txt"
printf '%s\n' "old beta" >"${migration_codex_home}/skills/beta/old.txt"
printf '%s\n' "preserve" >"${migration_codex_home}/skills/unrelated/data.txt"

HOME="${migration_user_home}" CODEX_HOME="${migration_codex_home}" "${migration_fixture}/install.sh" --dry-run >"${tmp_root}/migration-dry.out"
assert_file_contains "${tmp_root}/migration-dry.out" "Would migrate legacy managed skills"
[[ -f "${migration_codex_home}/skills/alpha/old.txt" ]] || fail "migration dry-run changed a legacy managed skill"
HOME="${migration_user_home}" CODEX_HOME="${migration_codex_home}" "${migration_fixture}/install.sh" >/dev/null
[[ -f "${migration_agents_home}/skills/alpha/SKILL.md" ]] || fail "migration did not install alpha in the user skill directory"
[[ -f "${migration_agents_home}/skills/beta/SKILL.md" ]] || fail "migration did not install beta in the user skill directory"
[[ ! -e "${migration_codex_home}/skills/alpha" ]] || fail "migration retained legacy managed alpha"
[[ ! -e "${migration_codex_home}/skills/beta" ]] || fail "migration retained legacy managed beta"
[[ -f "${migration_codex_home}/skills/unrelated/data.txt" ]] || fail "migration removed an unrelated legacy skill"
[[ ! -e "${migration_codex_home}/codex-workflows-managed-skills.tsv" ]] || fail "migration retained the legacy manifest"
HOME="${migration_user_home}" CODEX_HOME="${migration_codex_home}" "${migration_fixture}/install.sh" --check >/dev/null

echo "Installer smoke tests passed."
