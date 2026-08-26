#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version_file="${repo_dir}/.ruby-version"
quiet=0
probe_root=""

usage() {
  cat <<'EOF'
Usage: ./scripts/check-ruby-runtime.sh [--quiet]

Verify the exact repository Ruby contract, executable shebangs and guards, and
direct shebang execution from a conflicting working directory.
EOF
}

die() {
  echo "check-ruby-runtime.sh: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${probe_root}" && -d "${probe_root}" ]]; then
    rm -rf "${probe_root}"
  fi
}
trap cleanup EXIT HUP INT TERM

while (($# > 0)); do
  case "$1" in
    --quiet)
      quiet=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ -f "${version_file}" ]] || die "canonical version file not found: ${version_file}"
IFS= read -r required_ruby_version <"${version_file}" || \
  die "could not read canonical version: ${version_file}"
[[ "${required_ruby_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  die "${version_file}: expected one exact x.y.z Ruby version"
[[ "$(wc -l <"${version_file}" | tr -d ' ')" == "1" ]] || \
  die "${version_file}: expected exactly one line"

required_shebang="#!/usr/bin/env -S RBENV_VERSION=${required_ruby_version} ruby"
required_engine_guard='required_ruby_engine = "ruby"'
required_version_guard="required_ruby_version = \"${required_ruby_version}\""
required_guard_condition='unless required_ruby_engine == RUBY_ENGINE && required_ruby_version == RUBY_VERSION'
executable_count=0

while IFS= read -r -d '' ruby_file; do
  executable_count=$((executable_count + 1))
  IFS= read -r actual_shebang <"${ruby_file}" || die "could not read ${ruby_file}"
  [[ "${actual_shebang}" == "${required_shebang}" ]] || \
    die "${ruby_file}: expected shebang ${required_shebang}"
  grep -Fqx "${required_engine_guard}" "${ruby_file}" || \
    die "${ruby_file}: missing exact CRuby engine guard"
  grep -Fqx "${required_version_guard}" "${ruby_file}" || \
    die "${ruby_file}: guard does not match ${version_file}"
  grep -Fqx "${required_guard_condition}" "${ruby_file}" || \
    die "${ruby_file}: missing exact engine/version guard condition"
done < <(
  find "${repo_dir}/scripts" "${repo_dir}/skills" \
    -type f -name '*.rb' -perm -111 -print0
)

[[ "${executable_count}" -gt 0 ]] || die "no executable Ruby programs found"

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-ruby-runtime.XXXXXX")"
probe_file="${probe_root}/probe.rb"
conflict_dir="${probe_root}/conflict"
mkdir -p "${conflict_dir}"
printf '%s\n' '0.0.0-unavailable' >"${conflict_dir}/.ruby-version"

{
  printf '%s\n' "${required_shebang}"
  cat <<RUBY
# frozen_string_literal: true

required_ruby_engine = "ruby"
required_ruby_version = "${required_ruby_version}"
unless required_ruby_engine == RUBY_ENGINE && required_ruby_version == RUBY_VERSION
  warn "probe.rb: CRuby #{required_ruby_version} is required; detected #{RUBY_DESCRIPTION}"
  warn "probe.rb: resolved interpreter: #{RbConfig.ruby}"
  exit 1
end

puts [RUBY_ENGINE, RUBY_VERSION, RbConfig.ruby, ENV.fetch("RBENV_VERSION", "")].join("\\t")
RUBY
} >"${probe_file}"
chmod 755 "${probe_file}"

if ! probe_output="$(cd "${conflict_dir}" && "${probe_file}" 2>&1)"; then
  die "direct shebang probe failed from a conflicting working directory: ${probe_output}"
fi

IFS=$'\t' read -r actual_engine actual_version resolved_ruby selected_version <<<"${probe_output}"
[[ "${actual_engine}" == "ruby" ]] || die "expected CRuby, found ${actual_engine:-unknown}"
[[ "${actual_version}" == "${required_ruby_version}" ]] || \
  die "expected Ruby ${required_ruby_version}, found ${actual_version:-unknown}"
[[ -n "${resolved_ruby}" ]] || die "probe did not report the resolved interpreter"
[[ "${selected_version}" == "${required_ruby_version}" ]] || \
  die "shebang did not export RBENV_VERSION=${required_ruby_version}"

if [[ "${quiet}" -eq 0 ]]; then
  ruby_command="$(command -v ruby 2>/dev/null || true)"
  provider="direct"
  if [[ "${ruby_command}" == */.rbenv/shims/ruby || "${ruby_command}" == */shims/ruby ]]; then
    provider="rbenv-shim"
  fi
  echo "Ruby runtime policy passed: CRuby ${actual_version} via ${resolved_ruby} (PATH: ${ruby_command:-unresolved}; ${provider})"
fi
