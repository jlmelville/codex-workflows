#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: observe-long-r-process.sh PID [--state-root PATH]...

Print one read-only Linux snapshot of a long-running process, its descendants,
optional state-root freshness, and filesystem capacity. The command never
signals, restarts, or otherwise controls the observed process.

Arguments:
  PID                Positive process ID to observe.
  --state-root PATH  Existing directory whose five newest files and capacity
                     should be reported. May be repeated; prefer narrow roots.
  -h, --help         Show this help.
EOF
}

fail_usage() {
  echo "$1" >&2
  usage >&2
  exit 2
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "observe-long-r-process.sh: required command not found: ${command_name}" >&2
    exit 1
  fi
}

parent_pid=""
state_roots=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --state-root)
      [[ "$#" -ge 2 ]] || fail_usage "observe-long-r-process.sh: --state-root requires a path"
      [[ -n "$2" ]] || fail_usage "observe-long-r-process.sh: --state-root requires a non-empty path"
      [[ -d "$2" ]] || fail_usage "observe-long-r-process.sh: state root is not a directory: $2"
      state_roots+=("$2")
      shift 2
      ;;
    --*)
      fail_usage "observe-long-r-process.sh: unknown option: $1"
      ;;
    *)
      [[ -z "${parent_pid}" ]] || fail_usage "observe-long-r-process.sh: unexpected argument: $1"
      parent_pid="$1"
      shift
      ;;
  esac
done

[[ -n "${parent_pid}" ]] || fail_usage "observe-long-r-process.sh: PID is required"
[[ "${parent_pid}" =~ ^[1-9][0-9]*$ ]] || fail_usage "observe-long-r-process.sh: PID must be a positive integer"
[[ "$(uname -s)" == "Linux" ]] || {
  echo "observe-long-r-process.sh: Linux is required" >&2
  exit 1
}

for command_name in awk date df find mktemp ps readlink sed sort uname; do
  require_command "${command_name}"
done

resolved_state_roots=()
if [[ "${#state_roots[@]}" -gt 0 ]]; then
  for state_root in "${state_roots[@]}"; do
    resolved_state_roots+=("$(readlink -f -- "${state_root}")")
  done
fi

snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/observe-long-r-process.XXXXXX")"
cleanup() {
  rm -rf "${snapshot_dir}"
}
trap cleanup EXIT

process_snapshot="${snapshot_dir}/processes.tsv"
parent_snapshot="${snapshot_dir}/parent.tsv"
descendant_snapshot="${snapshot_dir}/descendants.tsv"
sorted_descendants="${snapshot_dir}/descendants-sorted.tsv"

ps -eo pid=,ppid=,etimes=,pcpu=,pmem=,stat=,args= | awk '
  BEGIN { OFS = "\t" }
  {
    command = $7
    for (field = 8; field <= NF; field++) {
      command = command " " $field
    }
    print $1, $2, $3, $4, $5, $6, command
  }
' >"${process_snapshot}"

awk -F '\t' -v target="${parent_pid}" '$1 == target { print; found = 1 } END { exit(found ? 0 : 1) }' \
  "${process_snapshot}" >"${parent_snapshot}" || {
    echo "observe-long-r-process.sh: process is not running or not visible: ${parent_pid}" >&2
    exit 1
  }

awk -F '\t' -v target="${parent_pid}" '
  {
    process_id[NR] = $1
    parent_id[NR] = $2
    row[NR] = $0
  }
  END {
    included[target] = 1
    do {
      changed = 0
      for (record = 1; record <= NR; record++) {
        if (!included[process_id[record]] && included[parent_id[record]]) {
          included[process_id[record]] = 1
          changed = 1
        }
      }
    } while (changed)
    for (record = 1; record <= NR; record++) {
      if (process_id[record] != target && included[process_id[record]]) {
        print row[record]
      }
    }
  }
' "${process_snapshot}" >"${descendant_snapshot}"
sort -t $'\t' -k4,4nr -k1,1n "${descendant_snapshot}" >"${sorted_descendants}"

descendant_count="$(awk 'END { print NR }' "${sorted_descendants}")"
printf 'snapshot_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'process_columns\tpid\tppid\telapsed_s\tcpu_pct\tmem_pct\tstate\tcommand\n'
printf 'parent\t'
cat "${parent_snapshot}"
printf 'descendant_count\t%s\n' "${descendant_count}"
sed -n '1,20{s/^/descendant\t/;p;}' "${sorted_descendants}"
if [[ "${descendant_count}" -gt 20 ]]; then
  printf 'descendants_omitted\t%s\n' "$((descendant_count - 20))"
fi

printf 'state_root_count\t%s\n' "${#resolved_state_roots[@]}"
if [[ "${#resolved_state_roots[@]}" -gt 0 ]]; then
  printf 'filesystem_columns\ttotal_kib\tused_kib\tavailable_kib\tuse_pct\tmount\n'
  printf 'newest_file_columns\ttimestamp\tsize_bytes\tpath\n'
  root_index=0
  snapshot_status=0
  for state_root in "${resolved_state_roots[@]}"; do
    root_index=$((root_index + 1))
    newest_snapshot="${snapshot_dir}/newest-${root_index}.tsv"
    find_errors="${snapshot_dir}/find-${root_index}.stderr"
    printf 'state_root\t%s\n' "${state_root}"
    df -Pk -- "${state_root}" | awk 'NR == 2 {
      printf "filesystem_kib\t%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $6
    }'
    if LC_ALL=C TZ=UTC find "${state_root}" \
      -path "${snapshot_dir}" -prune -o -type f \
      -printf '%T@\t%TY-%Tm-%TdT%TH:%TM:%TS%TZ\t%s\t%p\n' \
      2>"${find_errors}" | sort -t $'\t' -k1,1nr >"${newest_snapshot}"; then
      printf 'state_root_scan\tcomplete\n'
    else
      printf 'state_root_scan\tpartial\n'
      echo "observe-long-r-process.sh: could not read every file under state root: ${state_root}" >&2
      snapshot_status=1
    fi
    if [[ -s "${newest_snapshot}" ]]; then
      sed -n '1,5{s/^[^\t]*\t/newest_file\t/;p;}' "${newest_snapshot}"
    else
      printf 'newest_file\tnone\n'
    fi
  done
  exit "${snapshot_status}"
fi
