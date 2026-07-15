#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
shell_files=()
python_files=()
ruby_files=()
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
    if ! ruby -e '
      require "yaml"

      path = ARGV.fetch(0)
      skill_name = ARGV.fetch(1)
      data = YAML.safe_load(File.read(path))
      raise "top-level YAML must be a mapping" unless data.is_a?(Hash)

      interface = data["interface"]
      raise "missing interface" unless interface.is_a?(Hash)

      display_name = interface["display_name"]
      short_description = interface["short_description"]
      default_prompt = interface["default_prompt"]

      unless display_name.is_a?(String) && !display_name.empty?
        raise "missing interface.display_name"
      end
      unless short_description.is_a?(String) && !short_description.empty?
        raise "missing interface.short_description"
      end
      unless default_prompt.is_a?(String) && !default_prompt.empty?
        raise "missing interface.default_prompt"
      end
      if display_name.length > 40
        raise "interface.display_name is longer than 40 characters"
      end
      if short_description.length > 80
        raise "interface.short_description is longer than 80 characters"
      end
      unless default_prompt.include?("$#{skill_name}")
        raise "interface.default_prompt should mention $#{skill_name}"
      end
    ' "${skill_dir}/agents/openai.yaml" "${skill_name}"; then
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

if ! ruby -e '
  require "yaml"

  repo = ARGV.fetch(0)
  max_description = 420
  max_total_description = 6_000
  status = 0
  total = 0

  Dir.glob(File.join(repo, "skills", "*", "SKILL.md")).sort.each do |path|
    text = File.read(path, encoding: "UTF-8")
    frontmatter = text.split(/^---\s*$/, 3)[1]
    data = YAML.safe_load(frontmatter)
    description = data.fetch("description")
    total += description.length

    next unless description.length > max_description

    warn "#{path.delete_prefix("#{repo}/")}: description is #{description.length} characters; max is #{max_description}"
    status = 1
  end

  if total > max_total_description
    warn "skill descriptions total #{total} characters; max is #{max_total_description}"
    status = 1
  end

  exit(status)
' "${repo_dir}"; then
  status=1
fi

while IFS= read -r -d '' file; do
  shell_files+=("${file}")
done < <(
  find "${repo_dir}" \
    -path "${repo_dir}/.git" -prune -o \
    -type f \( -name '*.sh' -o -name 'install.sh' \) -print0
)

while IFS= read -r -d '' file; do
  python_files+=("${file}")
done < <(
  find "${repo_dir}/skills" \
    -type f -path '*/scripts/*.py' -print0
)

while IFS= read -r -d '' file; do
  ruby_files+=("${file}")
done < <(
  find "${repo_dir}" \
    -path "${repo_dir}/.git" -prune -o \
    -type f -path '*/scripts/*.rb' -print0
)

while IFS= read -r -d '' file; do
  r_files+=("${file}")
done < <(
  find "${repo_dir}/skills" \
    -type f -path '*/scripts/*.R' -print0
)

for script in "${shell_files[@]}"; do
  if ! bash -n "${script}"; then
    status=1
  fi
done

