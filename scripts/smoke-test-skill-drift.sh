#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_source="${repo_dir}/scripts/audit-skill-drift.rb"

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required for the skill drift smoke test" >&2
  exit 1
fi

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-drift-smoke.XXXXXX")"
trap 'rm -rf "${fixture_dir}"' EXIT

mkdir -p "${fixture_dir}/scripts" "${fixture_dir}/skills/example/scripts"
cp "${audit_source}" "${fixture_dir}/scripts/audit-skill-drift.rb"

cat >"${fixture_dir}/scripts/audit-skill-drift-triage.tsv" <<'EOF'
# section	pattern	rationale
Repeated Helper Names	fixture_helper:	The duplicate helper is an intentional advisory fixture.
EOF

cat >"${fixture_dir}/scripts/one.sh" <<'EOF'
fixture_helper() {
  return 0
}
EOF

cat >"${fixture_dir}/scripts/two.sh" <<'EOF'
fixture_helper() {
  return 0
}
EOF

cat >"${fixture_dir}/skills/example/scripts/check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

skill_file="${fixture_dir}/skills/example/SKILL.md"
cat >"${skill_file}" <<'EOF'
---
name: example
description: Exercise deterministic drift-audit classification fixtures.
---

# Example

From this source
repository root, run:

```sh
scripts/check.sh
```
EOF
cp "${skill_file}" "${fixture_dir}/good-skill.md"

output_file="${fixture_dir}/audit.out"
error_file="${fixture_dir}/audit.err"
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --bogus >"${output_file}" 2>"${error_file}"; then
  echo "invalid audit option unexpectedly succeeded" >&2
  exit 1
else
  invalid_status=$?
fi
if [[ "${invalid_status}" -ne 2 ]] || [[ -s "${output_file}" ]] ||
  ! grep -Fq "audit-skill-drift.rb: invalid option: --bogus" "${error_file}" ||
  ! grep -Fq "Usage:" "${error_file}" || grep -Fq "OptionParser::" "${error_file}"; then
  cat "${error_file}" >&2
  echo "invalid audit option did not follow the CLI usage-error contract" >&2
  exit 1
fi

if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" extra >"${output_file}" 2>"${error_file}"; then
  echo "unexpected audit argument succeeded" >&2
  exit 1
else
  invalid_status=$?
fi
if [[ "${invalid_status}" -ne 2 ]] || [[ -s "${output_file}" ]] ||
  ! grep -Fq "audit-skill-drift.rb: unexpected argument: extra" "${error_file}" ||
  ! grep -Fq "Usage:" "${error_file}"; then
  cat "${error_file}" >&2
  echo "unexpected audit argument did not follow the CLI usage-error contract" >&2
  exit 1
fi

if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --triage "${fixture_dir}/missing.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "missing explicit triage manifest unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "triage manifest not found" "${error_file}" || grep -Fq "from .*audit-skill-drift.rb" "${error_file}"; then
  cat "${error_file}" >&2
  echo "missing explicit triage manifest did not produce a stable error" >&2
  exit 1
fi

printf '%s\n' 'malformed-row' >"${fixture_dir}/malformed.tsv"
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --triage "${fixture_dir}/malformed.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "malformed triage manifest unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "expected section<TAB>pattern<TAB>rationale" "${error_file}" ||
  grep -Fq "ArgumentError" "${error_file}"; then
  cat "${error_file}" >&2
  echo "malformed triage manifest did not produce a stable error" >&2
  exit 1
fi

if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "wrapped source-repository context or triaged advisory fixture failed" >&2
  exit 1
fi

if ! grep -Fq "No untriaged drift findings." "${output_file}"; then
  cat "${output_file}" >&2
  echo "clean fixture did not report zero untriaged findings" >&2
  exit 1
fi

cp "${fixture_dir}/scripts/audit-skill-drift-triage.tsv" "${fixture_dir}/scripts/triage.clean"
printf '%s\n' $'Description Overlap\tmissing-skill-a <-> missing-skill-b\tStale fixture entry.' \
  >>"${fixture_dir}/scripts/audit-skill-drift-triage.tsv"
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "unused triage fixture unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Unused Triage Entries" "${output_file}"; then
  cat "${output_file}" >&2
  echo "unused triage fixture did not produce the expected hard finding" >&2
  exit 1
fi
cp "${fixture_dir}/scripts/triage.clean" "${fixture_dir}/scripts/audit-skill-drift-triage.tsv"

cat >>"${skill_file}" <<'EOF'

Run <skill-dir>/scripts/check.sh.
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "placeholder fixture unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Ambiguous Bundled Skill Script References" "${output_file}" ||
  ! grep -Fq "<skill-dir>/scripts/check.sh" "${output_file}"; then
  cat "${output_file}" >&2
  echo "placeholder fixture did not produce the expected hard finding" >&2
  exit 1
fi

cp "${fixture_dir}/good-skill.md" "${skill_file}"
cat >>"${skill_file}" <<'EOF'

## Installed use

This deliberately unqualified example exercises the hard finding.

Run scripts/check.sh
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "ambiguous bundled-script fixture unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Run scripts/check.sh" "${output_file}"; then
  cat "${output_file}" >&2
  echo "ambiguous bundled-script fixture did not produce the expected row" >&2
  exit 1
fi

cp "${fixture_dir}/good-skill.md" "${skill_file}"
cat >>"${skill_file}" <<'EOF'

## Installed use

This punctuated sentence exercises the path boundary.

Run scripts/check.sh.
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "punctuated bundled-script fixture unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Run scripts/check.sh." "${output_file}"; then
  cat "${output_file}" >&2
  echo "punctuated bundled-script fixture did not produce the expected row" >&2
  exit 1
fi

echo "Skill drift smoke test passed."
