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
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the skill drift smoke test" >&2
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
# name	reviewed-revision	entry-normalized-characters	total-normalized-characters
example	abcdef0	100000	100000
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
fixture_characters="$(ruby -e 'print File.read(ARGV.fetch(0)).gsub(/\s+/, " ").strip.length' "${skill_file}")"
printf 'example\tabcdef0\t%s\t%s\n' "${fixture_characters}" "${fixture_characters}" \
  >"${fixture_dir}/tight-character-baseline.tsv"
ruby -0777 -pi -e \
  'sub("From this source\nrepository root", "From this source repository\nroot")' \
  "${skill_file}"
if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/tight-character-baseline.tsv" \
  --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "whitespace-only reflow unexpectedly failed strict review" >&2
  exit 1
fi
if ! grep -Fq "SKILL.md ${fixture_characters} (+0), total ${fixture_characters} (+0)" "${output_file}"; then
  cat "${output_file}" >&2
  echo "whitespace-only reflow changed the measured payload" >&2
  exit 1
fi
ruby -pi -e \
  'sub("deterministic drift-audit", "deterministic expanded drift-audit")' \
  "${skill_file}"
if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/tight-character-baseline.tsv" \
  --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "same-line payload growth unexpectedly became a strict finding" >&2
  exit 1
fi
if ! grep -Fq "(+9)" "${output_file}" || ! grep -Fq "No untriaged drift findings." "${output_file}"; then
  cat "${output_file}" >&2
  echo "same-line growth was not visible independently of strict findings" >&2
  exit 1
fi
if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/tight-character-baseline.tsv" \
  --strict-hard --hard-only >"${output_file}" 2>&1 || grep -Fq "Payload review leads" "${output_file}"; then
  cat "${output_file}" >&2
  echo "hard-only output did not preserve its focused contract" >&2
  exit 1
fi
cp "${fixture_dir}/good-skill.md" "${skill_file}"

printf 'example\tabcdef0\t100\t99\n' >"${fixture_dir}/invalid-payload-snapshot.tsv"
if ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/invalid-payload-snapshot.tsv" >"${output_file}" 2>"${error_file}"; then
  echo "invalid payload snapshot unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -Fq "snapshot sizes must be positive with total >= entry" "${error_file}"; then
  cat "${error_file}" >&2
  echo "invalid payload snapshot did not produce a stable diagnostic" >&2
  exit 1
fi

python3 - "${fixture_dir}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
snapshot = root / "scripts/audit-skill-drift-payload-baseline.tsv"
with snapshot.open("a") as rows:
    for index, description in enumerate(["amber", "bronze", "cobalt", "denim", "emerald", "fuchsia"], 1):
        name = f"rank-{index}"
        skill = root / "skills" / name
        (skill / "references").mkdir(parents=True)
        entry = f"---\nname: {name}\ndescription: {description}\n---\n\n# Ranking fixture\n"
        baseline = len(re.sub(r"\s+", " ", entry).strip())
        rows.write(f"{name}\tabcdef0\t{baseline}\t{baseline}\n")
        (skill / "SKILL.md").write_text(entry + "e" * (index * 10) + "\n")
        (skill / "references/details.md").write_text("r" * ((7 - index) * 100) + "\n")
    rows.write("retired-skill\tabcdef0\t100\t100\n")
PY
if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" --strict >"${output_file}" 2>&1; then
  cat "${output_file}" >&2
  echo "payload rankings or a retired skill snapshot unexpectedly blocked strict review" >&2
  exit 1
fi
python3 - "${output_file}" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = {
    "Largest current skill payloads": [f"rank-{index}" for index in range(1, 6)],
    "Largest SKILL.md growth since review": [f"rank-{index}" for index in range(6, 1, -1)],
    "Largest total Markdown growth since review": [f"rank-{index}" for index in range(1, 6)],
}
for heading, names in expected.items():
    start = lines.index(f"  {heading}:") + 1
    actual = []
    for line in lines[start:]:
        if not line.startswith("    "):
            break
        actual.append(line.strip().split(":", 1)[0])
    if actual != names:
        raise SystemExit(f"{heading}: expected {names}, got {actual}")
PY
printf '# no reviewed skills yet\n' >"${fixture_dir}/empty-payload-snapshots.tsv"
if ! ruby "${fixture_dir}/scripts/audit-skill-drift.rb" \
  --payload-baseline "${fixture_dir}/empty-payload-snapshots.tsv" --strict >"${output_file}" 2>&1 ||
  ! grep -Fq "Without review snapshots: example, rank-1" "${output_file}"; then
  cat "${output_file}" >&2
  echo "skills without snapshots were hidden or blocked strict review" >&2
  exit 1
fi
for rank_index in 1 2 3 4 5 6; do
  rm -rf -- "${fixture_dir}/skills/rank-${rank_index}"
done
cp "${fixture_dir}/scripts/payload-baseline.clean" \
  "${fixture_dir}/scripts/audit-skill-drift-payload-baseline.tsv"

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
