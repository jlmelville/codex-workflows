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

create_fixture() {
  local fixture="$1"

  mkdir -p "${fixture}/skills"
  cp -a "${repo_dir}/install.sh" "${fixture}/install.sh"
  create_skill "${fixture}" alpha "alpha v1"
  create_skill "${fixture}" beta "beta v1"
}

manifest="${tmp_root}/codex-home/codex-workflows-managed-skills.tsv"
fixture="${tmp_root}/fixture"
codex_home="${tmp_root}/codex-home"
create_fixture "${fixture}"

mkdir -p "${codex_home}/skills/unrelated" "${codex_home}/skills/legacy-stale" "${codex_home}/skills/alpha"
cat >"${codex_home}/skills/unrelated/data.txt" <<'EOF_UNRELATED'
do not touch
EOF_UNRELATED
cat >"${codex_home}/skills/legacy-stale/data.txt" <<'EOF_STALE'
legacy unknown
EOF_STALE
cat >"${codex_home}/skills/alpha/old.txt" <<'EOF_OLD'
old alpha
EOF_OLD
chmod 700 "${codex_home}/skills/unrelated"
chmod 600 "${codex_home}/skills/unrelated/data.txt"

CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
[[ -f "${manifest}" ]] || fail "first run did not write manifest"
assert_file_contains "${manifest}" "# codex-workflows-managed-skills v1"
assert_file_contains "${manifest}" "alpha"
assert_file_contains "${manifest}" "beta"
[[ -f "${codex_home}/skills/alpha/SKILL.md" ]] || fail "first run did not replace alpha"
[[ -f "${codex_home}/skills/beta/SKILL.md" ]] || fail "first run did not install beta"
[[ -f "${codex_home}/skills/legacy-stale/data.txt" ]] || fail "first run removed unknown legacy stale skill"
[[ "$(cat "${codex_home}/skills/unrelated/data.txt")" == "do not touch" ]] || fail "unrelated skill content changed"
assert_mode "${codex_home}/skills/unrelated" 700
assert_mode "${codex_home}/skills/unrelated/data.txt" 600
assert_mode "${codex_home}/skills/alpha/scripts/run.sh" 755
assert_mode "${codex_home}/skills/alpha/notes.txt" 640

CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null
before_idempotence="$(snapshot_tree "${codex_home}")"
CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
after_idempotence="$(snapshot_tree "${codex_home}")"
[[ "${before_idempotence}" == "${after_idempotence}" ]] || fail "second install changed paths, types, modes, or content"

echo "drift" >>"${codex_home}/skills/alpha/SKILL.md"
if CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check did not detect managed content drift"
fi
CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
chmod 600 "${codex_home}/skills/alpha/scripts/run.sh"
if CODEX_HOME="${codex_home}" "${fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check did not detect managed mode drift"
fi
CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null

rm -rf "${fixture}/skills/beta"
CODEX_HOME="${codex_home}" "${fixture}/install.sh" >/dev/null
[[ ! -e "${codex_home}/skills/beta" ]] || fail "stale managed skill beta was not removed"
[[ -f "${codex_home}/skills/legacy-stale/data.txt" ]] || fail "upgrade removed unrelated legacy stale skill"
if grep -F "beta" "${manifest}" >/dev/null; then
  fail "manifest still lists removed managed skill beta"
fi

lock_home="${tmp_root}/lock-home"
create_fixture "${tmp_root}/lock-fixture"
mkdir -p "${lock_home}/.codex-workflows-install.lock"
printf '%s\n' "12345" >"${lock_home}/.codex-workflows-install.lock/pid"
printf '%s\n' "smoke-host" >"${lock_home}/.codex-workflows-install.lock/hostname"
printf '%s\n' "2026-01-02T03:04:05Z" >"${lock_home}/.codex-workflows-install.lock/created_at"
if CODEX_HOME="${lock_home}" "${tmp_root}/lock-fixture/install.sh" >"${tmp_root}/lock.out" 2>&1; then
  fail "installer succeeded despite existing lock"
fi
assert_file_contains "${tmp_root}/lock.out" "pid: 12345"
assert_file_contains "${tmp_root}/lock.out" "hostname: smoke-host"
assert_file_contains "${tmp_root}/lock.out" "created_at: 2026-01-02T03:04:05Z"
[[ -d "${lock_home}/.codex-workflows-install.lock" ]] || fail "installer removed a lock it did not acquire"

partial_fixture="${tmp_root}/partial-fixture"
partial_home="${tmp_root}/partial-home"
create_fixture "${partial_fixture}"
rm -rf "${partial_fixture}/skills/beta"
CODEX_HOME="${partial_home}" "${partial_fixture}/install.sh" >/dev/null
old_manifest="$(cat "${partial_home}/codex-workflows-managed-skills.tsv")"
create_skill "${partial_fixture}" gamma "gamma v1"
printf '\nalpha v2\n' >>"${partial_fixture}/skills/alpha/SKILL.md"
if CODEX_WORKFLOWS_INSTALL_FAIL_AFTER_REPLACE=1 CODEX_HOME="${partial_home}" "${partial_fixture}/install.sh" >"${tmp_root}/partial.out" 2>&1; then
  fail "simulated partial install unexpectedly succeeded"
fi
assert_file_contains "${tmp_root}/partial.out" "runtime may be partially updated"
[[ "$(cat "${partial_home}/codex-workflows-managed-skills.tsv")" == "${old_manifest}" ]] || fail "partial failure changed old manifest"
if CODEX_HOME="${partial_home}" "${partial_fixture}/install.sh" --check >/dev/null 2>&1; then
  fail "--check passed after simulated partial replacement"
fi
CODEX_HOME="${partial_home}" "${partial_fixture}/install.sh" >/dev/null
CODEX_HOME="${partial_home}" "${partial_fixture}/install.sh" --check >/dev/null
assert_file_contains "${partial_home}/codex-workflows-managed-skills.tsv" "gamma"

dry_home="${tmp_root}/dry-home"
create_fixture "${tmp_root}/dry-fixture"
CODEX_HOME="${dry_home}" "${tmp_root}/dry-fixture/install.sh" --dry-run >"${tmp_root}/dry.out"
[[ ! -e "${dry_home}/skills" ]] || fail "--dry-run created target skills directory"
[[ ! -e "${dry_home}/codex-workflows-managed-skills.tsv" ]] || fail "--dry-run created manifest"
assert_file_contains "${tmp_root}/dry.out" "Would create first managed-skill manifest"

echo "Installer smoke tests passed."
