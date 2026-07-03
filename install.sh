#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
target_dir="${codex_home}/skills"

mkdir -p "${target_dir}"

shopt -s nullglob
for skill_dir in "${repo_dir}"/skills/*; do
  [[ -d "${skill_dir}" ]] || continue
  skill_name="$(basename "${skill_dir}")"
  rm -rf "${target_dir:?}/${skill_name}"
  cp -a "${skill_dir}" "${target_dir}/"
done

find "${target_dir}" -path '*/scripts/*.sh' -type f -exec chmod +x {} +

echo "Installed skills from ${repo_dir}/skills to ${target_dir}"