if ((${#shell_files[@]} > 0)); then
  if ! ruby - "${shell_files[@]}" <<'RUBY'
patterns = [
  ["map" + "file", Regexp.new("\\bmap" + "file\\b")],
  ["read" + "array", Regexp.new("\\bread" + "array\\b")],
  ["local " + "-n", Regexp.new("\\blocal[[:space:]]+-n\\b")],
  ["declare " + "-n", Regexp.new("\\bdeclare[[:space:]]+-n\\b")]
]

status = 0
ARGV.each do |path|
  File.readlines(path, chomp: true).each_with_index do |line, index|
    patterns.each do |label, pattern|
      next unless line.match?(pattern)

      warn "#{path}:#{index + 1}: avoid Bash 4-only #{label}; macOS /bin/bash is Bash 3.2"
      status = 1
    end
  end
end

exit(status)
RUBY
  then
    status=1
  fi
fi

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

if ((${#ruby_files[@]} > 0)); then
  if ! command -v ruby >/dev/null 2>&1; then
    echo "ruby is required to validate bundled Ruby scripts" >&2
    status=1
  else
    for script in "${ruby_files[@]}"; do
      if ! ruby -c "${script}" >/dev/null; then
        status=1
      fi
    done
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

# shellcheck disable=SC2016
if ! ruby -e '
  repo = ARGV.fetch(0)
  skills_dir = File.join(repo, "skills")
  skill_names = Dir.children(skills_dir).select { |name|
    File.directory?(File.join(skills_dir, name))
  }

  markdown_files = Dir.glob([
    File.join(repo, "README.md"),
    File.join(repo, "AGENTS.md"),
    File.join(repo, "docs", "**", "*.md"),
    File.join(repo, "prompts", "**", "*.md"),
    File.join(repo, "skills", "**", "*.md")
  ])

  status = 0
  markdown_files.each do |path|
    text = File.read(path)
    rel_path = path.delete_prefix("#{repo}/")

    text.scan(/\[[^\]\n]+\]\(([^)\s]+)(?:\s+[^)]*)?\)/).each do |match|
      target = match.fetch(0)
      next if target.start_with?("#")
      next if target.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:/)

      target_path = target.sub(/#.*/, "")
      next if target_path.empty?

      resolved = File.expand_path(target_path, File.dirname(path))
      unless File.exist?(resolved)
        warn "#{rel_path}: markdown link target not found: #{target}"
        status = 1
      end
    end

    text.scan(/\$([a-z][a-z0-9]*(?:-[a-z0-9]+)*)/).each do |match|
      skill_ref = match.fetch(0)
      next if skill_ref == "skill-name"
      next if !skill_ref.include?("-") && !skill_names.include?(skill_ref)

      unless skill_names.include?(skill_ref)
        warn "#{rel_path}: unknown skill reference $#{skill_ref}"
        status = 1
      end
    end

    text.scan(/\bskills\/[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*[A-Za-z0-9_-]/).each do |target|
      resolved = File.join(repo, target)
      unless File.exist?(resolved)
        warn "#{rel_path}: repo path not found: #{target}"
        status = 1
      end
    end
  end

  exit(status)
' "${repo_dir}"; then
  status=1
fi

smoke_script="${repo_dir}/scripts/smoke-test-skill-scripts.sh"
if [[ ! -x "${smoke_script}" ]]; then
  echo "${smoke_script}: missing or not executable" >&2
  status=1
elif ! "${smoke_script}"; then
  status=1
fi

installer_smoke_script="${repo_dir}/scripts/smoke-test-installer.sh"
if [[ ! -x "${installer_smoke_script}" ]]; then
  echo "${installer_smoke_script}: missing or not executable" >&2
  status=1
elif ! "${installer_smoke_script}"; then
  status=1
fi

mirror_manifest="${repo_dir}/scripts/mirrored-files.tsv"
if [[ -f "${mirror_manifest}" ]]; then
  while IFS=$'\t' read -r canonical mirror; do
    [[ -z "${canonical}" || "${canonical}" == \#* ]] && continue
    if [[ -z "${mirror}" ]]; then
      echo "${mirror_manifest}: missing mirror path for ${canonical}" >&2
      status=1
      continue
    fi

    canonical_path="${repo_dir}/${canonical}"
    mirror_path="${repo_dir}/${mirror}"
    if [[ ! -f "${canonical_path}" ]]; then
      echo "${mirror_manifest}: canonical file not found: ${canonical}" >&2
      status=1
    elif [[ ! -f "${mirror_path}" ]]; then
      echo "${mirror_manifest}: mirror file not found: ${mirror}" >&2
      status=1
    elif ! cmp -s "${canonical_path}" "${mirror_path}"; then
      echo "${mirror_manifest}: mirrored files differ: ${canonical} ${mirror}" >&2
      status=1
    fi
  done <"${mirror_manifest}"
fi

drift_audit="${repo_dir}/scripts/audit-skill-drift.rb"
if [[ ! -x "${drift_audit}" ]]; then
  echo "${drift_audit}: missing or not executable" >&2
  status=1
elif ! "${drift_audit}" --strict-hard --hard-only; then
  status=1
fi

exit "${status}"
