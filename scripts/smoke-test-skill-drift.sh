#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_source="${repo_dir}/scripts/audit-skill-drift.rb"
baseline_source="${repo_dir}/scripts/audit-skill-drift-command-baseline.tsv"
payload_baseline_source="${repo_dir}/scripts/audit-skill-drift-payload-baseline.tsv"

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required for the skill drift smoke test" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required for the skill drift smoke test" >&2
  exit 1
fi

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/skill-drift-smoke.XXXXXX")"
trap 'rm -rf "${fixture_dir}"' EXIT

mkdir -p "${fixture_dir}/scripts" "${fixture_dir}/skills/example/scripts"
cp "${audit_source}" "${fixture_dir}/scripts/audit-skill-drift.rb"
cp "${baseline_source}" "${fixture_dir}/scripts/audit-skill-drift-command-baseline.tsv"
cp "${payload_baseline_source}" "${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv"
cat >"${fixture_dir}/scripts/audit-skill-drift-command-baseline.tsv" <<'EOF'
# command	path	hit-count
EOF

cat >"${fixture_dir}/scripts/audit-skill-drift-triage.tsv" <<'EOF'
# section	pattern	rationale
Repeated Helper Names	fixture_helper:	The duplicate helper is an intentional advisory fixture.
EOF

cat >"${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv" <<'EOF'
# scope	name	hot-lines	total-lines
skill	example	1000	1000
repository	instructional-markdown	-	10000
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

git -C "${fixture_dir}" init -q
git -C "${fixture_dir}" config user.email smoke@example.invalid
git -C "${fixture_dir}" config user.name "Smoke Test"
git -C "${fixture_dir}" add .
git -C "${fixture_dir}" commit -q -m baseline

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

if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --command-baseline "${fixture_dir}/missing-baseline.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "missing command baseline unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "command baseline not found" "${error_file}"; then
  cat "${error_file}" >&2
  echo "missing command baseline did not produce a stable error" >&2
  exit 1
fi

if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/missing-payload-baseline.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "missing payload baseline unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "payload baseline not found" "${error_file}"; then
  cat "${error_file}" >&2
  echo "missing payload baseline did not produce a stable error" >&2
  exit 1
fi

cp "${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv" \
  "${fixture_dir}/scripts/payload-baseline.clean"
ruby -pi -e 'sub("skill\texample\t1000\t1000", "skill\texample\t1001\t1000")' \
  "${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv"
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "increased payload baseline unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Payload Baseline Increase" "${output_file}" ||
  ! grep -Fq "hot-path limit 1000 -> 1001 lines" "${output_file}"; then
  cat "${output_file}" >&2
  echo "payload baseline increase did not produce the expected hard finding" >&2
  exit 1
fi
cp "${fixture_dir}/scripts/payload-baseline.clean" \
  "${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv"

cat >"${fixture_dir}/low-payload-baseline.tsv" <<'EOF'
# scope	name	hot-lines	total-lines
skill	example	1	1
repository	instructional-markdown	-	1
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/low-payload-baseline.tsv" \
  --strict-hard --hard-only >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "payload growth unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Instructional Payload Growth" "${output_file}" ||
  ! grep -Fq "repository instructional Markdown" "${output_file}"; then
  cat "${output_file}" >&2
  echo "payload growth did not produce the expected hard finding" >&2
  exit 1
fi

cat >"${fixture_dir}/unmatched-baseline.tsv" <<'EOF'
# command	path	hit-count
actionlint	README.md	1
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --command-baseline "${fixture_dir}/unmatched-baseline.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "unmatched command baseline unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "repeated-command baseline and triage labels differ" "${error_file}"; then
  cat "${error_file}" >&2
  echo "unmatched command baseline did not produce a stable error" >&2
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

cat >"${fixture_dir}/scripts/audit-skill-drift-triage.tsv" <<'EOF'
# section	pattern	rationale
Repeated Helper Names	fixture_helper:	The duplicate helper is an intentional advisory fixture.
Repeated Command Guidance	actionlint:	The repeated command is an intentional advisory fixture.
EOF
cat >"${fixture_dir}/scripts/audit-skill-drift-command-baseline.tsv" <<'EOF'
# command	path	hit-count
actionlint	README.md	1
actionlint	skills/example/SKILL.md	1
actionlint	skills/example/reference.md	1
EOF
cat >"${fixture_dir}/README.md" <<'EOF'
Run actionlint for the repository workflow check.
EOF
cat >"${fixture_dir}/skills/example/reference.md" <<'EOF'
Run actionlint for this routed workflow check.
EOF
cp "${fixture_dir}/good-skill.md" "${skill_file}"
cat >>"${skill_file}" <<'EOF'

Run actionlint for this skill workflow check.
EOF

if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "unchanged repeated-command baseline unexpectedly failed" >&2
  exit 1
fi
if ! grep -Fq "Repeated command baselines: 1 stable, 0 expanded" "${output_file}"; then
  cat "${output_file}" >&2
  echo "unchanged repeated-command baseline was not reported as stable" >&2
  exit 1
fi

cat >>"${skill_file}" <<'EOF'
Run actionlint again after changing this path.
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "expanded repeated-command path unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "Repeated Command Growth" "${output_file}" ||
  ! grep -Fq "skills/example/SKILL.md +1" "${output_file}"; then
  cat "${output_file}" >&2
  echo "expanded repeated-command path did not produce a bounded delta" >&2
  exit 1
fi

cp "${fixture_dir}/good-skill.md" "${skill_file}"
cat >>"${skill_file}" <<'EOF'

Run actionlint for this skill workflow check.
EOF
cat >"${fixture_dir}/skills/example/new-path.md" <<'EOF'
Run actionlint from this new path.
EOF
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "new repeated-command path unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "skills/example/new-path.md new (+1)" "${output_file}"; then
  cat "${output_file}" >&2
  echo "new repeated-command path did not produce a bounded delta" >&2
  exit 1
fi

for suffix in 2 3 4 5 6; do
  printf 'Run actionlint from new path %s.\n' "${suffix}" \
    >"${fixture_dir}/skills/example/new-path-${suffix}.md"
done
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "many new repeated-command paths unexpectedly passed" >&2
  exit 1
fi
if ! grep -Fq "+1 more paths" "${output_file}"; then
  cat "${output_file}" >&2
  echo "repeated-command growth output was not bounded" >&2
  exit 1
fi

echo "Skill drift smoke test passed."
