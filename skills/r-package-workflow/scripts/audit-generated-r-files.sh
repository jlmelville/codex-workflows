#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "audit-generated-r-files.sh: not inside a git worktree" >&2
  exit 2
fi

git status --short -- \
  R/RcppExports.R src/RcppExports.cpp \
  R/cpp11.R src/cpp11.cpp \
  NAMESPACE 'man/*.Rd' docs 2>/dev/null || true
