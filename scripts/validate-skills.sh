#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
shell_files=()
python_files=()
ruby_files=()
r_files=()
validation_output_counter=0
validation_output_files=()
validation_output_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-skill-validation.XXXXXX")"

# shellcheck disable=SC2317,SC2329  # Invoked by the EXIT trap.
cleanup_validation_outputs() {
  if ((${#validation_output_files[@]} > 0)); then
    rm -f "${validation_output_files[@]}"
  fi
  rmdir "${validation_output_dir}" 2>/dev/null || true
}
trap cleanup_validation_outputs EXIT

run_check() {
  local check_output
  local check_status

  validation_output_counter=$((validation_output_counter + 1))
  check_output="${validation_output_dir}/${validation_output_counter}.out"
  validation_output_files+=("${check_output}")
  if "$@" >"${check_output}" 2>&1; then
    return 0
  else
    check_status=$?
  fi

  if [[ -s "${check_output}" ]]; then
    cat "${check_output}" >&2
  else
    echo "$1 failed with status ${check_status}" >&2
  fi
  return "${check_status}"
}

ruby_policy_checker="${repo_dir}/scripts/check-ruby-runtime.sh"
if [[ ! -x "${ruby_policy_checker}" ]]; then
  echo "${ruby_policy_checker}: missing or not executable" >&2
  exit 1
fi
if ! run_check "${ruby_policy_checker}" --quiet; then
  exit 1
fi
IFS= read -r required_ruby_version <"${repo_dir}/.ruby-version"
export RBENV_VERSION="${required_ruby_version}"
export BUNDLE_GEMFILE="${repo_dir}/Gemfile"
cd "${repo_dir}"

parity_script="${repo_dir}/scripts/check-ci-tool-parity.sh"
if [[ ! -x "${parity_script}" ]]; then
  echo "${parity_script}: missing or not executable" >&2
  status=1
elif ! "${parity_script}" --quiet; then
  status=1
fi

shopt -s nullglob

metadata_validator="${repo_dir}/scripts/validate-skill-metadata.rb"
if [[ ! -x "${metadata_validator}" ]]; then
  echo "${metadata_validator}: missing or not executable" >&2
  status=1
elif ! run_check "${metadata_validator}" "${repo_dir}"; then
  status=1
fi

markdown_validator="${repo_dir}/scripts/validate-markdown-references.rb"
if [[ ! -x "${markdown_validator}" ]]; then
  echo "${markdown_validator}: missing or not executable" >&2
  status=1
elif ! run_check "${markdown_validator}" "${repo_dir}"; then
  status=1
fi

for skill_dir in "${repo_dir}"/skills/*; do
  [[ -d "${skill_dir}" ]] || continue

  for script in "${skill_dir}"/scripts/*.sh; do
    [[ -f "${script}" ]] || continue
    if [[ ! -x "${script}" ]]; then
      echo "${script}: should be executable" >&2
      status=1
    fi
  done
done

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
  if ! run_check bash -n "${script}"; then
    status=1
  fi
done

if ((${#shell_files[@]} > 0)); then
  if ! run_check ruby - "${shell_files[@]}" <<'RUBY'
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
  if ! run_check shellcheck "${shell_files[@]}"; then
    status=1
  fi
fi

if ((${#python_files[@]} > 0)); then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to validate bundled Python scripts" >&2
    status=1
  else
    if ! run_check python3 - "${python_files[@]}" <<'PY'
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
      if ! run_check ruby -c "${script}"; then
        status=1
      fi
    done

    bundler=()
    ruby_series="$(ruby -e 'print RUBY_VERSION[/\A\d+\.\d+/]')"
    if command -v bundle >/dev/null 2>&1; then
      bundler=(bundle)
    elif command -v "bundle${ruby_series}" >/dev/null 2>&1; then
      bundler=("bundle${ruby_series}")
    else
      echo "bundler is required to validate Ruby style" >&2
      status=1
    fi

    if ((${#bundler[@]} > 0)); then
      bundle_identity_errors="${validation_output_dir}/bundler-identity.err"
      validation_output_files+=("${bundle_identity_errors}")
      if bundle_ruby_identity="$("${bundler[@]}" exec ruby -e \
        'print [RUBY_ENGINE, RUBY_VERSION, RbConfig.ruby].join("\t")' \
        2>"${bundle_identity_errors}")"; then
        IFS=$'\t' read -r bundle_ruby_engine bundle_ruby_version bundle_ruby_path \
          <<<"${bundle_ruby_identity}"
        if [[ "${bundle_ruby_engine}" != "ruby" || "${bundle_ruby_version}" != "${required_ruby_version}" ]]; then
          if [[ -s "${bundle_identity_errors}" ]]; then
            cat "${bundle_identity_errors}" >&2
          fi
          echo "Bundler must use CRuby ${required_ruby_version}; found ${bundle_ruby_engine} ${bundle_ruby_version} via ${bundle_ruby_path}" >&2
          status=1
        fi
      else
        if [[ -n "${bundle_ruby_identity}" ]]; then
          printf '%s' "${bundle_ruby_identity}" >&2
        fi
        if [[ -s "${bundle_identity_errors}" ]]; then
          cat "${bundle_identity_errors}" >&2
        else
          echo "Bundler Ruby identity check failed" >&2
        fi
        status=1
      fi

      tmp_cache_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
      standard_cache="${XDG_CACHE_HOME:-${tmp_cache_root}/codex-standard-cache}"
      if ! run_check env XDG_CACHE_HOME="${standard_cache}" \
        "${bundler[@]}" exec ruby \
        -rrubygems \
        -e 'load Gem.activate_bin_path("standard", "standardrb")' \
        -- --format quiet "${ruby_files[@]}"; then
        status=1
      fi
    fi
  fi
fi

if ((${#r_files[@]} > 0)); then
  if ! command -v Rscript >/dev/null 2>&1; then
    echo "Rscript is required to validate bundled R scripts" >&2
    status=1
  elif ! run_check Rscript --vanilla -e '
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

smoke_scripts=(
  "${repo_dir}/scripts/smoke-test-skill-scripts.sh"
  "${repo_dir}/scripts/smoke-test-installer.sh"
  "${repo_dir}/scripts/smoke-test-skill-drift.sh"
)
smoke_pids=()
smoke_outputs=()

for index in "${!smoke_scripts[@]}"; do
  smoke_script="${smoke_scripts[${index}]}"
  if [[ ! -x "${smoke_script}" ]]; then
    echo "${smoke_script}: missing or not executable" >&2
    status=1
    continue
  fi

  smoke_output="${validation_output_dir}/smoke-${index}.out"
  "${smoke_script}" >"${smoke_output}" 2>&1 &
  smoke_pids+=("$!")
  smoke_outputs+=("${smoke_output}")
  validation_output_files+=("${smoke_output}")
done

for index in "${!smoke_pids[@]}"; do
  if ! wait "${smoke_pids[${index}]}"; then
    cat "${smoke_outputs[${index}]}" >&2
    status=1
  fi
done

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
elif ! run_check "${drift_audit}" --strict-hard --hard-only; then
  status=1
fi

if [[ "${status}" -eq 0 ]]; then
  echo "Skill repository validation passed."
fi
exit "${status}"
