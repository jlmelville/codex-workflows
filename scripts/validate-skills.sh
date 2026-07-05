#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
shell_files=()
python_files=()
r_files=()

shopt -s nullglob
for skill_dir in "${repo_dir}"/skills/*; do
  [[ -d "${skill_dir}" ]] || continue
  skill_name="$(basename "${skill_dir}")"
  skill_file="${skill_dir}/SKILL.md"

  if [[ ! -f "${skill_file}" ]]; then
    echo "${skill_name}: missing SKILL.md" >&2
    status=1
    continue
  fi

  if ! ruby -e '
    require "yaml"
    path = ARGV.fetch(0)
    text = File.read(path)
    frontmatter = text.split(/^---\s*$/, 3)[1]
    raise "missing YAML frontmatter" unless frontmatter
    data = YAML.safe_load(frontmatter)
    raise "missing name" unless data["name"].is_a?(String) && !data["name"].empty?
    raise "missing description" unless data["description"].is_a?(String) && !data["description"].empty?
    raise "skill name must match folder" unless data["name"] == ARGV.fetch(1)
  ' "${skill_file}" "${skill_name}"; then
    status=1
  fi

  if [[ -f "${skill_dir}/agents/openai.yaml" ]]; then
    if ! ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "${skill_dir}/agents/openai.yaml"; then
      status=1
    fi
  fi

  for script in "${skill_dir}"/scripts/*.sh; do
    [[ -f "${script}" ]] || continue
    if [[ ! -x "${script}" ]]; then
      echo "${script}: should be executable" >&2
      status=1
    fi
  done
done

mapfile -d '' shell_files < <(
  find "${repo_dir}" \
    -path "${repo_dir}/.git" -prune -o \
    -type f \( -name '*.sh' -o -name 'install.sh' \) -print0
)

mapfile -d '' python_files < <(
  find "${repo_dir}/skills" \
    -type f -path '*/scripts/*.py' -print0
)

mapfile -d '' r_files < <(
  find "${repo_dir}/skills" \
    -type f -path '*/scripts/*.R' -print0
)

for script in "${shell_files[@]}"; do
  if ! bash -n "${script}"; then
    status=1
  fi
done

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is required for repository validation" >&2
  status=1
elif ((${#shell_files[@]} > 0)); then
  if ! shellcheck "${shell_files[@]}"; then
    status=1
  fi
fi

if ((${#python_files[@]} > 0)); then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to validate bundled Python scripts" >&2
    status=1
  else
    if ! python3 - "${python_files[@]}" <<'PY'
import pathlib
import sys

status = 0
for path_text in sys.argv[1:]:
    path = pathlib.Path(path_text)
    try:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    except SyntaxError as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        status = 1

sys.exit(status)
PY
    then
      status=1
    fi
  fi
fi

if ((${#r_files[@]} > 0)); then
  if ! command -v Rscript >/dev/null 2>&1; then
    echo "Rscript is required to validate bundled R scripts" >&2
    status=1
  elif ! Rscript --vanilla -e '
    status <- 0L
    for (path in commandArgs(TRUE)) {
      tryCatch(
        invisible(parse(file = path)),
        error = function(e) {
          message(path, ": ", conditionMessage(e))
          status <<- 1L
        }
      )
    }
    quit(status = status)
  ' "${r_files[@]}"; then
    status=1
  fi
fi

generic_actions_audit="${repo_dir}/skills/github-actions-hardening/scripts/audit-actions.sh"
r_actions_audit="${repo_dir}/skills/r-ci-hardening/scripts/audit-actions.sh"
if [[ -f "${generic_actions_audit}" && -f "${r_actions_audit}" ]] &&
  ! cmp -s "${generic_actions_audit}" "${r_actions_audit}"; then
  echo "audit-actions.sh mirrors differ; update both or document why validation should change" >&2
  status=1
fi

exit "${status}"
