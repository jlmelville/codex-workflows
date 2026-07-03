#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
shell_files=()

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

exit "${status}"
